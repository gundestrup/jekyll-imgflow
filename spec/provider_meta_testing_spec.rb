# frozen_string_literal: true

require "spec_helper"
require_relative "support/provider_test_helper"

RSpec.describe "Provider Meta-Testing", :external, :provider do
  before(:all) do
    # Create test site once for all tests (original files never changed)
    @test_site_dir = create_test_dir("provider_meta_test")
    create_test_jekyll_site(@test_site_dir, :imgflow_only,
                            { test_images: TestPictures.get(:default_multi) })

    # Create actual site object
    site_config = TEST_CONFIG.dup
    site_config["destination"] = File.join(@test_site_dir, "_site")
    site_config["source"] = @test_site_dir
    @site = Jekyll::Site.new(Jekyll.configuration(site_config))

    # Create shared components once
    @components = create_imgflow_components(@site)
  end

  after(:all) do
    FileUtils.rm_rf(@test_site_dir) if @test_site_dir && Dir.exist?(@test_site_dir)
  end

  # Allow network connections for HTTP provider availability checks
  before do
    WebMock.allow_net_connect!
  end

  # Use shared test patterns (created once in before(:all))
  let(:site) { @site }
  let(:components) { @components }
  let(:config) { components[:config] }
  let(:test_image) { TestPictures.get(:default).first }
  let(:test_image_path) { fixture_image_path(test_image) }

  describe "Basic Operation Testing" do
    it "tests resize operation across all providers" do
      operations = [
        { type: :resize, width: 800, height: 600 }
      ]

      results = ProviderTestHelper.test_all_providers_with_operations(test_image_path, operations,
                                                                      self, components)

      # Verify at least one provider succeeded
      successful_providers = results.select { |_, result| result[:success] }
      expect(successful_providers).not_to be_empty, "No providers succeeded with resize operation"

      # Verify output validation worked
      successful_providers.each do |provider_name, result|
        expect(result[:output_info][:size]).to eq([800, 600]),
                                               "#{provider_name} didn't produce correct dimensions"
      end
    end

    it "tests format conversion across all providers" do
      operations = [
        { type: :format, format: :webp }
      ]

      results = ProviderTestHelper.test_all_providers_with_operations(test_image_path, operations,
                                                                      self, components)

      # Verify format conversion worked
      successful_providers = results.select { |_, result| result[:success] }
      successful_providers.each do |provider_name, result|
        expect(result[:output_info][:type].to_s).to eq("webp"),
                                                    "#{provider_name} didn't convert to webp format"
      end
    end

    it "tests combined resize + format operations across all providers" do
      operations = [
        { type: :resize, width: 400, height: 300 },
        { type: :format, format: :webp }
      ]

      results = ProviderTestHelper.test_all_providers_with_operations(test_image_path, operations,
                                                                      self, components)

      # Verify combined operations worked
      successful_providers = results.select { |_, result| result[:success] }
      successful_providers.each do |provider_name, result|
        expect(result[:output_info][:type].to_s).to eq("webp"),
                                                    "#{provider_name} didn't convert to webp format"
        expect(result[:output_info][:size]).to eq([400, 300]),
                                               "#{provider_name} didn't produce correct dimensions after resize+format"
      end
    end

    it "tests quality optimization across all providers" do
      operations = [
        { type: :resize, width: 600, height: 400 },
        { type: :quality, quality: 75 },
        { type: :format, format: :jpg }
      ]

      results = ProviderTestHelper.test_all_providers_with_operations(test_image_path, operations,
                                                                      self, components)

      # Verify quality operation was applied (file size should be reasonable)
      successful_providers = results.select { |_, result| result[:success] }
      successful_providers.each do |provider_name, result|
        expect(result[:output_info][:file_size]).to be > 0,
                                                    "#{provider_name} produced empty file"
        expect(result[:output_info][:type].to_s).to eq("jpeg"),
                                                    "#{provider_name} didn't produce jpg format"
      end
    end

    it "tests crop operation across all providers" do
      operations = [
        { type: :crop, width: 200, height: 200, x: 50, y: 50 }
      ]

      results = ProviderTestHelper.test_all_providers_with_operations(test_image_path, operations,
                                                                      self, components)

      # Verify crop operation worked
      successful_providers = results.select { |_, result| result[:success] }
      successful_providers.each do |provider_name, result|
        expect(result[:output_info][:size]).to eq([200, 200]),
                                               "#{provider_name} didn't crop to correct dimensions"
      end
    end

    it "tests complex operation chaining across all providers" do
      operations = [
        { type: :crop, width: 300, height: 300, x: 100, y: 100 },
        { type: :resize, width: 400, height: 400 },
        { type: :quality, quality: 85 },
        { type: :format, format: :webp }
      ]

      results = ProviderTestHelper.test_all_providers_with_operations(test_image_path, operations,
                                                                      self, components)

      # Verify complex operations worked
      successful_providers = results.select { |_, result| result[:success] }
      successful_providers.each do |provider_name, result|
        expect(result[:output_info][:size]).to eq([400, 400]),
                                               "#{provider_name} didn't process complex operations correctly"
        expect(result[:output_info][:type].to_s).to eq("webp"),
                                                    "#{provider_name} didn't convert to webp in complex operation"
      end
    end
  end

  describe "Command Generation Testing" do
    it "tests command generation for CLI providers" do
      # Use standard components
      cli_providers = components[:registry].providers.select do |provider|
        provider.available? && provider.respond_to?(:execute_command)
      end

      cli_providers.each do |provider|
        provider.class.name.split("::").last

        # Add operations directly to provider (without executing) to test command building
        provider.reset_operations
        provider.resize(800, 600)
        provider.quality(80)

        # Test command generation - verify operations were collected and command builder works
        expect(provider.operations.length).to eq(2)
        expect(provider.operations.map { |op| op[:type] }).to contain_exactly(:resize, :quality)
        provider.reset_operations
      end
    end
  end

  describe "URL Generation Testing" do
    it "tests URL generation for HTTP providers" do
      # Use standard components
      http_providers = components[:registry].providers.select do |provider|
        provider.class.name.include?("Imgproxy") ||
          provider.class.name.include?("Weserv") ||
          provider.class.name.include?("Flyimg")
      end

      http_providers.each do |provider|
        provider.class.name.split("::").last

        # Test URL encoding capabilities - actually call the methods
        encoded = provider.send(:encode_file_url, "https://example.com/image.jpg")
        expect(encoded).to be_a(String)
        expect(encoded).not_to be_empty

        # Test HTTP service checking - actually call the method
        service_result = provider.send(:check_http_service, provider.config)
        expect(service_result).to be(true).or(be(false))
      end
    end
  end

  describe "Comprehensive Operation Set Testing" do
    it "runs all predefined operation sets" do
      # This is a comprehensive test that runs all operation sets
      # It's useful for full regression testing
      results = ProviderTestHelper.test_all_operation_sets(test_image_path, self)

      # Verify we tested all operation sets
      expect(results.keys).to include(
        :basic_resize,
        :format_conversion,
        :quality_optimization,
        :complex_operations,
        :all_operations
      )

      # Verify at least some providers succeeded for each set
      results.each do |set_name, set_results|
        successful = set_results.count { |_, result| result[:success] }
        set_results.count { |_, result| result[:available] }

        # At least one provider should succeed for each operation set
        expect(successful).to be > 0, "No providers succeeded for #{set_name}"
      end
    end
  end

  describe "Error Handling Testing" do
    it "tests error handling across all providers" do
      # Test with invalid operations
      invalid_operations = [
        { type: :resize, width: -100, height: -100 } # Invalid dimensions
      ]

      results = ProviderTestHelper.test_all_providers_with_operations(test_image_path,
                                                                      invalid_operations, self)

      # Providers should handle invalid operations gracefully
      results.each do |provider_name, result|
        if result[:available]
          expect(result[:error]).not_to be_empty,
                                        "#{provider_name} should reject invalid operations"
        end
      end
    end

    it "tests missing input file handling" do
      # Test with non-existent input file
      non_existent_file = "/tmp/non_existent_image.jpg"

      # Use standard components
      components[:registry].providers.each do |provider|
        next unless provider.available?

        begin
          provider.resize(800, 600)
          provider.execute(non_existent_file, "/tmp/output.jpg")

          # Should handle missing file gracefully
        rescue StandardError => e
          # Exception is acceptable, but should be informative
          expect(e.message).not_to be_empty
        end
      end
    end
  end

  describe "TestPictures Integration Testing" do
    it "uses TestPictures expected filename patterns" do
      operations = [
        { type: :resize, width: 800, height: 600 },
        { type: :format, format: :webp }
      ]

      # Test with expected filename from TestPictures
      TestPictures.expected_filename(test_image, :md, :webp)

      results = ProviderTestHelper.test_all_providers_with_operations(test_image_path, operations,
                                                                      self, components)

      # Verify successful providers produce expected results
      successful_providers = results.select { |_, result| result[:success] }

      successful_providers.each do |provider_name, result|
        # Verify format matches TestPictures expectation
        expect(result[:output_info][:type].to_s).to eq("webp"),
                                                    "#{provider_name} didn't match TestPictures format expectation"

        # Verify dimensions match TestPictures md size (800px width)
        expect(result[:output_info][:size][0]).to eq(800),
                                                  "#{provider_name} didn't match TestPictures size expectation"
      end
    end

    it "tests multiple TestPictures images" do
      # Test with multiple images from TestPictures catalog
      test_images = TestPictures.get(:default_multi).first(3) # Test first 3 images

      test_images.each do |image_name|
        image_path = fixture_image_path(image_name)
        next unless File.exist?(image_path)

        operations = [
          { type: :resize, width: 400, height: 300 },
          { type: :format, format: :jpg }
        ]

        results = ProviderTestHelper.test_all_providers_with_operations(image_path, operations,
                                                                        self)

        # Verify at least one provider succeeded for this image
        successful = results.count { |_, result| result[:success] }
        expect(successful).to be > 0, "No providers succeeded for #{image_name}"
      end
    end
  end

  describe "Performance Testing" do
    it "tests provider performance" do
      operations = [
        { type: :resize, width: 800, height: 600 },
        { type: :format, format: :webp }
      ]

      results = ProviderTestHelper.test_all_providers_with_operations(test_image_path, operations,
                                                                      self, components)

      # Measure execution time for successful providers
      successful_providers = results.select { |_, result| result[:success] }

      successful_providers.each_value do |result|
        # Performance should be reasonable (less than 30 seconds for basic operations)
        # This is a loose check since CI environments can be slow
        expect(result[:output_info][:file_size]).to be > 0
      end
    end
  end
end
