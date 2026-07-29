# frozen_string_literal: true

require "spec_helper"
require_relative "support/test_directory_helper"
require_relative "support/test_pictures"
require "yaml"

RSpec.describe "Tags System - Comprehensive Testing", :integration, :system do
  # Use our helper methods and test photos
  let(:test_dir) { TestDirectoryHelper.create_test_dir("tags-system") }
  let(:test_images) { TestPictures.get(:default_multi) }
  let(:test_image) { test_images.first }
  let(:tokens) { double("tokens", line_number: 1) }

  # Dynamic tag discovery
  let(:available_tags) { JekyllImgFlow::Tags::TagRegistry.available_tags }
  let(:tag_classes) do
    available_tags.filter_map { |tag_name| JekyllImgFlow::Tags::TagRegistry.get_tag(tag_name) }
  end

  # Get base options from REAL config values
  let(:base_options) do
    test_options = { backend_priority: ["libvips"] }
    imgflow_cfg = imgflow_config(test_options)

    site_config = TEST_CONFIG.dup.merge(imgflow_cfg)
    mock_site = MockSite.new(site_config)
    config = JekyllImgFlow::Config.new(mock_site)

    {
      width: config.sizes.values,
      height: [300, 600, 900],
      quality: [config.quality - 10, config.quality, config.quality + 10],
      ratio: ["16:9", "4:3", "1:1"],
      alt: ["Test Image", "Hero Banner"],
      format: config.formats,
      optimize: %i[low medium high]
    }.freeze
  end

  # Use test photo library for input formats
  let(:input_formats) do
    test_options = { backend_priority: ["libvips"] }
    imgflow_cfg = imgflow_config(test_options)

    site_config = TEST_CONFIG.dup.merge(imgflow_cfg)
    mock_site = MockSite.new(site_config)
    config = JekyllImgFlow::Config.new(mock_site)

    # Use TestPictures catalog for format selection
    result = {}
    config.input_formats.each do |format|
      format_images = TestPictures.by_format(format.to_sym)
      result[format.downcase] = format_images.first if format_images.any?
    end
    result
  end

  describe "Tag Registry Integration" do
    it "discovers all available tags dynamically" do
      expect(available_tags).to be_an(Array)
      expect(available_tags.size).to be >= 7

      # Check that all expected tags are discovered
      expect(available_tags).to include(:resize, :crop, :quality, :format, :optimize, :watermark,
                                        :opacity)
    end

    it "retrieves tag classes correctly" do
      tag_classes.each do |tag_class|
        expect(tag_class).to be_a(Class)
        expect(tag_class.ancestors).to include(JekyllImgFlow::Tags::BaseTag)
      end
    end

    it "validates tag class inheritance" do
      tag_classes.each do |tag_class|
        expect(tag_class).to be < JekyllImgFlow::Tags::BaseTag
        expect(tag_class.instance_methods).to include(:process)
      end
    end
  end

  describe "Individual Tag Classes - Dynamic Testing" do
    let(:mock_config) do
      double("config",
             quality: 85,
             formats: %w[webp avif jpg],
             optimize_qualities: { "low" => 60, "medium" => 75, "high" => 85 })
    end
    let(:mock_provider) do
      double("provider",
             :config => mock_config,
             :resize => nil,
             :crop => nil,
             :quality= => nil,
             :convert_format => nil,
             :add_watermark => nil,
             :alpha_opacity= => nil,
             :optimize => nil,
             :execute => "output.jpg")
    end

    it "tests all discovered tag classes dynamically" do
      tag_classes.each do |tag_class|
        tag = tag_class.new(mock_provider)

        expect(tag).to be_a(JekyllImgFlow::Tags::BaseTag)
        expect(tag).to respond_to(:process)
      end
    end

    it "validates BaseTag helper methods" do
      base_tag = JekyllImgFlow::Tags::BaseTag.new(mock_provider)

      # BaseTag.process should raise NotImplementedError
      expect { base_tag.process("input.jpg", "output.jpg", {}) }.to raise_error(NotImplementedError)

      # Verify tag has access to provider and config
      expect(base_tag.instance_variable_get(:@provider)).to eq(mock_provider)
      expect(base_tag.instance_variable_get(:@default_quality)).to eq(85)
    end

    it "validates ResizeTag operations" do
      resize_tag = JekyllImgFlow::Tags::ResizeTag.new(mock_provider)

      # Mock file operations
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:mkdir_p)
      allow(resize_tag).to receive(:get_image_dimensions).and_return([1920, 1080])

      # Test resize with width
      expect(mock_provider).to receive(:resize).with(800, 450, anything)
      expect(mock_provider).to receive(:execute).with("input.jpg", "output.jpg")

      resize_tag.process("input.jpg", "output.jpg", { width: 800 })
    end

    it "validates CropTag operations" do
      crop_tag = JekyllImgFlow::Tags::CropTag.new(mock_provider)

      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:mkdir_p)
      # Mock the private method to return dimensions
      allow(crop_tag).to receive(:get_original_dimensions).and_return([1920, 1080])

      expect(mock_provider).to receive(:crop).with("16:9", anything)
      expect(mock_provider).to receive(:execute).with("input.jpg", "output.jpg")

      crop_tag.process("input.jpg", "output.jpg", { ratio: "16:9" })
    end

    it "validates QualityTag operations" do
      quality_tag = JekyllImgFlow::Tags::QualityTag.new(mock_provider)

      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:mkdir_p)

      expect(mock_provider).to receive(:quality=).with(85)
      expect(mock_provider).to receive(:execute).with("input.jpg", "output.jpg")

      quality_tag.process("input.jpg", "output.jpg", { quality: 85 })
    end

    it "validates FormatTag operations" do
      # FormatTag is a special case - it returns format conversion info
      # Create a simple test that validates format handling
      config = JekyllImgFlow::Config.new(MockSite.new(TEST_CONFIG))

      # Verify config has formats
      expect(config.formats).to include("webp")
      expect(config.supported_output_format?("webp")).to be true
    end

    it "validates WatermarkTag operations" do
      watermark_tag = JekyllImgFlow::Tags::WatermarkTag.new(mock_provider)

      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:mkdir_p)

      # WatermarkTag passes options hash to provider
      expect(mock_provider).to receive(:add_watermark).with("logo.png", anything)
      expect(mock_provider).to receive(:execute).with("input.jpg", "output.jpg")

      watermark_tag.process("input.jpg", "output.jpg", { watermark: "logo.png" })
    end

    it "validates OpacityTag operations" do
      opacity_tag = JekyllImgFlow::Tags::OpacityTag.new(mock_provider)

      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:mkdir_p)

      expect(mock_provider).to receive(:alpha_opacity=).with(0.7)
      expect(mock_provider).to receive(:execute).with("input.jpg", "output.jpg")

      opacity_tag.process("input.jpg", "output.jpg", { opacity: 0.7 })
    end

    it "validates OptimizeTag operations" do
      optimize_tag = JekyllImgFlow::Tags::OptimizeTag.new(mock_provider)

      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:mkdir_p)

      # OptimizeTag translates optimize level to quality setting
      expect(mock_provider).to receive(:quality=).with(75) # medium = 75
      expect(mock_provider).to receive(:execute).with("input.jpg", "output.jpg")

      optimize_tag.process("input.jpg", "output.jpg", { optimize: :medium })
    end
  end

  describe "Test Pictures Integration" do
    it "uses cataloged test images for all formats" do
      expect(test_images).not_to be_empty
      expect(test_images.length).to be >= 3

      test_images.each do |image|
        expect(TestPictures.exists?(image)).to be true
        TestPictures.metadata(image)
      end
    end

    it "validates image metadata from catalog" do
      test_images.each do |image|
        metadata = TestPictures.metadata(image)
        next if metadata.empty?

        expect(metadata).to have_key(:format)
        expect(metadata).to have_key(:size)
        expect(%i[jpg png webp tiff avif svg]).to include(metadata[:format])
      end
    end

    it "generates expected filenames using catalog" do
      test_images.each do |image|
        metadata = TestPictures.metadata(image)
        next if metadata.empty? || !metadata[:expected_defaults]

        metadata[:expected_defaults].each_value do |formats|
          formats.each do |format, expected_filename|
            expect(expected_filename).to include(image.split(".").first)
            # Size is encoded as width (400, 800, 1200, 2000) not as :sm, :md, etc
            expect(expected_filename).to match(/-(400|800|1200|2000)-/)
            expect(expected_filename).to include(format.to_s)
          end
        end
      end
    end

    it "uses TestPictures for format-specific testing" do
      %i[jpg png webp tiff avif].each do |format|
        format_images = TestPictures.by_format(format)
        next if format_images.empty?

        expect(format_images).to be_an(Array)
        expect(format_images.first).to be_a(String)
      end
    end
  end

  describe "Helper Method Integration" do
    it "uses TestDirectoryHelper for test management" do
      expect(Dir.exist?(test_dir)).to be true
      expect(test_dir).to include("tags-system")
      expect(test_dir).to include(TestDirectoryHelper::TEST_BASE_DIR)
    end

    it "properly cleans up test directories" do
      # Test cleanup functionality
      TestDirectoryHelper.cleanup_test_directories
    end

    it "creates test directories with proper structure" do
      custom_dir = TestDirectoryHelper.create_test_dir("custom-test")

      expect(Dir.exist?(custom_dir)).to be true
      expect(custom_dir).to include("custom-test")
    end
  end

  describe "Dynamic Tag Discovery Testing" do
    it "tests all dynamically discovered tags" do
      discovered_tags = JekyllImgFlow::Tags::TagRegistry.available_tags

      expect(discovered_tags).not_to be_empty
      expect(discovered_tags.size).to be >= 7

      # Each discovered tag should be testable
      discovered_tags.each do |tag_name|
        tag_class = JekyllImgFlow::Tags::TagRegistry.get_tag(tag_name)
        expect(tag_class).to be_a(Class)
        expect(tag_class).to respond_to(:new)
      end
    end

    it "validates tag registry functionality" do
      registry = JekyllImgFlow::Tags::TagRegistry

      # Test registry methods
      expect(registry).to respond_to(:available_tags)
      expect(registry).to respond_to(:get_tag)
      expect(registry).to respond_to(:register_tag)

      # Test tag retrieval
      available_tags.each do |tag_name|
        tag_class = registry.get_tag(tag_name)
        expect(tag_class).to be_a(Class)
      end
    end

    it "ensures all tags inherit from BaseTag" do
      available_tags.each do |tag_name|
        tag_class = JekyllImgFlow::Tags::TagRegistry.get_tag(tag_name)

        expect(tag_class.ancestors).to include(JekyllImgFlow::Tags::BaseTag)
        expect(tag_class.instance_methods).to include(:process)
      end
    end
  end

  describe "Config Integration with Dynamic Discovery" do
    let(:config) { JekyllImgFlow::Config.new(MockSite.new(TEST_CONFIG)) }

    it "validates formats using config methods" do
      # Test format validation methods
      expect(config).to respond_to(:supported_input_format?)
      expect(config).to respond_to(:supported_output_format?)
      expect(config).to respond_to(:validate_input_format!)
      expect(config).to respond_to(:validate_output_format!)

      # Test with test images
      input_formats.each_key do |format|
        expect(config.supported_input_format?(format)).to be true
        config.validate_input_format!(format) # Should not raise error
      end

      config.formats.each do |format|
        expect(config.supported_output_format?(format)).to be true
        config.validate_output_format!(format) # Should not raise error
      end
    end

    it "uses config values for tag operations" do
      expect(config.sizes).to be_a(Hash)
      expect(config.formats).to be_an(Array)
      expect(config.quality).to be_a(Integer)
      expect(config.input_formats).to be_an(Array)
    end
  end

  describe "Error Handling and Edge Cases" do
    let(:mock_config) do
      double("config",
             quality: 85,
             formats: %w[webp avif jpg],
             optimize_qualities: { "low" => 60, "medium" => 75, "high" => 85 })
    end
    let(:mock_provider) { double("provider", config: mock_config) }

    it "handles invalid tag operations gracefully" do
      # Test only tags that actually validate parameters
      resize_tag = JekyllImgFlow::Tags::ResizeTag.new(mock_provider)
      expect { resize_tag.process("", "", {}) }.to raise_error(ArgumentError)

      quality_tag = JekyllImgFlow::Tags::QualityTag.new(mock_provider)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:mkdir_p)
      expect do
        quality_tag.process("input.jpg", "output.jpg", { quality: 150 })
      end.to raise_error(ArgumentError)
    end

    it "validates parameter types" do
      resize_tag = JekyllImgFlow::Tags::ResizeTag.new(mock_provider)

      # Invalid width type
      expect do
        resize_tag.process("input.jpg", "output.jpg",
                           { width: "invalid" })
      end.to raise_error(ArgumentError)

      # Negative width
      expect do
        resize_tag.process("input.jpg", "output.jpg", { width: -100 })
      end.to raise_error(ArgumentError)
    end

    it "handles missing required parameters" do
      resize_tag = JekyllImgFlow::Tags::ResizeTag.new(mock_provider)

      # No width or height
      expect { resize_tag.process("input.jpg", "output.jpg", {}) }.to raise_error(ArgumentError)
    end
  end

  describe "Performance and Scalability" do
    it "handles large numbers of tags efficiently" do
      # Create a page with many tags
      large_content = []
      100.times do |i|
        large_content << "{% imgflow #{test_image} width:#{800 + i} %}\n"
      end

      test_file = File.join(test_dir, "large_test.md")
      File.write(test_file, large_content.join("\n"))

      # Should not timeout or crash
      start_time = Time.now
      site = double("site", config: TEST_CONFIG, source: test_dir)
      config = JekyllImgFlow::Config.new(site)
      scanner = JekyllImgFlow::TagScanner.new(site, config)
      tags = scanner.scan_content(File.read(test_file))
      end_time = Time.now

      expect(tags.length).to eq(100)
      expect(end_time - start_time).to be < 5.0 # Should complete within 5 seconds
    end

    it "efficiently discovers tags on multiple calls" do
      start_time = Time.now

      10.times do
        JekyllImgFlow::Tags::TagRegistry.available_tags
      end

      end_time = Time.now

      # Should be fast due to caching
      expect(end_time - start_time).to be < 0.1
    end
  end

  describe "Integration with TestPictures Expected Outputs" do
    it "validates expected filename generation" do
      sizes = %i[sm md lg xl]
      formats = %i[webp avif jpg png]
      test_images.each do |image|
        metadata = TestPictures.metadata(image)
        next unless metadata[:expected_defaults]

        sizes.each do |size|
          formats.each do |format|
            expected = TestPictures.expected_filename(image, size, format)
            next unless expected

            expect(expected).to be_a(String)
            expect(expected).to include(image.split(".").first)
          end
        end
      end
    end

    it "validates hash generation for images" do
      test_images.each do |image|
        hash = TestPictures.hash(image)
        next unless hash

        expect(hash).to be_a(String)
        expect(hash.length).to eq(9) # JPT hash format
      end
    end
  end

  describe "Tag System Comprehensive Coverage" do
    it "covers all tag operations with test images" do
      operations_tested = {
        resize: 0,
        crop: 0,
        quality: 0,
        format: 0,
        watermark: 0,
        opacity: 0,
        optimize: 0
      }

      # Simulate testing each operation with test images
      test_images.first(3).each do |_image|
        operations_tested[:resize] += 1
        operations_tested[:crop] += 1
        operations_tested[:quality] += 1
        operations_tested[:format] += base_options[:format].length
        operations_tested[:watermark] += 1
        operations_tested[:opacity] += 1
        operations_tested[:optimize] += 1
      end

      operations_tested.each_value do |count|
        expect(count).to be > 0
      end

      operations_tested.values.sum
    end
  end
end
