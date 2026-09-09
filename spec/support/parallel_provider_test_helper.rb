# frozen_string_literal: true

require_relative "test_environment"

# Provider constants for filtering
CLI_PROVIDERS = TestEnvironment::CLI_PROVIDERS
HTTP_PROVIDERS = TestEnvironment::HTTP_PROVIDERS

begin
  require "parallel"
rescue LoadError
  # Parallel gem not available - will run sequentially
end

module ParallelProviderTestHelper
  extend self

  # Maximum parallel processes (cap at 8 for resource management)
  MAX_PARALLEL_PROCESSES = 8

  # Check if parallel testing is available
  def parallel_available?
    defined?(Parallel) && Parallel.processor_count > 1
  end

  # Get optimal number of parallel processes
  def parallel_process_count
    return 1 unless parallel_available?

    [Parallel.processor_count, MAX_PARALLEL_PROCESSES].min
  end

  # Check if provider filtering is enabled via environment variable
  def provider_filter_enabled?
    provider_filter && !provider_filter.empty?
  end

  def provider_filter
    ENV["IMGFLOW_TEST_PROVIDER"] || ENV.fetch("TEST_PROVIDER", nil)
  end

  # Get filtered provider list
  def filtered_providers(all_providers)
    return all_providers unless provider_filter_enabled?

    all_providers.select { |provider| provider.to_s.downcase == provider_filter.downcase }
  end

  # Run tests across providers in parallel
  def run_providers_parallel(providers, options = {}, &)
    # Apply provider filtering if enabled
    test_providers = filtered_providers(providers)

    return if test_providers.empty?

    # ⚠️ NEVER run performance benchmarks in parallel!
    # Check if this is a performance test and force sequential execution
    if performance_test?

      use_parallel = false
      process_count = 1
    else
      # Determine execution mode
      use_parallel = options.fetch(:parallel, parallel_available?)
      process_count = options.fetch(:processes, parallel_process_count)
    end

    if use_parallel && test_providers.length > 1
      run_parallel(test_providers, process_count, &)
    else
      run_sequential(test_providers, &)
    end
  end

  # Get available providers from config
  def providers
    site_config = TEST_CONFIG.dup
    mock_site = MockSite.new(site_config)
    config = JekyllImgFlow::Config.new(mock_site)
    config.backend_priority
  end

  # Filter providers by type (CLI vs HTTP)
  def filter_providers_by_type(providers, type = :all)
    case type
    when :cli
      providers.select { |p| CLI_PROVIDERS.include?(p) }
    when :http
      providers.select { |p| HTTP_PROVIDERS.include?(p) }
    when :available
      # Only return providers that are actually available
      providers.select { |p| provider_available?(p) }
    else
      providers
    end
  end

  # Check if a specific provider is available
  def provider_available?(provider_name)
    case provider_name
    when "sharp"
      system("which sharp > /dev/null 2>&1")
    when "imagemagick"
      system("which magick > /dev/null 2>&1") || system("which convert > /dev/null 2>&1")
    when "libvips"
      system("which vips > /dev/null 2>&1")
    when "imgproxy", "weserv", "flyimg"
      # HTTP providers - check if service is running
      check_http_service(provider_name)
    else
      false
    end
  end

  # Check if current test is a performance benchmark
  def performance_test?
    # Check if PERFORMANCE env var is set (performance tests use this)
    ENV["PERFORMANCE"] == "true" ||
      # Check if RSpec example description contains "performance" or "benchmark"
      (defined?(RSpec) && RSpec.current_example &&
       (RSpec.current_example.metadata[:description] =~ /performance|benchmark/i ||
        RSpec.current_example.metadata[:file_path] =~ /performance.*spec\.rb/))
  end

  private

  def run_parallel(providers, process_count)
    start_time = Time.now

    results = Parallel.map(providers, in_threads: process_count) do |provider|
      provider_start = Time.now
      begin
        yield(provider)
        duration = Time.now - provider_start

        { provider: provider, status: :success, duration: duration }
      rescue StandardError => e
        duration = Time.now - provider_start

        { provider: provider, status: :failed, duration: duration, error: e }
      end
    end

    total_duration = Time.now - start_time
    print_summary(results, total_duration, parallel: true)

    # Re-raise first error if any failed
    failed = results.find { |r| r[:status] == :failed }
    raise failed[:error] if failed
  end

  def run_sequential(providers)
    start_time = Time.now

    results = providers.map do |provider|
      provider_start = Time.now
      begin
        yield(provider)
        duration = Time.now - provider_start

        { provider: provider, status: :success, duration: duration }
      rescue StandardError => e
        duration = Time.now - provider_start

        { provider: provider, status: :failed, duration: duration, error: e }
      end
    end

    total_duration = Time.now - start_time
    print_summary(results, total_duration, parallel: false)

    # Re-raise first error if any failed
    failed = results.find { |r| r[:status] == :failed }
    raise failed[:error] if failed
  end

  def print_summary(results, total_duration, parallel: false)
    return unless ENV["DEBUG"]

    results.count { |r| r[:status] == :success }
    results.count { |r| r[:status] == :failed }

    return unless parallel && results.length > 1

    sequential_time = results.sum { |r| r[:duration] }
    sequential_time / total_duration
  end

  def check_http_service(provider_name)
    require "net/http"

    response = Net::HTTP.get_response(URI(TestEnvironment.docker_url(provider_name)))
    response.is_a?(Net::HTTPResponse)
  rescue StandardError
    false
  end
end
