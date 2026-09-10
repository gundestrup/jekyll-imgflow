# frozen_string_literal: true

require "simplecov"
require "ostruct"
require "fastimage"
require "open3"
require_relative "../scripts/test_logger"
require_relative "support/test_directory_helper"
require_relative "support/test_pictures"
require_relative "support/test_environment"

# Auto-start test logging for all test runs
TestLogger.auto_start

SimpleCov.start do
  skip "/spec/"
end

# Constants for performance optimization
HTTP_API_PROVIDERS = TestEnvironment::HTTP_PROVIDERS.map(&:capitalize).freeze
CLI_TOOLS = TestEnvironment::CLI_PROVIDERS.map(&:capitalize).freeze

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
require_relative "support/provider_integration_helper"
require "webmock/rspec"
require "jekyll"

WebMock.disable_net_connect!(allow_localhost: true)

# Parallel testing configuration is centralized in TestEnvironment.

def active_servers
  @active_servers ||= {}
end

# Get the source/server port assigned to the current test process.
def test_port
  TestEnvironment.current_source_port
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
  return if active_servers.empty?

  active_servers.each_key { |port| cleanup_server(port) }
  active_servers.clear
end

# Manual cleanup for orphaned servers (can be called from command line)
def cleanup_orphaned_servers
  # Kill any remaining servers on test ports.
  ports_to_check = TestEnvironment.all_test_ports

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

  # 2. Clean up old temporary test directories
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
    # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec -- system receives separate arguments; no shell interpolation.
    system("which", command, out: File::NULL, err: File::NULL)
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
    filename_generator = JekyllImgFlow::FilenameGenerator.new
    manifest_manager = JekyllImgFlow::ManifestManager.new(site)
    operation_processor = JekyllImgFlow::OperationProcessor.new(
      provider, path_resolver, manifest_manager, config
    )
    batch_manager = JekyllImgFlow::BatchManager.new(operation_processor)

    {
      config: config,
      registry: registry,
      provider: provider,
      path_resolver: path_resolver,
      filename_generator: filename_generator,
      operation_processor: operation_processor,
      stats: operation_processor.stats,
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

  # Build and optionally serve a Jekyll site
  def build_jekyll_site(site_dir, serve: false, port: nil)
    port ||= test_port

    Dir.chdir(site_dir) do
      system("bundle exec jekyll build --trace")
    end

    if serve
      # Clean up any existing server on this port
      cleanup_server(port)

      Dir.chdir(site_dir) do
        pid = spawn("bundle", "exec", "jekyll", "serve", "--host", "0.0.0.0",
                    "--port", port.to_s, "--detach")
        sleep 2 # Give server time to start

        # Track the server for cleanup
        active_servers[port] = {
          pid: pid,
          url: "http://localhost:#{port}",
          site_dir: site_dir
        }
      end

      # Return server info
      active_servers[port]
    else
      { site_dir: site_dir, port: port }
    end
  end

  # Clean up a specific server
  def cleanup_server(port)
    # Kill any process using this port (more reliable than PID tracking)
    # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec -- Open3 receives an argument array; no shell is invoked.
    output, = Open3.capture3("lsof", "-ti:#{Integer(port)}")
    output.split
          .filter_map { |pid| Integer(pid, exception: false) }
          .each { |pid| Process.kill("KILL", pid) }

    # Also try to kill the tracked PID if we have one
    server_info = active_servers[port]
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

    active_servers.delete(port)

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
    format = options[:test_output_format]
    format_option = format ? " format:#{format}" : ""
    imgflow_tags = test_images.map do |image|
      "{% imgflow #{image} width:800#{format_option} %}"
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
    detected_type = FastImage.type(file_path)
    return validate_detected_type(file_path, expected_format, detected_type) if detected_type

    validate_file_fallback(file_path, expected_format)
  end

  def validate_detected_type(file_path, expected_format, detected_type)
    return if detected_type.to_s.casecmp?(expected_format.to_s)

    raise "Expected #{expected_format} format, got #{detected_type} for #{file_path}"
  end

  def validate_file_fallback(file_path, expected_format)
    actual_extension = File.extname(file_path).delete_prefix(".")
    expected = normalize_image_format(expected_format)
    actual = normalize_image_format(actual_extension)
    return if actual == expected && File.size(file_path) > 50

    raise "Expected #{expected_format} format (extension #{actual_extension}) for #{file_path}" unless actual == expected

    raise "File too small to be valid image: #{file_path}"
  end

  def normalize_image_format(format)
    format.to_s.downcase.sub("jpeg", "jpg")
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

    original_dimensions = get_image_dimensions(original_path)
    resized_dimensions = get_image_dimensions(resized_path)
    return false unless original_dimensions.all? && resized_dimensions.all?

    expected_dimensions = expected_resize_dimensions(
      original_dimensions, target_width, target_height, maintain_aspect
    )
    validate_image_dimensions(resized_path, *expected_dimensions, tolerance: 2)
  end

  def expected_resize_dimensions(original_dimensions, target_width, target_height, maintain_aspect)
    return [target_width, target_height] unless maintain_aspect

    original_width, original_height = original_dimensions
    if target_width && !target_height
      [target_width, (target_width * original_height.to_f / original_width).round]
    elsif target_height && !target_width
      [(target_height * original_width.to_f / original_height).round, target_height]
    else
      [target_width, target_height]
    end
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
    session_failure_log = TestLogger.rspec_result_path(:failure)

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
    pending_count = if config.reporter.respond_to?(:examples)
                      config.reporter.examples.count do |example|
                        example.respond_to?(:execution_result) &&
                          example.execution_result.respond_to?(:status) &&
                          example.execution_result.status == :pending
                      end
                    else
                      0
                    end

    if total_failures > 0
      failure_data = {
        timestamp: Time.now.iso8601,
        total_examples: total_examples,
        test_failure_count: total_failures,
        total_failures: total_failures,
        pending_count: pending_count,
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

      content = JSON.pretty_generate(failure_data)
      FileUtils.rm_f(File.join(Dir.pwd, "test_logs", "latest_success.json"))
      File.write(failure_log, content)
      File.write(session_failure_log, content)

    else
      # Create a success log for tracking
      success_log = File.join(Dir.pwd, "test_logs", "latest_success.json")
      session_success_log = TestLogger.rspec_result_path(:success)
      success_data = {
        timestamp: Time.now.iso8601,
        total_examples: total_examples,
        pending_count: pending_count,
        status: "all_passed"
      }
      content = JSON.pretty_generate(success_data)
      FileUtils.rm_f(failure_log)
      File.write(success_log, content)
      File.write(session_success_log, content)

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

  # Setup signal handlers and shared test lifecycle
  config.before(:suite) do
    setup_signal_handlers
    TestEnvironment.start_source_server
    cleanup_temp_output_files if ENV["TEST_ENV_NUMBER"].to_i == 0
  end

  # Per-test cleanup to ensure clean state
  config.after do |example|
    # Clean up servers after each test that uses them
    cleanup_all_servers if example.metadata[:uses_server] || example.file_path.include?("imgflow_system_spec.rb")
  end

  # Comprehensive cleanup after entire test suite
  config.after(:suite) do
    TestEnvironment.stop_source_server
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
  config.include ProviderIntegrationHelper
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
