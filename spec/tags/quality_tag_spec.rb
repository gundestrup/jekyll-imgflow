# frozen_string_literal: true

require "spec_helper"
require "vips"

RSpec.describe JekyllImgFlow::Tags::QualityTag, :unit do
  let(:site) do
    double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                   dest: "/tmp/test_site/_site")
  end
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:provider) { JekyllImgFlow::ProviderRegistry.new(config).current_provider }
  let(:tag) { described_class.new(provider) }

  # Helper method to get compression information using ruby-vips
  def get_compression_info(image_path)
    image = Vips::Image.new_from_file(image_path)

    # Get basic image info
    width = image.width
    height = image.height
    bands = image.bands
    format = image.interpretation

    # Calculate file size
    file_size = File.size(image_path)

    # Estimate original uncompressed size (rough calculation)
    # For JPEG: width * height * 3 bytes (RGB)
    uncompressed_size = width * height * bands

    # Calculate compression ratio
    compression_ratio = uncompressed_size.to_f / file_size

    {
      width: width,
      height: height,
      bands: bands,
      format: format,
      file_size: file_size,
      uncompressed_size: uncompressed_size,
      compression_ratio: compression_ratio,
      quality_estimate: estimate_quality_from_compression(compression_ratio)
    }
  rescue StandardError => e
    # Fallback if ruby-vips fails
    {
      error: e.message,
      file_size: File.size(image_path)
    }
  end

  # Estimate quality from compression ratio (rough approximation)
  def estimate_quality_from_compression(compression_ratio)
    case compression_ratio
    when 0..5 then 95   # Very low compression = high quality
    when 5..10 then 85  # Low compression = high quality
    when 10..20 then 75 # Medium compression = medium quality
    when 20..30 then 65 # High compression = medium quality
    when 30..50 then 50 # Very high compression = low quality
    else 40 # Extreme compression = low quality
    end
  end

  describe "#process" do
    let(:test_image_dir) { create_test_dir("quality-tag-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.jpg") }
    let(:output_path) { File.join(test_image_dir, config.output, "test-q85-a1b2c3d4e.jpg") }
    let(:original_image) do
      File.expand_path("../fixtures/originals/mars-crater-large.jpg", __dir__)
    end

    before do
      # Create test directories and copy test image
      FileUtils.mkdir_p(File.dirname(input_path))
      FileUtils.cp(original_image, input_path)
      FileUtils.mkdir_p(File.dirname(output_path))
    end

    after do
      FileUtils.rm_rf(test_image_dir)
    end

    context "with valid quality" do
      let(:options) { { quality: 85 } }

      it "changes quality and verifies through compression analysis" do
        # Get original compression info using ruby-vips
        original_info = get_compression_info(original_image)

        # Process the quality change
        result = tag.process(input_path, output_path, options)

        # Verify output file exists
        expect(File.exist?(output_path)).to be true
        expect(File.size(output_path)).to be > 1000

        # Verify format is still JPEG
        expect_file_signature(output_path, "jpeg")

        # Get compressed image info using ruby-vips
        compressed_info = get_compression_info(output_path)

        # Quality change verification: compression should be different
        expect(compressed_info[:compression_ratio]).not_to eq(original_info[:compression_ratio])

        # For quality 85, compression ratio should indicate medium-high quality
        expect(compressed_info[:quality_estimate]).to be_between(75, 95)

        # Verify dimensions are preserved
        expect(compressed_info[:width]).to eq(original_info[:width])
        expect(compressed_info[:height]).to eq(original_info[:height])

        # Verify return value
        expect(result).to eq(output_path)
      end
    end

    context "with different quality levels" do
      let(:high_quality_path) { File.join(test_image_dir, config.output, "test-q95-a1b2c3d4e.jpg") }
      let(:low_quality_path) { File.join(test_image_dir, config.output, "test-q30-a1b2c3d4e.jpg") }

      it "creates different compression ratios for different quality levels" do
        # Process high quality
        tag.process(input_path, high_quality_path, { quality: 95 })

        # Process low quality
        tag.process(input_path, low_quality_path, { quality: 30 })

        # Both files should exist
        expect(File.exist?(high_quality_path)).to be true
        expect(File.exist?(low_quality_path)).to be true

        # Get compression info using ruby-vips
        high_info = get_compression_info(high_quality_path)
        low_info = get_compression_info(low_quality_path)

        # High quality should have lower compression ratio (less compressed)
        # Low quality should have higher compression ratio (more compressed)
        expect(high_info[:compression_ratio]).to be < low_info[:compression_ratio]

        # Verify estimated quality ranges
        expect(high_info[:quality_estimate]).to be >= 85
        expect(low_info[:quality_estimate]).to be <= 65

        # Both should be valid JPEG files with same dimensions
        expect_file_signature(high_quality_path, "jpeg")
        expect_file_signature(low_quality_path, "jpeg")
        expect(high_info[:width]).to eq(low_info[:width])
        expect(high_info[:height]).to eq(low_info[:height])
      end
    end

    context "with string quality" do
      let(:options) { { quality: "90" } }

      it "converts string to integer and processes" do
        result = tag.process(input_path, output_path, options)

        # Verify output exists and is valid
        expect(File.exist?(output_path)).to be true
        expect(File.size(output_path)).to be > 1000
        expect_file_signature(output_path, "jpeg")

        expect(result).to eq(output_path)
      end
    end

    context "with no quality specified" do
      let(:options) { {} }

      it "uses default quality (85) from config" do
        result = tag.process(input_path, output_path, options)

        # Verify output exists and is valid
        expect(File.exist?(output_path)).to be true
        expect(File.size(output_path)).to be > 1000
        expect_file_signature(output_path, "jpeg")

        # Verify default quality (85) was applied by comparing with explicit quality
        explicit_output = File.join(test_image_dir, config.output,
                                    "test-explicit-q85-a1b2c3d4e.jpg")
        tag.process(input_path, explicit_output, { quality: 85 })

        # Files should be similar size (same quality applied)
        default_size = File.size(output_path)
        explicit_size = File.size(explicit_output)

        # Allow small variance for processing differences
        expect(default_size).to be_within(explicit_size * 0.05).of(explicit_size)

        expect(result).to eq(output_path)
      end
    end

    context "with invalid quality" do
      let(:options) { { quality: 150 } }

      it "raises validation error" do
        expect do
          tag.process(input_path, output_path, options)
        end.to raise_error(ArgumentError, /Invalid quality/)
      end
    end

    context "with quality too low" do
      let(:options) { { quality: 0 } }

      it "raises validation error" do
        expect do
          tag.process(input_path, output_path, options)
        end.to raise_error(ArgumentError, /Invalid quality/)
      end
    end

    context "with negative quality" do
      let(:options) { { quality: -10 } }

      it "raises validation error" do
        expect do
          tag.process(input_path, output_path, options)
        end.to raise_error(ArgumentError, /Invalid quality/)
      end
    end
  end

  describe "#validate_quality" do
    it "accepts valid quality range" do
      result = tag.send(:validate_quality, 75)
      expect(result).to eq(75)
    end

    it "accepts string quality" do
      result = tag.send(:validate_quality, "80")
      expect(result).to eq(80)
    end

    it "returns default quality for nil" do
      result = tag.send(:validate_quality, nil)
      expect(result).to eq(85) # Default from TEST_CONFIG
    end

    it "rejects quality above 100" do
      expect { tag.send(:validate_quality, 150) }.to raise_error(ArgumentError, /Invalid quality/)
    end

    it "rejects quality below 1" do
      expect { tag.send(:validate_quality, 0) }.to raise_error(ArgumentError, /Invalid quality/)
    end

    it "rejects negative quality" do
      expect { tag.send(:validate_quality, -10) }.to raise_error(ArgumentError, /Invalid quality/)
    end
  end
end
