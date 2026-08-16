# frozen_string_literal: true

require "simplecov"
require "ostruct"
require "fastimage"
require_relative "../scripts/test_logger"
require_relative "support/test_directory_helper"
require_relative "support/test_pictures"

# Auto-start test logging for all test runs
TestLogger.auto_start

SimpleCov.start do
  skip "/spec/"
end

# Constants for performance optimization
HTTP_API_PROVIDERS = %w[Imgproxy Weserv Flyimg].freeze
CLI_TOOLS = %w[Sharp Imagemagick Libvips].freeze

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "rspec"
require "jekyll-imgflow"
require "jekyll-imgflow/tags/base_tag"
require "jekyll-imgflow/tags/crop_tag"
require "jekyll-imgflow/tags/format_tag"
require "jekyll-imgflow/tags/opacity_tag"
require "jekyll-imgflow/tags/optimize_tag"
require "jekyll-imgflow/tags/quality_tag"
require "jekyll-imgflow/tags/resize_tag"
require "jekyll-imgflow/tags/watermark_tag"
require "test_config"
require "webmock/rspec"
require "jekyll"

WebMock.disable_net_connect!(allow_localhost: true)

# Parallel Testing Configuration
SINGLE_TEST_PORT = 4000        # Port for non-parallel tests
PARALLEL_PORT_BASE = 4010      # Base port for parallel tests (4010-4018)

# Auto-detect CPU cores and use n-1 for parallel testing
# Can be overridden with IMGFLOW_MAX_PARALLEL_PROCESSES environment variable
# Maximum of 8 parallel processes to prevent excessive resource usage
def detect_max_parallel_processes
  if ENV["IMGFLOW_MAX_PARALLEL_PROCESSES"]
    ENV["IMGFLOW_MAX_PARALLEL_PROCESSES"].to_i
  else
    # Detect number of CPU cores
    cpu_count = case RbConfig::CONFIG["host_os"]
                when /darwin|mac os/
                  `sysctl -n hw.ncpu`.to_i
                when /linux/
                  `nproc`.to_i
                else
                  # Fallback to Ruby's processor count
                  require "etc"
                  Etc.nprocessors
                end

    # Use n-1 cores (leave one for system), with a maximum of 8
    (cpu_count - 1).clamp(1, 8)
  end
end

MAX_PARALLEL_PROCESSES = detect_max_parallel_processes
ACTIVE_SERVERS = {}.freeze
PREBUILT_SITES = {}.freeze

# Process-specific test site registry for parallel execution
class TestSiteRegistry
  include Singleton

  attr_accessor :prebuilt_sites, :test_file_server

  def initialize
    @prebuilt_sites = {}
  end

  def add_site(index, site_data)
    @prebuilt_sites[index] = site_data
  end

  def get_site(index)
    @prebuilt_sites[index]
  end

  def clear_sites
    @prebuilt_sites.clear
  end

  def any_sites?
    @prebuilt_sites.any?
  end

  def sites_count
    @prebuilt_sites.length
  end

  # Make singleton process-specific by using process ID
  def self.instance
    @instances ||= {}
    process_id = Process.pid
    @instances[process_id] ||= new
  end

  # Clean up instances when process exits
  def self.cleanup_instance
    process_id = Process.pid
    @instances&.delete(process_id)
  end
end

# Detect actual CPU count for display
DETECTED_CPU_CORES = case RbConfig::CONFIG["host_os"]
                     when /darwin|mac os/
                       `sysctl -n hw.ncpu`.to_i
                     when /linux/
                       `nproc`.to_i
                     else
                       require "etc"
                       Etc.nprocessors
                     end

# Global methods for RSpec configuration (outside module scope)
def prebuild_test_sites
  ProviderTestHelpers.prebuild_test_sites
end

def prebuilt_site
  ProviderTestHelpers.prebuilt_site
end

# Get port for current test process
def test_port
  test_env_number = ENV.fetch("TEST_ENV_NUMBER", nil)
  if test_env_number.nil? || test_env_number.empty?
    SINGLE_TEST_PORT # Non-parallel test uses port 4000
  else
    PARALLEL_PORT_BASE + test_env_number.to_i # Parallel tests use 4010, 4011, etc.
  end
end

# Signal handling for cleanup when tests are canceled
def setup_signal_handlers
  %w[INT TERM].each do |signal|
    trap(signal) do
      cleanup_all_servers
      exit(1)
    end
  end
end

# Ensure cleanup on exit (covers normal exit, exceptions, etc.)
at_exit do
  cleanup_all_test_artifacts
end

# Clean up all active servers with enhanced error handling and process isolation
def cleanup_all_servers
  return if ACTIVE_SERVERS.empty?

  # Create a copy to avoid modification during iteration
  servers_to_cleanup = ACTIVE_SERVERS.dup

  servers_to_cleanup.each do |port, server_info|
    # Kill by port first (most reliable)
    system("lsof -ti:#{port} | xargs kill -9 2>/dev/null")

    # Also try to kill the tracked PID
    if server_info[:pid]
      begin
        Process.kill("TERM", server_info[:pid])
      rescue StandardError
        nil
      end
      begin
        Process.wait(server_info[:pid])
      rescue StandardError
        nil
      end
    end

    # Remove from tracking immediately
    ACTIVE_SERVERS.delete(port)
  rescue Errno::ESRCH, Errno::ECHILD
    # Process already gone - still remove from tracking
    ACTIVE_SERVERS.delete(port)
    nil
  rescue StandardError
    # Still try to remove from tracking to prevent accumulation
    ACTIVE_SERVERS.delete(port) if ENV["DEBUG"]
  end

  # Final safety clear
  ACTIVE_SERVERS.clear if ACTIVE_SERVERS.any?
end

# Manual cleanup for orphaned servers (can be called from command line)
def cleanup_orphaned_servers
  # Kill any remaining Jekyll processes on test ports
  ports_to_check = [SINGLE_TEST_PORT] +
                   (PARALLEL_PORT_BASE..(PARALLEL_PORT_BASE + MAX_PARALLEL_PROCESSES - 1)).to_a

  ports_to_check.each do |port|
    # Check if port is in use
    require "socket"
    server = TCPServer.new("127.0.0.1", port)
    server.close
  rescue Errno::EADDRINUSE
    # Port is in use, try to kill the process

    system("lsof -ti:#{port} | xargs kill -9 2>/dev/null")
  end
end

# Get local tmp directory for test artifacts
def local_tmp_dir
  @local_tmp_dir ||= File.expand_path("../tmp", __dir__)
end

# Cleanup pre-built test sites with enhanced error handling
def cleanup_prebuilt_sites
  base_tmp_dir = File.join(local_tmp_dir, "test_sites")
  if File.exist?(base_tmp_dir)

    begin
      FileUtils.rm_rf(base_tmp_dir)
    rescue StandardError
    ensure
      # Always clear the tracking hash, even if file cleanup fails
      TestSiteRegistry.instance.clear_sites
    end
  elsif TestSiteRegistry.instance.any_sites?
    TestSiteRegistry.instance.clear_sites
  end
  # Clear hash even if directory doesn't exist (prevents stale data)
end

# Cleanup temporary output files from OperationProcessor
# Only removes files older than 1 hour to avoid deleting temp files
# being actively used by other parallel test processes.
def cleanup_temp_output_files
  temp_dir = Dir.tmpdir
  temp_files = Dir.glob(File.join(temp_dir, "imgflow-out-*"))

  return if temp_files.empty?

  cutoff = Time.now - 3600 # 1 hour ago

  temp_files.each do |file|
    next if File.mtime(file) >= cutoff

    FileUtils.rm_f(file)
  rescue StandardError => e
    warn "Failed to remove #{file}: #{e.message}"
  end
end

# Cleanup temporary test directories
def cleanup_temp_test_dirs
  temp_dir = Dir.tmpdir
  patterns = [
    "imgflow-picture-test*",
    "imgflow-enhanced-benchmark*",
    "imgflow-performance-test*",
    "imgflow-out-*", # Temp output files from OperationProcessor
    "d[0-9]*-*-*" # Dir.mktmpdir pattern
  ]

  patterns.each do |pattern|
    Dir.glob(File.join(temp_dir, pattern)).each do |path|
      # Handle both directories and files
      is_directory = File.directory?(path)

      # Only clean up items older than 1 day to avoid interfering with running tests
      next if File.mtime(path) >= Time.now - 86_400

      begin
        if is_directory
          FileUtils.rm_rf(path)

        else
          FileUtils.rm_f(path)

        end
      rescue StandardError => e
        warn "Failed to remove #{path}: #{e.message}"
      end
    end
  end
end

# Comprehensive cleanup - call this at the end of test suite
def cleanup_all_test_artifacts
  # 0. Clean up all temp output files (including old ones)
  cleanup_temp_output_files

  # 1. Stop all Jekyll servers
  cleanup_all_servers

  # 2. Pre-built sites are NOT cleaned - they're reused across test runs
  # To manually clean: CLEAN_PREBUILT=1 bundle exec rspec

  # 3. Clean up old temporary test directories
  cleanup_temp_test_dirs

  # 4. Clean up old TestDirectoryHelper test directories (>1 hour old)
  # This preserves recent test runs for inspection
  TestDirectoryHelper.cleanup_test_directories
end

# Unified Provider Testing Helpers
# Mock site class for testing
MockSite = Struct.new(:config)

module ProviderTestHelpers
  extend self # Make all instance methods available as module methods

  # Pre-build test sites for parallel testing
  def prebuild_test_sites
    base_tmp_dir = File.join(local_tmp_dir, "test_sites")

    # Check if pre-built sites already exist
    if Dir.exist?(base_tmp_dir) && Dir.glob(File.join(base_tmp_dir,
                                                      "site_*")).length == MAX_PARALLEL_PROCESSES

      # Register existing sites
      (0...MAX_PARALLEL_PROCESSES).each do |i|
        site_dir = File.join(base_tmp_dir, "site_#{i}")
        port = PARALLEL_PORT_BASE + i
        TestSiteRegistry.instance.add_site(i, {
                                             site_dir: site_dir,
                                             built_at: File.mtime(site_dir),
                                             port: port
                                           })
      end
      return
    end

    FileUtils.rm_rf(base_tmp_dir)
    FileUtils.mkdir_p(base_tmp_dir)

    (0...MAX_PARALLEL_PROCESSES).each do |i|
      site_dir = File.join(base_tmp_dir, "site_#{i}")
      port = PARALLEL_PORT_BASE + i

      # Create and build the site
      create_test_jekyll_site(site_dir, :imgflow_only)

      # Update the Jekyll config to use the correct port
      config_file = File.join(site_dir, "_config.yml")
      config_content = File.read(config_file)
      config_content.gsub!("url: http://localhost:4000", "url: http://localhost:#{port}")
      File.write(config_file, config_content)

      # Build the Jekyll site (without serving)
      Dir.chdir(site_dir) do
        system("bundle exec jekyll build --trace > /dev/null 2>&1")
      end

      # Store the pre-built site info
      TestSiteRegistry.instance.add_site(i, {
                                           site_dir: site_dir,
                                           built_at: Time.now,
                                           port: port
                                         })
    end
  end

  # Get or create pre-built site for current test process
  def prebuilt_site
    test_env_number = ENV["TEST_ENV_NUMBER"].to_i
    registry = TestSiteRegistry.instance

    raise "Pre-built site #{test_env_number} not found. Run prebuild_test_sites first." unless registry.get_site(test_env_number)

    registry.get_site(test_env_number)
  end

  # Clean up test site modifications to restore pristine state
  def cleanup_test_site_modifications(site_dir)
    return unless site_dir && File.exist?(site_dir)

    # Remove any test images from originals directory
    originals_dir = File.join(site_dir, TEST_CONFIG["imgflow"]["originals"])
    if File.exist?(originals_dir)
      Dir.glob(File.join(originals_dir, "test_image.*")).each do |file|
        FileUtils.rm_f(file)
      end
    end

    # Remove any generated optimized images
    optimized_dir = File.join(site_dir, "_site", TEST_CONFIG["imgflow"]["output"])
    if File.exist?(optimized_dir)
      Dir.glob(File.join(optimized_dir, "test_image*")).each do |file|
        FileUtils.rm_f(file)
      end
    end

    # Rebuild the site to restore clean state
    Dir.chdir(site_dir) do
      system("bundle exec jekyll build --trace > /dev/null 2>&1")
    end
  end

  # Helper to check if Docker container is running
  def docker_container_running?(port)
    require "net/http"
    Net::HTTP.get_response(URI("http://localhost:#{port}/"))
    true
  rescue Errno::ECONNREFUSED, SocketError
    false
  end

  # Helper to check if CLI tool is available
  def cli_tool_available?(command)
    system("which #{command} >/dev/null 2>&1")
  end

  # Get all providers from registry without availability filtering
  def all_providers_from_registry
    site = create_mock_site
    config = JekyllImgFlow::Config.new(site)
    JekyllImgFlow::ProviderRegistry.get_all_providers_with_status(config)
  end

  # Get only available providers (for tests that need running services)
  def available_providers
    site = create_mock_site
    config = JekyllImgFlow::Config.new(site)
    available = JekyllImgFlow::ProviderRegistry.get_available_providers(config)

    available.map do |provider|
      {
        name: provider.class.name.split("::").last,
        class: provider.class,
        instance: provider,
        available: true
      }
    end
  end

  # Generate detailed provider availability report (reused from Rake task)
  def generate_provider_availability_report
    all_providers = all_providers_from_registry

    # HTTP Services

    http_services = all_providers.select do |p|
      HTTP_API_PROVIDERS.include?(p[:name])
    end
    http_services.each do |provider_info|
      provider_info[:available] ? "✅ AVAILABLE" : "❌ NOT AVAILABLE"
    end

    # CLI Tools

    cli_tools = all_providers.reject do |p|
      HTTP_API_PROVIDERS.include?(p[:name])
    end
    cli_tools.each do |provider_info|
      provider_info[:available] ? "✅ AVAILABLE" : "❌ NOT AVAILABLE"
    end

    all_providers.count { |p| p[:available] }
  end

  # ========================================
  # COMPONENT CREATION HELPERS
  # ========================================

  # Create ImgFlow components from a site object
  # Returns a hash with all standard components
  # @param site [Jekyll::Site] Jekyll site object
  # @return [Hash] Hash containing :config, :registry, :provider, :path_resolver, :operation_processor, :batch_manager, :manifest_manager, :manifest (alias)
  def create_imgflow_components(site)
    config = JekyllImgFlow::Config.new(site)
    registry = JekyllImgFlow::ProviderRegistry.new(config)
    provider = registry.current_provider
    path_resolver = JekyllImgFlow::PathResolver.new(config)
    operation_processor = JekyllImgFlow::OperationProcessor.new(provider, path_resolver)
    batch_manager = JekyllImgFlow::BatchManager.new(operation_processor)
    manifest_manager = JekyllImgFlow::ManifestManager.new(site)

    {
      config: config,
      registry: registry,
      provider: provider,
      path_resolver: path_resolver,
      operation_processor: operation_processor,
      batch_manager: batch_manager,
      manifest_manager: manifest_manager,
      manifest: manifest_manager # Alias for backward compatibility
    }
  end

  # Create a standard batch task definition
  # @param original_name [String] Original image filename
  # @param input_path [String] Path to input image
  # @param output_path [String] Path to output image
  # @param options [Hash] Optional parameters
  # @return [Hash] Task definition hash
  def create_batch_task(original_name, input_path, output_path, options = {})
    {
      original_name: original_name,
      operation_type: options[:operation_type] || :resize,
      input_path: input_path,
      output_path: output_path,
      params: options[:params] || { width: 800 },
      version_type: options[:version_type] || :default,
      page_path: options[:page_path],
      skip_if_exists: options.fetch(:skip_if_exists, true)
    }
  end

  # Create a mock Jekyll site for testing (RSpec double)
  # @param options [Hash] Optional site configuration
  # @option options [Hash] :config Site configuration (defaults to TEST_CONFIG)
  # @option options [String] :source Site source directory
  # @option options [String] :dest Site destination directory
  # @return [RSpec::Mocks::Double] Mock site object
  def create_mock_site(options = {})
    config = options[:config] || TEST_CONFIG
    source = options[:source] || "/tmp/test_site"
    dest = options[:dest] || File.join(source, "_site")

    double("site",
           config: config,
           source: source,
           dest: dest)
  end

  # Create a simple MockSite struct for testing (used in site generation)
  # @param config [Hash] Site configuration
  # @return [MockSite] Simple struct with config attribute
  def create_simple_mock_site(config)
    MockSite.new(config)
  end

  # Create a mock Jekyll page for testing
  # @param options [Hash] Optional page configuration
  # @option options [String] :url Page URL (defaults to "/test-page.html")
  # @option options [String] :path Page path (defaults to "/test-page.html")
  # @return [RSpec::Mocks::Double] Mock page object
  def create_mock_page(options = {})
    url = options[:url] || "/test-page.html"
    path = options[:path] || "/test-page.html"

    double("page", url: url, path: path)
  end

  # Create a mock Liquid context for testing
  # @param site [Object] Site object to register
  # @param options [Hash] Optional context configuration
  # @return [RSpec::Mocks::Double] Mock context object
  def create_mock_context(site, options = {})
    registers = { site: site }.merge(options[:registers] || {})
    double("context", registers: registers)
  end

  # Get path to a test fixture image
  # @param filename [String] Image filename (defaults to TestPictures.default)
  # @return [String] Absolute path to fixture image
  def fixture_image_path(filename = nil)
    filename ||= TestPictures.get(:default).first
    File.expand_path("fixtures/originals/#{filename}", __dir__)
  end

  # Get multiple fixture image paths
  # @param set [Symbol] TestPictures set name (defaults to :default_multi)
  # @return [Array<String>] Array of absolute paths to fixture images
  def fixture_image_paths(set = :default_multi)
    TestPictures.get(set).map { |filename| fixture_image_path(filename) }
  end

  # Create a complete tag test setup (site, config, provider, tag)
  # @param tag_class [Class] Tag class to instantiate
  # @param options [Hash] Optional configuration
  # @option options [Hash] :site_config Site configuration (defaults to TEST_CONFIG)
  # @option options [String] :source Site source directory
  # @return [Hash] Hash containing :site, :config, :provider, :tag
  def create_tag_test_setup(tag_class, options = {})
    site = create_mock_site(options)
    components = create_imgflow_components(site)
    tag = tag_class.new(components[:provider])

    {
      site: site,
      config: components[:config],
      provider: components[:provider],
      tag: tag
    }
  end

  # Create a test setup with custom config
  # @param custom_config [Hash] Custom configuration to merge with TEST_CONFIG
  # @param options [Hash] Optional parameters
  # @return [Hash] Hash containing :site, :config, :components
  def create_test_setup_with_config(custom_config, options = {})
    merged_config = TEST_CONFIG.dup.merge(custom_config)
    site = create_mock_site(options.merge(config: merged_config))
    config = JekyllImgFlow::Config.new(site)
    components = create_imgflow_components(site)

    {
      site: site,
      config: config,
      components: components
    }
  end

  # Get build-time processor components (avoid repeated instance_variable_get)
  # @param processor [JekyllImgFlow::BuildTimeProcessor] Processor instance
  # @return [Hash] Hash containing processor components
  def get_processor_components(processor)
    {
      manifest: processor.instance_variable_get(:@manifest),
      site_dest: processor.instance_variable_get(:@site).dest,
      batch_manager: processor.instance_variable_get(:@batch_manager),
      operation_processor: processor.instance_variable_get(:@operation_processor)
    }
  end

  # ========================================
  # TEST SITE HELPERS
  # ========================================

  # Create a test directory using the centralized system
  def create_test_dir(name = nil)
    TestDirectoryHelper.create_test_dir(name)
  end

  # Create a test Jekyll site with specified configuration
  def create_test_jekyll_site(site_dir, config_type = :imgflow_only, options = {})
    # Create a mock site with TEST_CONFIG merged with defaults
    site_config = TEST_CONFIG.dup
    site_config["destination"] = File.join(site_dir, "_site")
    site_config["source"] = site_dir

    # Create Config object to get proper defaults
    mock_site = create_simple_mock_site(site_config)
    config = JekyllImgFlow::Config.new(mock_site)

    # Use paths from Config object (with TEST_CONFIG overrides)
    originals_dir = File.join(site_dir, config.originals)
    optimized_dir = File.join(site_dir, config.output)

    # Create directory structure
    FileUtils.mkdir_p(originals_dir)
    FileUtils.mkdir_p(optimized_dir)
    FileUtils.mkdir_p(File.join(site_dir, "_layouts"))
    FileUtils.mkdir_p(File.join(site_dir, "_data"))

    # Copy test images
    copy_test_images_to_site(originals_dir, options[:test_images] || TestPictures.get(:default))

    # Create config based on type
    config_content = generate_site_config(config_type, options)
    File.write(File.join(site_dir, "_config.yml"), config_content)

    # Create Gemfile so Jekyll loads the plugin
    relative_path = File.expand_path("../..", site_dir)
    gemfile_content = <<~GEMFILE
      source "https://rubygems.org"
      gem "jekyll"
      gem "jekyll-imgflow", path: "#{relative_path}"
    GEMFILE
    File.write(File.join(site_dir, "Gemfile"), gemfile_content)

    # Run bundle install to install dependencies
    Dir.chdir(site_dir) do
      system("bundle install > /dev/null 2>&1")
    end

    # Create default layout
    create_default_layout(site_dir)

    # Create data files based on configuration
    create_data_files(site_dir, config_type, options)

    # Create sample pages
    create_sample_pages(site_dir, config_type, options)

    site_dir
  end

  # Build and optionally serve a Jekyll site with parallel testing support
  def build_jekyll_site(site_dir = nil, serve: false, port: nil, use_prebuilt: true)
    # Use pre-built site if available and requested
    if use_prebuilt && !PREBUILT_SITES.empty?
      prebuilt = prebuilt_site
      site_dir = prebuilt[:site_dir]
      port = prebuilt[:port]
    else
      # Fallback to building on-demand
      # Auto-assign port based on test environment
      port ||= test_port

      Dir.chdir(site_dir) do
        # Build the site
        system("bundle exec jekyll build --trace")
      end
    end

    # Optionally serve the site
    if serve
      # Clean up any existing server on this port
      cleanup_server(port)

      Dir.chdir(site_dir) do
        pid = spawn("bundle exec jekyll serve --port #{port} --detach")
        sleep 2 # Give server time to start

        # Track the server for cleanup
        ACTIVE_SERVERS[port] = {
          pid: pid,
          url: "http://localhost:#{port}",
          site_dir: site_dir
        }
      end

      # Return server info
      ACTIVE_SERVERS[port]
    else
      { site_dir: site_dir, port: port }
    end
  end

  # Clean up a specific server
  def cleanup_server(port)
    # Kill any process using this port (more reliable than PID tracking)
    system("lsof -ti:#{port} | xargs kill -9 2>/dev/null")

    # Also try to kill the tracked PID if we have one
    server_info = ACTIVE_SERVERS[port]
    if server_info && server_info[:pid]
      begin
        Process.kill("TERM", server_info[:pid])
      rescue StandardError
        nil
      end
      begin
        Process.wait(server_info[:pid])
      rescue StandardError
        nil
      end
    end

    ACTIVE_SERVERS.delete(port)

    # Give the port a moment to be released
    sleep 0.5
  end

  private

  # Generate site configuration based on type
  def generate_site_config(config_type, options = {})
    # Start with plugin configurations
    plugin_configs = case config_type
                     when :imgflow_only
                       imgflow_config(options)
                     when :picture_tag_integration, :full_integration
                       imgflow_config(options).merge(picture_tag_config(options))
                     else
                       {}
                     end

    # Base Jekyll config should override plugin configs
    base_config = {
      "title" => options[:title] || "ImgFlow Test Site",
      "url" => options[:url] || TEST_SITE_URL,
      "baseurl" => options[:baseurl] || "",
      "source" => ".",
      "destination" => "_site",
      "plugins" => ["jekyll-imgflow"]
      # NOTE: Do NOT add keep_files: ["assets"] here — it masks the v0.1.6
      # wipe bug by preserving optimized images in _site across builds.
      # Without keep_files, Jekyll cleans _site on each build, which is the
      # correct production behavior we want tests to verify against.
    }

    # Merge plugin configs first, then base config to override
    plugin_configs.merge(base_config).to_yaml
  end

  # ImgFlow configuration - load from real project config
  def imgflow_config(options = {})
    # Start with base config from test_config.rb
    base_config = TEST_CONFIG["imgflow"].dup

    # Override with any provided options
    options.each do |key, value|
      base_config[key.to_s] = value
    end

    { "imgflow" => base_config }
  end

  # Picture Tag configuration - load from real project config
  def picture_tag_config(options = {})
    # Load from _config.yml if available, otherwise use defaults
    config_file = File.join(File.dirname(__dir__), "..", "_config.yml")

    if File.exist?(config_file)
      # Parse the actual config file
      require "yaml"
      project_config = YAML.load_file(config_file)
      picture_config = project_config["picture"] || {}

      # Apply test-specific overrides
      picture_config["disabled"] = options[:picture_tag_disabled] || true
      picture_config["ignore_missing_images"] = true
      picture_config["fast_build"] = true

      picture_config
    else
      # Fallback to test defaults
      {
        "source" => ["assets/images/originals"],
        "output" => "assets/images/optimized",
        "disabled" => options[:picture_tag_disabled] || true,
        "ignore_missing_images" => true,
        "fast_build" => true
      }
    end
  end

  # Copy test images to site
  # @param originals_dir [String] Destination directory for images
  # @param image_set [Symbol, Array] Image set name or array of filenames
  # @param fallback [Symbol] Fallback set if image_set is not found (default: :default_multi)
  def copy_test_images_to_site(originals_dir, image_set = :default_multi, fallback: :default_multi)
    # Get images from TestPictures module
    images = if image_set.is_a?(Array)
               image_set
             else
               TestPictures.get(image_set) || TestPictures.get(fallback)
             end

    copied = 0
    images.each do |image_name|
      src = fixture_image_path(image_name)
      dst = File.join(originals_dir, image_name)

      if File.exist?(src)
        FileUtils.cp(src, dst)
        copied += 1
      end
    end
  end

  # Create default layout
  def create_default_layout(site_dir)
    layout_content = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>{{ site.title }}</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
      </head>
      <body>
        {{ content }}
      </body>
      </html>
    HTML

    File.write(File.join(site_dir, "_layouts", "default.html"), layout_content)
  end

  # Create data files
  def create_data_files(site_dir, config_type, options)
    case config_type
    when :picture_tag_integration, :full_integration
      # Use picture tag configuration from real project config
      picture_tag_config(options)

      # Create picture.yml with real presets from project config if available
      config_file = File.join(File.dirname(__dir__), "..", "_config.yml")

      if File.exist?(config_file)
        require "yaml"
        project_config = YAML.load_file(config_file)
        picture_presets = project_config.dig("picture", "presets") || {
          "default" => {
            "formats" => %w[webp avif original],
            "widths" => [400, 800, 1200],
            "fallback_width" => 800,
            "attributes" => {
              "img" => 'loading="lazy" decoding="async"'
            }
          }
        }
      else
        # Fallback presets
        picture_presets = {
          "default" => {
            "formats" => %w[webp avif original],
            "widths" => [400, 800, 1200],
            "fallback_width" => 800,
            "attributes" => {
              "img" => 'loading="lazy" decoding="async"'
            }
          }
        }
      end

      File.write(File.join(site_dir, "_data", "picture.yml"),
                 { "presets" => picture_presets }.to_yaml)
    end
  end

  # Create sample pages
  def create_sample_pages(site_dir, config_type, options)
    case config_type
    when :imgflow_only
      create_imgflow_test_pages(site_dir, options)
    when :picture_tag_integration
      create_picture_tag_test_pages(site_dir)
    when :full_integration
      create_full_integration_test_pages(site_dir)
    end
  end

  # Create ImgFlow test pages
  def create_imgflow_test_pages(site_dir, options = {})
    # Use test_images from options if provided, otherwise default to TestPictures.default
    test_images = options[:test_images] || TestPictures.get(:default)

    # Generate imgflow tags for each test image
    imgflow_tags = test_images.map do |image|
      "{% imgflow #{image} width:800 height:600 ratio:16:9 %}"
    end.join("\n")

    index_content = <<~MARKDOWN
      ---
      layout: default
      ---

      # ImgFlow Test Site

      ## Test Images

      #{imgflow_tags}
    MARKDOWN

    File.write(File.join(site_dir, "index.md"), index_content)
  end

  # Create Picture Tag test pages
  def create_picture_tag_test_pages(site_dir)
    index_content = <<~MARKDOWN
      ---
      layout: default
      ---

      # Picture Tag Integration Test

      {% picture #{TestPictures.get(:default).first} %}
    MARKDOWN

    File.write(File.join(site_dir, "index.md"), index_content)
  end

  # Create full integration test pages
  def create_full_integration_test_pages(site_dir)
    index_content = <<~MARKDOWN
      ---
      layout: default
      ---

      # Full Integration Test

      ## ImgFlow Tags
      {% imgflow #{TestPictures.get(:default).first} width=800 height=600 %}

      ## Picture Tags
      {% picture #{TestPictures.get(:default).first} %}
    MARKDOWN

    File.write(File.join(site_dir, "index.md"), index_content)
  end

  # Check if file exists and has reasonable size
  def expect_valid_output_file(file_path, min_size = 1000)
    expect(File.exist?(file_path)).to be true
    expect(File.size(file_path)).to be > min_size
  end

  # Check file format using FastImage with fallback for reliability
  def expect_file_signature(file_path, expected_format)
    # Use FastImage to detect the actual image type
    detected_type = FastImage.type(file_path)

    if detected_type
      # FastImage worked - validate the format
      raise "Expected #{expected_format} format, got #{detected_type} for #{file_path}" unless detected_type.to_s.downcase == expected_format.downcase
    else
      # FastImage failed - fall back to basic validation for AVIF and newer formats
      # Check file extension and basic file properties
      actual_extension = File.extname(file_path).downcase.sub(".", "")

      # Handle jpg/jpeg mapping
      normalized_expected = expected_format.downcase
      normalized_actual = actual_extension.downcase

      # jpg and jpeg are equivalent
      if normalized_expected == "jpeg" && normalized_actual == "jpg"
        normalized_actual = "jpeg"
      elsif normalized_actual == "jpeg" && normalized_expected == "jpg"
        normalized_actual = "jpg"
      end

      raise "Expected #{expected_format} format (extension #{actual_extension}) for #{file_path}" unless normalized_actual == normalized_expected

      # For FastImage failures, just check that it's a reasonable file size
      raise "File too small to be valid image: #{file_path}" if File.size(file_path) <= 50
    end
  end
end

# Test Image Helpers
module TestImageHelpers
  def fixtures_dir
    @fixtures_dir ||= File.dirname(fixture_image_path)
  end

  def test_image_path
    @test_image_path ||= fixture_image_path
  end

  def http_test_image
    @http_test_image ||= "https://picsum.photos/1200/800"
  end

  # Validate that an image has the expected dimensions
  # @param image_path [String] Path to the image file
  # @param expected_width [Integer] Expected width
  # @param expected_height [Integer] Expected height
  # @param tolerance [Integer] Allowed tolerance in pixels (default: 2)
  # @return [Boolean] true if dimensions match within tolerance
  def validate_image_dimensions(image_path, expected_width, expected_height, tolerance: 2)
    return false unless File.exist?(image_path)

    begin
      actual_width, actual_height = FastImage.size(image_path)
      return false unless actual_width && actual_height

      width_diff = (actual_width - expected_width).abs
      height_diff = (actual_height - expected_height).abs

      width_diff <= tolerance && height_diff <= tolerance
    rescue FastImage::UnknownImageType, FastImage::ImageFetchError
      false
    end
  end

  # Get actual image dimensions
  # @param image_path [String] Path to the image file
  # @return [Array<Integer, nil>] [width, height] or [nil, nil] if failed
  def get_image_dimensions(image_path)
    return [nil, nil] unless File.exist?(image_path)

    begin
      FastImage.size(image_path)
    rescue FastImage::UnknownImageType, FastImage::ImageFetchError
      [nil, nil]
    end
  end

  # Validate that a resize operation produced correct dimensions
  # @param original_path [String] Path to original image
  # @param resized_path [String] Path to resized image
  # @param target_width [Integer] Target width (or nil for height-only)
  # @param target_height [Integer] Target height (or nil for width-only)
  # @param maintain_aspect [Boolean] Whether aspect ratio should be maintained
  # @return [Boolean] true if resize is correct
  def validate_resize_operation(original_path, resized_path, target_width, target_height,
                                maintain_aspect: true)
    return false unless File.exist?(resized_path)

    # Get original dimensions
    orig_width, orig_height = get_image_dimensions(original_path)
    return false unless orig_width && orig_height

    # Get resized dimensions
    new_width, new_height = get_image_dimensions(resized_path)
    return false unless new_width && new_height

    if maintain_aspect
      # For aspect-ratio maintained resize, calculate expected dimensions
      if target_width && !target_height
        # Width specified, height calculated
        expected_height = (target_width * orig_height.to_f / orig_width).round
        expected_width = target_width
      elsif target_height && !target_width
        # Height specified, width calculated
        expected_width = (target_height * orig_width.to_f / orig_height).round
        expected_height = target_height
      else
        # Both specified (shouldn't happen with maintain_aspect=true)
        expected_width = target_width
        expected_height = target_height
      end
    else
      # For exact resize, use specified dimensions
      expected_width = target_width
      expected_height = target_height
    end

    # Validate with small tolerance for rounding
    validate_image_dimensions(resized_path, expected_width, expected_height, tolerance: 2)
  end

  # Validate that a crop operation produced correct dimensions
  # @param original_path [String] Path to original image
  # @param cropped_path [String] Path to cropped image
  # @param expected_width [Integer] Expected crop width
  # @param expected_height [Integer] Expected crop height
  # @return [Boolean] true if crop is correct
  def validate_crop_operation(_original_path, cropped_path, expected_width, expected_height)
    return false unless File.exist?(cropped_path)

    # Get cropped dimensions
    new_width, new_height = get_image_dimensions(cropped_path)
    return false unless new_width && new_height

    # Crop should produce exact dimensions
    validate_image_dimensions(cropped_path, expected_width, expected_height, tolerance: 1)
  end

  # Print dimension validation result
  # @param image_path [String] Path to the image file
  # @param expected_width [Integer] Expected width
  # @param expected_height [Integer] Expected height
  # @param tolerance [Integer] Allowed tolerance
  # @return [Boolean] true if validation passed
  def dimension_validation?(image_path, expected_width, expected_height, tolerance: 2)
    actual_width, actual_height = get_image_dimensions(image_path)

    if actual_width && actual_height
      width_diff = (actual_width - expected_width).abs
      height_diff = (actual_height - expected_height).abs

      width_diff <= tolerance && height_diff <= tolerance
    else

      false
    end
  end
end

RSpec.configure do |config|
  config.color = true
  config.formatter = :documentation

  # JSON formatter removed - using custom logging instead

  # Profiling is now enabled in .rspec files

  # Capture any errors that occur during setup/teardown
  config.around do |example|
    example.run
  rescue StandardError => e
    # Log the error and re-raise
    error_log = File.join(Dir.pwd, "test_logs", "setup_errors.json")
    error_data = {
      timestamp: Time.now.iso8601,
      example: example.description,
      location: example.location,
      exception: {
        class: e.class.name,
        message: e.message,
        backtrace: e.backtrace&.first(5)
      }
    }

    # Append to error log
    errors = File.exist?(error_log) ? JSON.parse(File.read(error_log)) : []
    errors << error_data
    File.write(error_log, JSON.pretty_generate(errors))

    raise e
  end

  # Add comprehensive failure and error logging for debugging
  config.after(:suite) do
    failure_log = File.join(Dir.pwd, "test_logs", "latest_failures.json")

    # Get test statistics using the RSpec API
    total_examples = RSpec.world.example_count

    # Get failed examples using the reporter
    failed_examples = []

    # Use the reporter to get failed examples
    if config.reporter.respond_to?(:examples)
      config.reporter.examples.each do |example|
        failed_examples << example if example.respond_to?(:execution_result) && example.execution_result.respond_to?(:status) && example.execution_result.status == :failed
      end
    end

    total_failures = failed_examples.count

    if total_failures > 0
      failure_data = {
        timestamp: Time.now.iso8601,
        total_examples: total_examples,
        test_failure_count: total_failures,
        total_failures: total_failures,
        test_failures: failed_examples.map do |example|
          exception_info = if example.respond_to?(:execution_result) && example.execution_result.respond_to?(:exception)
                             example.execution_result.exception
                           else
                             StandardError.new("Unknown error")
                           end

          {
            description: example.description,
            location: example.location,
            exception: {
              class: exception_info.class.name,
              message: exception_info.message,
              backtrace: exception_info.backtrace&.first(5)
            }
          }
        end
      }

      File.write(failure_log, JSON.pretty_generate(failure_data))

    else
      # Create a success log for tracking
      success_log = File.join(Dir.pwd, "test_logs", "latest_success.json")
      success_data = {
        timestamp: Time.now.iso8601,
        total_examples: total_examples,
        status: "all_passed"
      }
      File.write(success_log, JSON.pretty_generate(success_data))

    end
  rescue StandardError => e
    # Log the error but don't let it break the test suite
    error_log = File.join(Dir.pwd, "test_logs", "logging_error.json")
    error_data = {
      timestamp: Time.now.iso8601,
      error: {
        class: e.class.name,
        message: e.message,
        backtrace: e.backtrace&.first(10)
      }
    }
    File.write(error_log, JSON.pretty_generate(error_data))
  end

  # Setup signal handlers and pre-build test sites
  config.before(:suite) do
    setup_signal_handlers

    # Start a file server for HTTP provider tests via Docker
    # Docker containers use host.docker.internal:4000 to fetch source images
    # encode_file_url produces paths relative to site.source, which varies per test.
    # Use a proc handler that searches candidate roots to resolve the file.
    if ENV["IMGFLOW_TEST_PROVIDER"] && HTTP_API_PROVIDERS.include?(ENV["IMGFLOW_TEST_PROVIDER"].capitalize)
      require "webrick"

      project_root = File.expand_path("..", __dir__)

      TestSiteRegistry.instance.test_file_server = WEBrick::HTTPServer.new(
        BindAddress: "0.0.0.0",
        Port: 4000,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )

      # Custom servlet: resolve URL path against candidate document roots
      TestSiteRegistry.instance.test_file_server.mount_proc("/") do |req, res|
        path = req.path_info
        # Candidate roots: project root, filesystem root, /tmp,
        # and all subdirs of tmp/tests (for jekyll_integration_spec test sites)
        candidates = [project_root, "/", "/tmp"]
        tests_dir = File.join(project_root, "tmp", "tests")
        Dir.glob(File.join(tests_dir, "*")).each { |d| candidates << d } if Dir.exist?(tests_dir)
        found = nil
        candidates.each do |root|
          full = File.join(root, path)
          if File.file?(full)
            found = full
            break
          end
        end

        if found
          res.body = File.binread(found)
          res["content-type"] = WEBrick::HTTPUtils.mime_type(found, WEBrick::HTTPUtils::DefaultMimeTypes)
        else
          res.status = 404
          res.body = "Not found: #{path}"
        end
      end

      Thread.new { TestSiteRegistry.instance.test_file_server.start }
      sleep 1
    end

    # Clean up old temp files before starting
    cleanup_temp_output_files if ENV["TEST_ENV_NUMBER"].to_i == 0

    # Pre-build test sites only once (first parallel process does this)
    # Other processes will wait and reuse the pre-built sites
    # Singleton pattern handles frozen hash issues automatically
    base_tmp_dir = File.join(local_tmp_dir, "test_sites")

    if ENV["TEST_ENV_NUMBER"].to_i == 0
      prebuild_test_sites
    else
      # Wait for pre-built sites to be ready
      max_wait = 60 # seconds
      waited = 0

      until File.exist?(base_tmp_dir) &&
            Dir.glob(File.join(base_tmp_dir, "site_*")).length >= MAX_PARALLEL_PROCESSES
        sleep 1
        waited += 1
        break if waited > max_wait
      end
    end

    # Load pre-built site info
    if File.exist?(base_tmp_dir)
      Dir.glob(File.join(base_tmp_dir, "site_*")).each_with_index do |site_dir, i|
        TestSiteRegistry.instance.add_site(i, {
                                             site_dir: site_dir,
                                             built_at: File.mtime(site_dir),
                                             port: PARALLEL_PORT_BASE + i
                                           })
      end
    end
  end

  # Per-test cleanup to ensure clean state
  config.after do |example|
    # Clean up servers after each test that uses them
    cleanup_all_servers if example.metadata[:uses_server] || example.file_path.include?("imgflow_system_spec.rb")
  end

  # Comprehensive cleanup after entire test suite
  config.after(:suite) do
    if TestSiteRegistry.instance.test_file_server
      TestSiteRegistry.instance.test_file_server.shutdown
      TestSiteRegistry.instance.test_file_server = nil
    end
    cleanup_all_test_artifacts
  end

  # Track test files for logging
  config.before do |example|
    TestLogger.track_test_file(example.metadata[:file_path])
  end

  # Check for test images before running tests
  config.before(:suite) do
    fixtures_dir = File.expand_path("fixtures/originals", __dir__)

    # Check if test images have been downloaded
    unless test_images_available?(fixtures_dir)
      Jekyll.logger.info "\n#{'=' * 80}"
      Jekyll.logger.info "❌ ERROR: Test images not found!"
      Jekyll.logger.info "=" * 80
      Jekyll.logger.info ""
      Jekyll.logger.info "Please download test images before running tests:"
      Jekyll.logger.info ""
      Jekyll.logger.info "  ./download-test-images.sh"
      Jekyll.logger.info ""
      Jekyll.logger.info "This will download comprehensive test images in multiple " \
                         "formats and sizes:"
      Jekyll.logger.info "  - NASA Mars imagery (JPEG, large files)"
      Jekyll.logger.info "  - Compression test patterns (JPEG, small/large)"
      Jekyll.logger.info "  - File examples (PNG, WebP, TIFF, SVG in multiple sizes)"
      Jekyll.logger.info ""
      Jekyll.logger.info "Total download size: ~30MB"
      Jekyll.logger.info "Download time: ~1-2 minutes"
      Jekyll.logger.info ""
      Jekyll.logger.info "See README.Development.md for more information."
      Jekyll.logger.info "=" * 80
      Jekyll.logger.info ""

      raise "Test images not available. Run ./download-test-images.sh first."
    end

    FileUtils.mkdir_p(fixtures_dir)
  end

  # Setup common test helpers
  config.include ProviderTestHelpers
  config.include TestImageHelpers
end

def test_images_available?(dir)
  return false unless Dir.exist?(dir)

  # Check for key test images that should exist - use biggest file of each type
  required_images = [
    "mars-crater-large.jpg",      # JPEG (largest JPEG)
    "file_example-large.png",     # PNG (largest PNG)
    "file_example-large.webp",    # WebP (largest overall - 5760x3840)
    "file_example-large.tiff",    # TIFF (largest TIFF - 5760x3840)
    "file_example-medium.svg",    # SVG (vector format)
    "ayousef-espanioly.avif" # AVIF (largest AVIF - 101KB)
  ]

  required_images.all? { |img| File.exist?(File.join(dir, img)) }
end
