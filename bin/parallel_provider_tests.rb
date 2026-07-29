#!/usr/bin/env ruby
# frozen_string_literal: true

require "parallel"
require "rspec/core"
require "ostruct"

# Mock site class for testing
MockSite = Struct.new(:config)

# Parallel provider test runner
class ParallelProviderRunner
  def initialize(test_file)
    @test_file = test_file
    @providers = providers
  end

  def run
    if parallel_available?
      puts "🔧 Running #{@providers.length} providers in parallel (#{Parallel.processor_count} processes)"

      results = Parallel.map(@providers, in_threads: Parallel.processor_count) do |provider|
        run_provider_tests(provider)
      end

    else
      puts "🔧 Running #{@providers.length} providers sequentially"
      results = @providers.map { |provider| run_provider_tests(provider) }
    end
    summarize_results(results)
  end

  private

  def parallel_available?
    defined?(Parallel) && Parallel.processor_count > 1
  end

  def providers
    # Load test config to get providers
    require_relative "test_config"

    site_config = TEST_CONFIG.dup
    mock_site = MockSite.new(site_config)
    config = JekyllImgFlow::Config.new(mock_site)
    config.backend_priority
  end

  def run_provider_tests(provider)
    start_time = Time.now

    begin
      puts "  🔄 Testing #{provider}..."

      # Set environment variable for the provider
      ENV["TEST_PROVIDER"] = provider

      # Run RSpec with provider filter
      result = system("bundle exec rspec #{@test_file} --format documentation")

      duration = Time.now - start_time

      if result
        puts "  ✅ #{provider} completed (#{duration.round(2)}s)"
        { provider: provider, status: :passed, duration: duration }
      else
        puts "  ❌ #{provider} failed (#{duration.round(2)}s)"
        { provider: provider, status: :failed, duration: duration }
      end
    rescue StandardError => e
      duration = Time.now - start_time
      puts "  ❌ #{provider} error: #{e.message} (#{duration.round(2)}s)"
      { provider: provider, status: :error, duration: duration, error: e.message }
    ensure
      # Clean up environment variable
      ENV.delete("TEST_PROVIDER")
    end
  end

  def summarize_results(results)
    puts "\n📊 Test Results Summary:"
    puts "=" * 50

    passed = results.count { |r| r[:status] == :passed }
    failed = results.count { |r| r[:status] == :failed }
    errors = results.count { |r| r[:status] == :error }
    total_duration = results.sum { |r| r[:duration] }

    puts "✅ Passed: #{passed}"
    puts "❌ Failed: #{failed}"
    puts "💥 Errors: #{errors}"
    puts "⏱️  Total time: #{total_duration.round(2)}s"

    puts "🚀 Parallel speedup: #{(results.sum { |r| r[:duration] } / total_duration).round(2)}x" if parallel_available?

    # Show individual results
    puts "\n📋 Individual Results:"
    status_icons = {
      passed: "✅",
      failed: "❌",
      error: "💥"
    }

    results.each do |result|
      status_icon = status_icons[result[:status]] || "❓"

      puts "  #{status_icon} #{result[:provider]}: #{result[:duration].round(2)}s"
      puts "    Error: #{result[:error]}" if result[:error]
    end

    # Exit with appropriate code
    exit_code = (failed + errors).positive? ? 1 : 0
    exit(exit_code)
  end
end

# Run the parallel tests if this script is executed directly
if __FILE__ == $PROGRAM_NAME
  test_file = ARGV[0] || "spec/picture_tag_integration_spec.rb"

  unless File.exist?(test_file)
    puts "❌ Test file not found: #{test_file}"
    exit(1)
  end

  runner = ParallelProviderRunner.new(test_file)
  runner.run
end
