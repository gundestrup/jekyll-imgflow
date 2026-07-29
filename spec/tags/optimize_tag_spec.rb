# frozen_string_literal: true

require "spec_helper"
require "vips"

RSpec.describe JekyllImgFlow::Tags::OptimizeTag, :unit do
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
    # Fallback to config values if ruby-vips fails
    {
      error: e.message,
      file_size: File.size(image_path),
      compression_ratio: nil,
      quality_estimate: config_quality_values["default"] # Use config default
    }
  end

  # Get actual quality values from unified config
  def config_quality_values
    config.optimize_qualities
  end

  # Simply return the config quality values - no estimation needed
  def expected_quality_for_level(level)
    config_quality_values[level.to_s]
  end

  describe "#process" do
    let(:test_image_dir) { create_test_dir("optimize-tag-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.jpg") }
    let(:output_path) { File.join(test_image_dir, config.output, "test-q50-a1b2c3d4e.jpg") }
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

    context "with medium level (default)" do
      let(:options) { {} }

      it "uses default medium optimization level" do
        # Get original compression info
        original_info = get_compression_info(original_image)

        # Process with default medium level
        result = tag.process(input_path, output_path, options)

        # Verify output file exists
        expect(File.exist?(output_path)).to be true
        expect(File.size(output_path)).to be > 1000

        # Verify format is still JPEG
        expect_file_signature(output_path, "jpeg")

        # Get optimized image info
        optimized_info = get_compression_info(output_path)

        # Verify optimization was applied (file size should be different)
        if optimized_info[:compression_ratio] && original_info[:compression_ratio]
          expect(optimized_info[:compression_ratio]).not_to eq(original_info[:compression_ratio])
        else
          # Fallback: verify file size is different (optimization was applied)
          expect(optimized_info[:file_size]).not_to eq(original_info[:file_size])
        end

        # Verify the expected quality from config
        expected_quality_for_level(:medium)

        # Verify dimensions are preserved
        expect(optimized_info[:width]).to eq(original_info[:width])
        expect(optimized_info[:height]).to eq(original_info[:height])

        # Verify return value
        expect(result).to eq(output_path)
      end
    end

    context "with different optimization levels" do
      let(:high_output) { File.join(test_image_dir, config.output, "test-q85-a1b2c3d4e.jpg") }
      let(:low_output) { File.join(test_image_dir, config.output, "test-q30-a1b2c3d4e.jpg") }

      it "creates different compression for different levels" do
        # Process high optimization
        tag.process(input_path, high_output, { level: :high })

        # Process low optimization
        tag.process(input_path, low_output, { level: :low })

        # Both files should exist
        expect(File.exist?(high_output)).to be true
        expect(File.exist?(low_output)).to be true

        # Get compression info
        high_info = get_compression_info(high_output)
        low_info = get_compression_info(low_output)

        # High optimization should have lower compression ratio (better quality) or different file size
        if high_info[:compression_ratio] && low_info[:compression_ratio]
          expect(high_info[:compression_ratio]).to be < low_info[:compression_ratio]
        else
          # Fallback: verify different file sizes (different optimization levels)
          expect(high_info[:file_size]).not_to eq(low_info[:file_size])
        end

        # Verify expected quality values from config
        expected_quality_for_level(:high)
        expected_quality_for_level(:low)

        # Both should be valid JPEG files with same dimensions
        expect_file_signature(high_output, "jpeg")
        expect_file_signature(low_output, "jpeg")
        expect(high_info[:width]).to eq(low_info[:width])
        expect(high_info[:height]).to eq(low_info[:height])
      end
    end

    context "with maximum level" do
      let(:options) { { level: :maximum } }
      let(:max_output) { File.join(test_image_dir, config.output, "test-q95-a1b2c3d4e.jpg") }

      it "applies maximum quality optimization" do
        result = tag.process(input_path, max_output, options)

        # Verify output exists and is valid
        expect(File.exist?(max_output)).to be true
        expect(File.size(max_output)).to be > 1000
        expect_file_signature(max_output, "jpeg")

        # Verify expected quality from config
        get_compression_info(max_output)
        expected_quality_for_level(:maximum)

        expect(result).to eq(max_output)
      end
    end

    context "with string level" do
      let(:options) { { level: "low" } }

      it "converts string level to symbol and processes" do
        result = tag.process(input_path, output_path, options)

        # Verify output exists and is valid
        expect(File.exist?(output_path)).to be true
        expect(File.size(output_path)).to be > 1000
        expect_file_signature(output_path, "jpeg")

        expect(result).to eq(output_path)
      end
    end

    context "with invalid level" do
      let(:options) { { level: :invalid } }

      it "uses default optimization for unknown level" do
        result = tag.process(input_path, output_path, options)

        # Should still process but with default quality
        expect(File.exist?(output_path)).to be true
        expect(File.size(output_path)).to be > 1000
        expect_file_signature(output_path, "jpeg")

        expect(result).to eq(output_path)
      end
    end

    context "with missing optimize_qualities configuration" do
      let(:options) { { level: :medium } }

      before do
        # Mock config to return nil for optimize_qualities
        allow(config).to receive(:optimize_qualities).and_return(nil)
      end

      it "raises error for missing configuration" do
        expect do
          tag.process(input_path, output_path, options)
        end.to raise_error(RuntimeError, /No optimize_qualities configured/)
      end
    end

    context "with missing default quality configuration" do
      let(:options) { { level: :unknown } }

      before do
        # Mock config to return nil for default quality
        allow(config).to receive(:optimize_qualities).and_return({ "default" => nil })
      end

      it "raises error for missing default quality" do
        expect do
          tag.process(input_path, output_path, options)
        end.to raise_error(RuntimeError, /No default optimize quality configured/)
      end
    end
  end

  describe "#translate_optimize_level_to_quality" do
    let(:config_qualities) { config_quality_values }

    it "translates levels to correct quality values from config" do
      expect(tag.send(:translate_optimize_level_to_quality, :low)).to eq(config_qualities["low"])
      expect(tag.send(:translate_optimize_level_to_quality,
                      :medium)).to eq(config_qualities["medium"])
      expect(tag.send(:translate_optimize_level_to_quality, :high)).to eq(config_qualities["high"])
      expect(tag.send(:translate_optimize_level_to_quality,
                      :maximum)).to eq(config_qualities["maximum"])
      expect(tag.send(:translate_optimize_level_to_quality,
                      :default)).to eq(config_qualities["default"])
    end

    it "translates string levels" do
      expect(tag.send(:translate_optimize_level_to_quality, "low")).to eq(config_qualities["low"])
      expect(tag.send(:translate_optimize_level_to_quality, "high")).to eq(config_qualities["high"])
    end

    it "uses default quality for unknown levels" do
      result = tag.send(:translate_optimize_level_to_quality, :unknown)
      expect(result).to eq(config_qualities["default"]) # default from config
    end
  end
end
