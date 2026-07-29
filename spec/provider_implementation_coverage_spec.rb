# frozen_string_literal: true

require "spec_helper"
require_relative "support/parallel_provider_test_helper"

RSpec.describe "Provider Implementation Coverage", :external, :provider do
  # Allow network connections for HTTP provider availability checks
  before do
    WebMock.allow_net_connect!
  end

  let(:site) { double("site", config: TEST_CONFIG, source: "/tmp/test_site") }
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:registry) { JekyllImgFlow::ProviderRegistry.new(config) }

  # Get all providers (including unavailable ones for testing)
  let(:all_providers) do
    JekyllImgFlow::ProviderRegistry.provider_registry.values.map { |klass| klass.new(config) }
  end

  # Get only available providers
  let(:available_providers) do
    all_providers.select(&:available?)
  end

  describe "Sharp Provider Implementation" do
    let(:sharp) { all_providers.find { |p| p.class.name.include?("Sharp") } }

    it "tests Sharp-specific CLI operations" do
      skip "Sharp not available" unless sharp&.available?

      # Test Sharp CLI command building
      sharp.resize(800, 600)
      expect(sharp.operations.last[:type]).to eq(:resize)
      expect(sharp.operations.last[:width]).to eq(800)
      expect(sharp.operations.last[:height]).to eq(600)

      # Test Sharp quality operation
      sharp.quality(85)
      expect(sharp.operations.last[:type]).to eq(:quality)
      expect(sharp.operations.last[:quality]).to eq(85)

      # Test Sharp format operation
      sharp.format(:webp)
      expect(sharp.operations.last[:type]).to eq(:format)
      expect(sharp.operations.last[:format]).to eq(:webp)

      # Test Sharp crop operation
      sharp.crop(100, 100, 10, 10)
      expect(sharp.operations.last[:type]).to eq(:crop)
      expect(sharp.operations.last[:width]).to eq(100)
      expect(sharp.operations.last[:height]).to eq(100)
      expect(sharp.operations.last[:x]).to eq(10)
      expect(sharp.operations.last[:y]).to eq(10)

      # Test Sharp command generation (without executing)
      sharp.reset_operations
      sharp.resize(800, 600)
      sharp.quality(80)

      # Verify Sharp can generate commands - actually call the builder
      cmd = sharp.send(:build_sharp_command, "/tmp/input.jpg", "/tmp/output.webp")
      expect(cmd).to be_a(String)
      expect(cmd).to include("sharp")
      sharp.reset_operations
    end
  end

  describe "ImageMagick Provider Implementation" do
    let(:imagemagick) { all_providers.find { |p| p.class.name.include?("Imagemagick") } }

    it "tests ImageMagick-specific CLI operations" do
      skip "ImageMagick not available" unless imagemagick&.available?

      # Test ImageMagick CLI command building
      imagemagick.resize(800, 600)
      expect(imagemagick.operations.last[:type]).to eq(:resize)
      expect(imagemagick.operations.last[:width]).to eq(800)
      expect(imagemagick.operations.last[:height]).to eq(600)

      # Test ImageMagick quality operation
      imagemagick.quality(85)
      expect(imagemagick.operations.last[:type]).to eq(:quality)
      expect(imagemagick.operations.last[:quality]).to eq(85)

      # Test ImageMagick format operation
      imagemagick.format(:webp)
      expect(imagemagick.operations.last[:type]).to eq(:format)
      expect(imagemagick.operations.last[:format]).to eq(:webp)

      # Test ImageMagick crop operation
      imagemagick.crop(100, 100, 10, 10)
      expect(imagemagick.operations.last[:type]).to eq(:crop)
      expect(imagemagick.operations.last[:width]).to eq(100)
      expect(imagemagick.operations.last[:height]).to eq(100)
      expect(imagemagick.operations.last[:x]).to eq(10)
      expect(imagemagick.operations.last[:y]).to eq(10)

      # Test ImageMagick command generation
      imagemagick.reset_operations
      imagemagick.resize(800, 600)
      imagemagick.quality(80)

      expect(imagemagick).to respond_to(:build_combined_imagemagick_command)
      cmd = imagemagick.send(:build_combined_imagemagick_command, "/tmp/input.jpg",
                             "/tmp/output.webp")
      expect(cmd).to be_a(String)
      expect(cmd).to include("magick")
      imagemagick.reset_operations
    end
  end

  describe "Libvips Provider Implementation" do
    let(:libvips) { all_providers.find { |p| p.class.name.include?("Libvips") } }

    it "tests Libvips-specific operations" do
      skip "Libvips not available" unless libvips&.available?

      # Test Libvips operations
      libvips.resize(800, 600)
      expect(libvips.operations.last[:type]).to eq(:resize)
      expect(libvips.operations.last[:width]).to eq(800)
      expect(libvips.operations.last[:height]).to eq(600)

      # Test Libvips quality operation
      libvips.quality(85)
      expect(libvips.operations.last[:type]).to eq(:quality)
      expect(libvips.operations.last[:quality]).to eq(85)

      # Test Libvips format operation
      libvips.format(:webp)
      expect(libvips.operations.last[:type]).to eq(:format)
      expect(libvips.operations.last[:format]).to eq(:webp)

      # Test Libvips crop operation
      libvips.crop(100, 100, 10, 10)
      expect(libvips.operations.last[:type]).to eq(:crop)
      expect(libvips.operations.last[:width]).to eq(100)
      expect(libvips.operations.last[:height]).to eq(100)
      expect(libvips.operations.last[:x]).to eq(10)
      expect(libvips.operations.last[:y]).to eq(10)

      # Test Libvips command generation
      libvips.reset_operations
      libvips.resize(800, 600)
      libvips.quality(80)

      expect(libvips).to respond_to(:build_vips_command)
      cmd = libvips.send(:build_vips_command, "/tmp/input.jpg", "/tmp/output.webp")
      expect(cmd).to be_a(String)
      expect(cmd).to include("vips")
      libvips.reset_operations
    end
  end

  describe "HTTP Provider Implementations" do
    let(:http_providers) do
      all_providers.select do |p|
        p.class.name.include?("Imgproxy") ||
          p.class.name.include?("Weserv") ||
          p.class.name.include?("Flyimg")
      end
    end

    it "tests HTTP provider URL building" do
      http_providers.each do |provider|
        provider.class.name.split("::").last

        # Test URL building operations
        provider.resize(800, 600)
        expect(provider.operations.last[:type]).to eq(:resize)
        expect(provider.operations.last[:width]).to eq(800)
        expect(provider.operations.last[:height]).to eq(600)

        # Test quality operation
        provider.quality(85)
        expect(provider.operations.last[:type]).to eq(:quality)
        expect(provider.operations.last[:quality]).to eq(85)

        # Test format operation
        provider.format(:webp)
        expect(provider.operations.last[:type]).to eq(:format)
        expect(provider.operations.last[:format]).to eq(:webp)

        # Test URL encoding/decoding capabilities - actually call the method
        encoded = provider.send(:encode_file_url, "https://example.com/image.jpg")
        expect(encoded).to be_a(String)
        expect(encoded).not_to be_empty

        # Test HTTP service checking - actually call the method
        service_result = provider.send(:check_http_service, provider.config)
        expect(service_result).to be(true).or(be(false))
      end
    end
  end

  describe "Provider Method Implementation Coverage" do
    it "ensures all providers implement required BaseProvider methods" do
      required_methods = %i[
        resize quality format crop optimize opacity watermark execute available? config operations reset_operations supports_operation?
      ]

      all_providers.each do |provider|
        provider_name = provider.class.name.split("::").last

        required_methods.each do |method|
          expect(provider).to respond_to(method),
                              "#{provider_name} does not implement #{method}"
        end
      end
    end
  end

  describe "Provider Operation Parameter Validation" do
    it "tests parameter validation for each provider" do
      available_providers.each do |provider|
        provider.class.name.split("::").last

        # Test resize parameter validation
        provider.reset_operations
        provider.resize(800, 600)
        expect(provider.operations.last[:type]).to eq(:resize)
        expect(provider.operations.last[:width]).to eq(800)
        expect(provider.operations.last[:height]).to eq(600)

        # Test invalid resize parameters (should not crash, just collect)
        provider.reset_operations
        provider.resize(-1, -1)
        expect(provider.operations.last[:width]).to eq(-1)

        # Test quality parameter validation
        provider.reset_operations
        provider.quality(85)
        expect(provider.operations.last[:type]).to eq(:quality)
        expect(provider.operations.last[:quality]).to eq(85)

        # Test invalid quality parameters
        provider.reset_operations
        provider.quality(150)
        expect(provider.operations.last[:quality]).to eq(150)

        # Test format parameter validation
        provider.reset_operations
        provider.format(:webp)
        expect(provider.operations.last[:type]).to eq(:format)
        expect(provider.operations.last[:format]).to eq(:webp)

        # Test invalid format parameters
        provider.reset_operations
        provider.format(:invalid_format)
        expect(provider.operations.last[:type]).to eq(:format)
      end
    end
  end

  describe "Provider Operation Chaining" do
    it "tests operation chaining for each provider" do
      available_providers.each do |provider|
        provider.class.name.split("::").last

        # Test multiple operations
        provider.reset_operations
        provider.resize(800, 600)
        provider.quality(80)
        provider.format(:webp)
        provider.crop(100, 100, 10, 10)

        expect(provider.operations.length).to eq(4)
        expect(provider.operations.map do |op|
                 op[:type]
               end).to contain_exactly(:resize, :quality, :format, :crop)

        # Test operation reset
        provider.reset_operations
        expect(provider.operations).to be_empty
      end
    end
  end

  describe "Provider Error Handling" do
    it "tests error handling for each provider" do
      all_providers.each do |provider|
        provider.class.name.split("::").last

        # Test nil parameters - provider collects them without validation (validation is in tags)
        provider.reset_operations
        provider.resize(nil, nil)
        expect(provider.operations.last[:type]).to eq(:resize)

        # Test string parameters (should be collected as provided)
        provider.reset_operations
        provider.resize("800", "600")
        expect(provider.operations.last[:width]).to eq("800")

        # Test zero parameters
        provider.reset_operations
        provider.resize(0, 0)
        expect(provider.operations.last[:width]).to eq(0)
      end
    end
  end

  describe "Provider Configuration Integration" do
    it "tests provider configuration handling" do
      all_providers.each do |provider|
        provider.class.name.split("::").last

        # Test config access
        expect(provider.config).to be_a(JekyllImgFlow::Config)

        # Test config values integration
        expect(provider.config.quality).to be_a(Integer)
        expect(provider.config.formats).to include("webp")
        expect(provider.config.sizes).to have_key("lg")
      end
    end
  end

  describe "Provider Coverage Summary" do
    it "generates comprehensive provider coverage report" do
      skip "Single provider mode" if ENV["IMGFLOW_TEST_PROVIDER"]
      total_providers = all_providers.length
      available_count = available_providers.length
      coverage_percentage = (available_count.to_f / total_providers * 100).round(1)

      all_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.available?
        provider_name.match?(/(Imgproxy|Weserv|Flyimg)/) ? "HTTP" : "CLI"
      end

      # Ensure we have reasonable coverage
      expect(coverage_percentage).to be >= 30, "Provider availability coverage too low"
      expect(total_providers).to be >= 5, "Should test at least 5 providers"
    end
  end
end
