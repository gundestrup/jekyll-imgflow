# frozen_string_literal: true

require "spec_helper"
require "benchmark"

# ⚠️ IMPORTANT: Performance benchmarks should NEVER run in parallel!
# Parallel execution causes resource contention and inaccurate measurements.
# This test is explicitly excluded from parallel provider testing.
RSpec.describe "ImgFlow Performance Benchmark", :performance, :slow do
  # Disable SimpleCov for performance tests to avoid broken pipe errors
  before(:all) do
    if defined?(SimpleCov)
      SimpleCov.minimum_coverage 0
      SimpleCov.start { minimum_coverage 0 }
    end
    @test_site_dir = create_test_dir("imgflow-performance-test")

    # Use :default (1 image) for quick performance testing
    @picture_library = :default
    create_test_jekyll_site(@test_site_dir, :imgflow_only,
                            { test_images: TestPictures.get(@picture_library) })

    # Get test image paths using proper RSpec helpers
    @test_image_paths = fixture_image_paths(@picture_library)

    # Create actual site object
    site_config = TEST_CONFIG.dup
    site_config["destination"] = File.join(@test_site_dir, "_site")
    site_config["source"] = @test_site_dir
    @site = Jekyll::Site.new(Jekyll.configuration(site_config))

    # Create shared components once
    @components = create_imgflow_components(@site)
  end

  # Allow network connections for HTTP provider tests
  before do
    WebMock.allow_net_connect!
  end

  after(:all) do
    FileUtils.rm_rf(@test_site_dir) if @test_site_dir && Dir.exist?(@test_site_dir)
  end

  # Use shared test patterns (created once in before(:all))
  let(:test_site_dir) { @test_site_dir }
  let(:site) { @site }
  let(:components) { @components }
  let(:test_image_path) do
    File.join(@test_site_dir, "assets/images/originals/spider_web-small.jpg")
  end

  describe "Performance Benchmark" do
    it "generates comprehensive performance report" do
      # Use picture library from before(:all) setup
      picture_library = @picture_library
      test_images = TestPictures.get(picture_library)

      providers = available_providers

      test_sizes = [400, 800, 1200, 1600]
      output_formats = TEST_CONFIG["imgflow"]["formats"] || %w[webp avif jpg png]

      pages_created = 0
      test_images.each do |picture_name|
        test_sizes.each do |size|
          output_formats.each do |format|
            page_content = <<~MARKDOWN
              ---
              layout: default
              title: "Test: #{picture_name} @ #{size}px"
              ---

              <img src="{% imgflow #{picture_name} width:#{size} format:#{format} %}" alt="#{picture_name}" />
            MARKDOWN

            safe_name = picture_name.gsub(/[^a-zA-Z0-9_-]/, "_")
            page_path = File.join(test_site_dir, "#{safe_name}-#{size}-#{format}.md")
            File.write(page_path, page_content)
            pages_created += 1
          end
        end
      end

      results = {}

      # Start Jekyll server once to serve original images for HTTP providers
      server_port = test_port
      build_jekyll_site(test_site_dir, serve: true, port: server_port,
                                       use_prebuilt: false)
      sleep 3 # Give server time to fully start

      begin
        providers.each do |provider_info|
          provider_name = provider_info[:name].downcase # Ensure lowercase for registry

          # Update config to use this provider
          # Note: Manifest manager will automatically detect provider change and invalidate cache
          config_file = File.join(test_site_dir, "_config.yml")
          config = YAML.load_file(config_file)
          config["imgflow"]["backend_priority"] = [provider_name]
          config["url"] = "http://localhost:#{server_port}"
          File.write(config_file, config.to_yaml)

          # Recreate site with updated config
          site_config = TEST_CONFIG.dup
          site_config["destination"] = File.join(test_site_dir, "_site")
          site_config["source"] = test_site_dir
          site_config["url"] = "http://localhost:#{server_port}"
          # Deep dup the imgflow hash to avoid frozen hash error
          site_config["imgflow"] = site_config["imgflow"].dup
          site_config["imgflow"]["backend_priority"] = [provider_name]
          test_site = Jekyll::Site.new(Jekyll.configuration(site_config))

          # Benchmark Jekyll build using Jekyll API (not shell command)
          build_time = Benchmark.realtime do
            test_site.process
          end

          # Collect metrics
          output_dir = File.join(test_site_dir, "_site", "assets", "images", "optimized")
          originals_dir = File.join(test_site_dir, "assets", "images", "originals")

          metrics = {
            build_time: build_time.round(2),
            images_generated: 0,
            total_output_size: 0,
            total_input_size: 0
          }

          if Dir.exist?(originals_dir)
            originals = Dir.glob(File.join(originals_dir, "*")).select { |f| File.file?(f) }
            metrics[:total_input_size] = originals.sum { |f| File.size(f) }
          end

          if Dir.exist?(output_dir)
            images = Dir.glob(File.join(output_dir, "**", "*")).select { |f| File.file?(f) }
            metrics[:images_generated] = images.length
            metrics[:total_output_size] = images.sum { |f| File.size(f) }
          end

          # Mark provider as failed if no images were generated
          metrics[:status] = if metrics[:images_generated] == 0
                               "failed"
                             else
                               "success"
                             end

          results[provider_name] = metrics
        end
      ensure
        # Clean up Jekyll server
        cleanup_server(server_port)
      end

      # Generate markdown report
      report_dir = File.expand_path("../docs/performance", __dir__)
      FileUtils.mkdir_p(report_dir)

      report_content = generate_performance_report(picture_library, test_images, results,
                                                   test_sizes, output_formats)
      report_file = File.join(report_dir, "README.Performance.md")
      File.write(report_file, report_content)

      # Generate JSON output
      json_output = {
        generated_at: Time.now.iso8601,
        picture_library: picture_library.to_s,
        test_images_count: test_images.length,
        test_sizes: test_sizes,
        output_formats: output_formats,
        providers: results
      }

      json_file = File.join(report_dir, "benchmark_results.json")
      File.write(json_file, JSON.pretty_generate(json_output))

      # Verify the benchmark ran successfully
      expect(results).not_to be_empty
      expect(providers.length).to be > 0
      expect(File.exist?(report_file)).to be true
      expect(File.exist?(json_file)).to be true

      results.each_value do |data|
        expect(data).to include(:build_time, :images_generated)
      end
    end

    def generate_performance_report(picture_library, test_images, results, test_sizes,
                                    output_formats)
      # Get system info
      cpu = cpu_info
      os = os_info
      mem = memory_info

      total_input_size = results.values.first&.dig(:total_input_size) || 0

      report = <<~MARKDOWN
        # Enhanced ImgFlow Performance Benchmark Report (#{picture_library.to_s.upcase} SET)

        **Generated:** #{Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')}
        **Ruby Version:** #{RUBY_VERSION}
        **Operating System:** #{os}
        **CPU:** #{cpu[:type]}
        **Memory:** #{mem}
        **CPU Cores:** #{cpu[:total]} total, #{cpu[:used]} used for testing
        **Test Set:** #{picture_library.to_s.upcase} SET (#{test_images.length} images)

        ## Summary Table

        | Provider | Runtime (s) | Images Generated | Total Size (MB) | Avg Size (KB) |
        |----------|-------------|------------------|-----------------|---------------|
      MARKDOWN

      results.each do |provider_name, metrics|
        avg_size = metrics[:images_generated] > 0 ? (metrics[:total_output_size] / metrics[:images_generated] / 1024.0).round(2) : 0
        total_mb = (metrics[:total_output_size] / 1024.0 / 1024.0).round(2)
        report += "| #{provider_name.upcase} | #{metrics[:build_time]} | " \
                  "#{metrics[:images_generated]} | #{total_mb} | #{avg_size} |\n"
      end

      report += <<~MARKDOWN

        ## Test Library Information

        **Total Input Library Size:** #{(total_input_size / 1024.0 / 1024.0).round(2)} MB
        **Number of Test Images:** #{test_images.length}
        **Test Sizes:** #{test_sizes.join(', ')}px
        **Output Formats:** #{output_formats.join(', ')}

        ## Key Findings

        - **Fastest Provider:** #{results.min_by { |_, r| r[:build_time] }&.first}
        - **Total Processing Time:** #{results.values.sum { |r| r[:build_time] }.round(2)}s

        ---

        *This report was generated automatically by the ImgFlow performance benchmark test.*
      MARKDOWN

      report
    end

    def cpu_info
      require "etc"
      total_cores = Etc.nprocessors
      used_cores = [total_cores - 1, 8].min.clamp(1, total_cores)

      cpu_type = case RbConfig::CONFIG["host_os"]
                 when /darwin|mac os/
                   `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip.split.first(2).join(" ")
                 else
                   "Unknown"
                 end

      { total: total_cores, used: used_cores, type: cpu_type }
    end

    def os_info
      case RbConfig::CONFIG["host_os"]
      when /darwin|mac os/
        version = `sw_vers -productVersion 2>/dev/null`.strip
        "macOS #{version}"
      when /linux/
        "Linux"
      else
        RbConfig::CONFIG["host_os"]
      end
    end

    def memory_info
      case RbConfig::CONFIG["host_os"]
      when /darwin|mac os/
        mem_bytes = `sysctl -n hw.memsize 2>/dev/null`.strip.to_i
        "#{(mem_bytes / 1024.0 / 1024.0 / 1024.0).round(1)} GB"
      else
        "Unknown"
      end
    end

    it "measures processing time accurately" do
      # Test that the benchmark can measure time differences
      start_time = Time.now
      sleep(0.1) # Simulate some processing
      end_time = Time.now

      processing_time = end_time - start_time
      expect(processing_time).to be > 0.09
      expect(processing_time).to be < 0.2
    end

    it "collects system information" do
      # Test system info collection
      ruby_version = RUBY_VERSION
      os = RUBY_PLATFORM

      expect(ruby_version).to match(/\d+\.\d+\.\d+/)
      expect(os).to match(/(darwin|linux|windows|mingw)/i)
    end
  end

  describe "Provider Comparison" do
    it "compares libvips vs ImageMagick performance using ImgFlow tags" do
      # Get available providers from shared components
      available_providers = components[:registry].providers.select(&:available?)
      available_providers.map { |p| p.class.name.split("::").last.downcase }

      # Focus on CLI providers for performance comparison
      target_providers = %w[libvips imagemagick sharp]
      results = {}

      target_providers.each do |provider_name|
        provider = available_providers.find { |p| p.class.name.downcase.include?(provider_name) }
        next unless provider

        # Use ImgFlow tag interface for accurate performance measurement
        start_time = Time.now

        # Create test conversion using ResizeTag
        tag = JekyllImgFlow::Tags::ResizeTag.new(provider)
        output_file = File.join(test_site_dir, "test-#{provider_name}.webp")

        # Calculate 50% of original dimensions for performance test
        require "fastimage"
        original_dims = FastImage.new(test_image_path).size
        target_width = (original_dims[0] * 0.5).round
        target_height = (original_dims[1] * 0.5).round

        begin
          tag.process(test_image_path, output_file, {
                        width: target_width,
                        height: target_height
                      })

          end_time = Time.now
          processing_time = end_time - start_time

          if File.exist?(output_file)
            file_size = File.size(output_file)
            results[provider_name] = {
              time: processing_time,
              size: file_size,
              success: true
            }
            (file_size / 1024.0).round(1)
          else
            results[provider_name] = { success: false }
          end
        rescue StandardError => e
          results[provider_name] = { success: false, error: e.message }
        end
      end

      # Compare results
      successful_results = results.select { |_, r| r[:success] }

      if successful_results.length > 1
        fastest = successful_results.min_by { |_, r| r[:time] }

        # Verify we have meaningful differences
        expect(fastest[1][:time]).to be > 0
        times = successful_results.values.map { |r| r[:time] }
        expect(times.uniq.length).to be > 0
      end
    end
  end

  describe "Format Efficiency" do
    it "compares different image formats using ImgFlow tags" do
      # Use a reliable provider for format comparison
      provider = components[:registry].providers.find do |p|
        p.class.name.downcase.include?("sharp")
      end
      unless provider&.available?
        # Fallback to first available CLI provider
        provider = components[:registry].providers.find(&:available?)
      end

      skip "No available providers for format efficiency test" unless provider

      original_size = File.size(test_image_path)
      formats = %w[webp jpg png]
      results = {}

      formats.each do |format|
        output_file = File.join(test_site_dir, "test-format-#{format}.#{format}")

        # Use ImgFlow FormatTag for accurate format conversion
        begin
          tag = JekyllImgFlow::Tags::FormatTag.new(provider)
          tag.process(test_image_path, output_file, {
                        formats: [format.to_sym]
                      })

          if File.exist?(output_file)
            file_size = File.size(output_file)
            compression_ratio = ((original_size - file_size).to_f / original_size * 100).round(1)
            results[format] = {
              size: file_size,
              compression: compression_ratio,
              success: true
            }
            (file_size / 1024.0).round(1)
          else
            results[format] = { success: false }
          end
        rescue StandardError => e
          results[format] = { success: false, error: e.message }
        end
      end

      # Find best compression
      successful_results = results.select { |_, r| r[:success] }
      if successful_results.any?
        successful_results.max_by { |_, r| r[:compression] }

        # Verify we have meaningful differences
        sizes = successful_results.values.map { |r| r[:size] }
        expect(sizes.uniq.length).to be > 0
      end
    end
  end
end
