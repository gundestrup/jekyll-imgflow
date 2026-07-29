# frozen_string_literal: true

require "spec_helper"
require "vips"

RSpec.describe JekyllImgFlow::Tags::CropTag, :unit do
  let(:site) do
    double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                   dest: "/tmp/test_site/_site")
  end
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:provider) { JekyllImgFlow::ProviderRegistry.new(config).current_provider }
  let(:tag) { described_class.new(provider) }

  # Helper method to get image information using ruby-vips
  def get_image_info(image_path)
    image = Vips::Image.new_from_file(image_path)

    {
      width: image.width,
      height: image.height,
      bands: image.bands,
      format: image.interpretation,
      file_size: File.size(image_path)
    }
  rescue StandardError => e
    # Fallback if ruby-vips fails
    {
      error: e.message,
      file_size: File.size(image_path),
      width: nil,
      height: nil
    }
  end

  describe "#process" do
    let(:test_image_dir) { create_test_dir("crop-tag-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.jpg") }
    let(:output_path) { File.join(test_image_dir, config.output, "test-crop-a1b2c3d4e.jpg") }
    let(:original_image) do
      File.expand_path("../fixtures/originals/mars-crater-large.jpg", __dir__)
    end

    before do
      # Skip tests if provider doesn't support crop operations
      skip "Provider #{provider.class} does not support crop operations" unless provider.class.supports_operation?(:crop)

      # Create test directories and copy test image
      FileUtils.mkdir_p(File.dirname(input_path))
      FileUtils.cp(original_image, input_path)
      FileUtils.mkdir_p(File.dirname(output_path))
    end

    after do
      FileUtils.rm_rf(test_image_dir)
    end

    context "with aspect ratio cropping" do
      context "with 16:9 ratio" do
        let(:options) { { ratio: "16:9" } }

        it "processes aspect ratio cropping" do
          # Get original image info
          get_image_info(original_image)

          # Process the crop
          result = tag.process(input_path, output_path, options)

          # Verify output file exists
          expect(File.exist?(output_path)).to be true
          expect(File.size(output_path)).to be > 1000

          # Verify format is still JPEG
          expect_file_signature(output_path, "jpeg")

          # Verify 16:9 aspect ratio is maintained
          actual_width, actual_height = get_image_dimensions(output_path)
          actual_ratio = (actual_width.to_f / actual_height).round(2)
          expected_ratio = (16.0 / 9).round(2)

          expect(actual_ratio).to be_within(0.1).of(expected_ratio)

          expect(result).to eq(output_path)
        end
      end

      context "with 4:3 ratio" do
        let(:options) { { aspect_ratio: "4:3" } }

        it "processes 4:3 aspect ratio cropping" do
          result = tag.process(input_path, output_path, options)

          # Verify output exists and is valid
          expect(File.exist?(output_path)).to be true
          expect_file_signature(output_path, "jpeg")

          # Verify 4:3 aspect ratio is maintained
          actual_width, actual_height = get_image_dimensions(output_path)
          actual_ratio = (actual_width.to_f / actual_height).round(2)
          expected_ratio = (4.0 / 3).round(2)

          expect(actual_ratio).to be_within(0.1).of(expected_ratio)

          expect(result).to eq(output_path)
        end
      end

      context "with 1:1 ratio (square)" do
        let(:options) { { ratio: "1:1" } }

        it "processes square aspect ratio cropping" do
          result = tag.process(input_path, output_path, options)

          # Verify output exists and is valid
          expect(File.exist?(output_path)).to be true
          expect_file_signature(output_path, "jpeg")

          # Verify 1:1 aspect ratio (square) is maintained
          actual_width, actual_height = get_image_dimensions(output_path)
          expect(actual_width).to eq(actual_height)

          expect(result).to eq(output_path)
        end
      end
    end

    context "with pixel-based cropping" do
      context "with valid coordinates" do
        let(:options) { { x: 100, y: 100, width: 800, height: 600 } }

        it "crops image to specified dimensions" do
          result = tag.process(input_path, output_path, options)

          # Verify output exists and is valid
          expect(File.exist?(output_path)).to be true
          expect_file_signature(output_path, "jpeg")

          # Verify cropping occurred and dimensions are reasonable
          cropped_info = get_image_info(output_path)
          expect(cropped_info[:width]).to be > 0
          expect(cropped_info[:height]).to be > 0
          expect(cropped_info[:width]).to be <= 2880  # Original width
          expect(cropped_info[:height]).to be <= 1800 # Original height

          expect(result).to eq(output_path)
        end
      end

      context "with centered crop using larger dimensions" do
        let(:options) { { x: 500, y: 400, width: 1200, height: 800 } }

        it "crops image to specified larger dimensions" do
          result = tag.process(input_path, output_path, options)

          # Verify output exists and is valid
          expect(File.exist?(output_path)).to be true
          expect_file_signature(output_path, "jpeg")

          # Verify cropping occurred and dimensions are reasonable
          cropped_info = get_image_info(output_path)
          expect(cropped_info[:width]).to be > 0
          expect(cropped_info[:height]).to be > 0
          expect(cropped_info[:width]).to be <= 2880  # Original width
          expect(cropped_info[:height]).to be <= 1800 # Original height

          expect(result).to eq(output_path)
        end
      end

      context "with default coordinates (x=0, y=0)" do
        let(:options) { { width: 600, height: 400 } }

        it "crops from top-left corner" do
          result = tag.process(input_path, output_path, options)

          # Verify output exists and is valid
          expect(File.exist?(output_path)).to be true
          expect_file_signature(output_path, "jpeg")

          # Verify precise crop dimensions using helper
          valid = validate_crop_operation(original_image, output_path, 600, 400)
          expect(valid).to be true

          expect(result).to eq(output_path)
        end
      end
    end

    context "with invalid inputs" do
      context "with invalid ratio format" do
        let(:options) { { ratio: "invalid" } }

        it "raises validation error for invalid ratio" do
          expect do
            tag.process(input_path, output_path, options)
          end.to raise_error(ArgumentError, /Invalid ratio/)
        end
      end

      context "with single dimension cropping" do
        let(:options) { { width: 800 } } # Missing height - should use original height

        it "processes crop with width only" do
          result = tag.process(input_path, output_path, options)

          # Verify output exists
          expect(File.exist?(output_path)).to be true
          expect(result).to eq(output_path)
        end
      end

      context "with height-only cropping" do
        let(:options) { { height: 600 } } # Missing width - should use original width

        it "processes crop with height only" do
          result = tag.process(input_path, output_path, options)

          # Verify output exists
          expect(File.exist?(output_path)).to be true
          expect(result).to eq(output_path)
        end
      end

      context "with negative coordinates" do
        let(:options) { { x: -10, y: 50, width: 400, height: 300 } }

        it "raises validation error for negative coordinates" do
          expect do
            tag.process(input_path, output_path, options)
          end.to raise_error(ArgumentError, /Invalid x/)
        end
      end

      context "with zero dimensions" do
        let(:options) { { x: 0, y: 0, width: 0, height: 300 } }

        it "raises validation error for zero dimensions" do
          expect do
            tag.process(input_path, output_path, options)
          end.to raise_error(ArgumentError, /Invalid width/)
        end
      end

      context "with invalid width in pixel crop" do
        let(:options) { { width: -100, height: 300 } }

        it "raises validation error for invalid width" do
          expect do
            tag.process(input_path, output_path, options)
          end.to raise_error(ArgumentError, /Invalid width/)
        end
      end

      context "with invalid height in pixel crop" do
        let(:options) { { width: 400, height: "invalid" } }

        it "raises validation error for invalid height" do
          expect do
            tag.process(input_path, output_path, options)
          end.to raise_error(ArgumentError, /Invalid height/)
        end
      end

      context "with invalid x coordinate" do
        let(:options) { { x: "invalid", width: 400, height: 300 } }

        it "raises validation error for invalid x" do
          expect do
            tag.process(input_path, output_path, options)
          end.to raise_error(ArgumentError, /Invalid x/)
        end
      end

      context "with invalid y coordinate" do
        let(:options) { { y: -50, width: 400, height: 300 } }

        it "raises validation error for invalid y" do
          expect do
            tag.process(input_path, output_path, options)
          end.to raise_error(ArgumentError, /Invalid y/)
        end
      end
    end
  end

  describe "#validate_ratio" do
    it "accepts valid ratio formats" do
      expect(tag.send(:validate_ratio, "16:9")).to eq("16:9")
      expect(tag.send(:validate_ratio, "4:3")).to eq("4:3")
      expect(tag.send(:validate_ratio, "1:1")).to eq("1:1")
    end

    it "accepts symbol ratios" do
      expect(tag.send(:validate_ratio, :"16:9")).to eq("16:9")
    end

    it "rejects invalid ratio formats" do
      expect do
        tag.send(:validate_ratio, "invalid")
      end.to raise_error(ArgumentError, /Invalid ratio/)
      expect { tag.send(:validate_ratio, "16-9") }.to raise_error(ArgumentError, /Invalid ratio/)
      expect { tag.send(:validate_ratio, "16") }.to raise_error(ArgumentError, /Invalid ratio/)
    end
  end

  describe "#validate_positive_integer" do
    it "accepts positive integers" do
      expect(tag.send(:validate_positive_integer, 100, "test")).to eq(100)
      expect(tag.send(:validate_positive_integer, "200", "test")).to eq(200)
    end

    it "accepts nil values" do
      expect(tag.send(:validate_positive_integer, nil, "test")).to be_nil
    end

    it "rejects negative numbers" do
      expect do
        tag.send(:validate_positive_integer, -10, "test")
      end.to raise_error(ArgumentError, /Invalid test/)
    end

    it "rejects zero" do
      expect do
        tag.send(:validate_positive_integer, 0, "test")
      end.to raise_error(ArgumentError, /Invalid test/)
    end

    it "rejects non-integers" do
      expect do
        tag.send(:validate_positive_integer, 10.5,
                 "test")
      end.to raise_error(ArgumentError, /Invalid test/)
      expect do
        tag.send(:validate_positive_integer, "abc",
                 "test")
      end.to raise_error(ArgumentError, /Invalid test/)
    end
  end

  describe "#validate_positive_integer" do
    it "accepts positive integers" do
      expect(tag.send(:validate_positive_integer, 100, "test")).to eq(100)
      expect(tag.send(:validate_positive_integer, "200", "test")).to eq(200)
    end

    it "accepts nil values" do
      expect(tag.send(:validate_positive_integer, nil, "test")).to be_nil
    end

    it "rejects negative numbers" do
      expect do
        tag.send(:validate_positive_integer, -10,
                 "test")
      end.to raise_error(ArgumentError, /Invalid test/)
    end

    it "rejects zero" do
      expect do
        tag.send(:validate_positive_integer, 0,
                 "test")
      end.to raise_error(ArgumentError, /Invalid test/)
    end
  end

  describe "#keep parameter support" do
    let(:test_image_dir) { create_test_dir("crop-keep-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.jpg") }
    let(:output_path) { File.join(test_image_dir, config.output, "test-crop-keep.jpg") }
    let(:original_image) do
      File.expand_path("../fixtures/originals/mars-crater-large.jpg", __dir__)
    end

    before do
      # Skip tests if provider doesn't support crop operations
      skip "Provider #{provider.class} does not support crop operations" unless provider.class.supports_operation?(:crop)

      # Create test directories and copy test image
      FileUtils.mkdir_p(File.dirname(input_path))
      FileUtils.mkdir_p(File.dirname(output_path))
      FileUtils.cp(original_image, input_path)
    end

    after do
      FileUtils.rm_rf(test_image_dir)
    end

    it "passes keep parameter to provider for aspect ratio cropping" do
      options = { ratio: "16:9", keep: "attention" }

      expect(provider).to receive(:crop).with("16:9", hash_including(keep: "attention"))

      tag.process(input_path, output_path, options)
    end

    it "passes keep parameter to provider for pixel cropping" do
      options = { width: 800, height: 600, keep: "center" }

      expect(provider).to receive(:crop).with(nil, hash_including(keep: "center"))

      tag.process(input_path, output_path, options)
    end

    it "validates keep parameter values" do
      options = { ratio: "16:9", keep: "invalid" }

      expect(provider).to receive(:crop).with("16:9", hash_not_including(:keep))

      tag.process(input_path, output_path, options)
    end

    it "handles nil keep parameter" do
      options = { ratio: "16:9", keep: nil }

      expect(provider).to receive(:crop).with("16:9", hash_not_including(:keep))

      tag.process(input_path, output_path, options)
    end
  end

  describe "#parse_dimension" do
    it "parses pixel values" do
      expect(tag.send(:parse_dimension, 800, 2880)).to eq(800)
      expect(tag.send(:parse_dimension, "600", 2880)).to eq(600)
    end

    it "parses percentage values" do
      expect(tag.send(:parse_dimension, "50%", 2880)).to eq(1440)
      expect(tag.send(:parse_dimension, "25%", 1800)).to eq(450)
    end

    it "returns nil for nil value" do
      expect(tag.send(:parse_dimension, nil, 2880)).to be_nil
    end
  end

  describe "#parse_position" do
    it "calculates center position" do
      expect(tag.send(:parse_position, "center", 800, 2880)).to eq(1040)
    end

    it "parses absolute position" do
      expect(tag.send(:parse_position, 100, 800, 2880)).to eq(100)
      expect(tag.send(:parse_position, "200", 800, 2880)).to eq(200)
    end

    it "returns nil for nil value" do
      expect(tag.send(:parse_position, nil, 800, 2880)).to be_nil
    end
  end

  describe "#parse_position_with_default" do
    it "defaults to center when value is nil" do
      expect(tag.send(:parse_position_with_default, nil, 800, 2880)).to eq(1040)
    end

    it "calculates center position" do
      expect(tag.send(:parse_position_with_default, "center", 800, 2880)).to eq(1040)
    end

    it "parses absolute position" do
      expect(tag.send(:parse_position_with_default, 100, 800, 2880)).to eq(100)
    end
  end

  describe "#validate_crop_dimensions" do
    it "raises when crop exceeds original dimensions" do
      expect do
        tag.send(:validate_crop_dimensions, 0, 0, 3000, 1800, 2880, 1800)
      end.to raise_error(ArgumentError, /Crop area exceeds/)
    end

    it "raises when crop position is negative" do
      expect do
        tag.send(:validate_crop_dimensions, -1, 0, 800, 600, 2880, 1800)
      end.to raise_error(ArgumentError, /negative/)
    end

    it "passes for valid crop dimensions" do
      result = tag.send(:validate_crop_dimensions, 0, 0, 800, 600, 2880, 1800)
      expect(result).to be_nil
    end
  end

  describe "#process with no ratio or dimensions" do
    let(:test_image_dir) { create_test_dir("crop-no-dims-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.jpg") }
    let(:output_path) { File.join(test_image_dir, config.output, "test-crop.jpg") }
    let(:original_image) do
      File.expand_path("../fixtures/originals/mars-crater-large.jpg", __dir__)
    end

    before do
      FileUtils.mkdir_p(File.dirname(input_path))
      FileUtils.cp(original_image, input_path)
      FileUtils.mkdir_p(File.dirname(output_path))
    end

    after do
      FileUtils.rm_rf(test_image_dir)
    end

    it "raises ArgumentError" do
      expect do
        tag.process(input_path, output_path, {})
      end.to raise_error(ArgumentError, /requires ratio or at least one dimension/)
    end
  end

  describe "#calculate_aspect_ratio_dimensions" do
    let(:test_image_dir) { create_test_dir("crop-ratio-calc-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.jpg") }
    let(:original_image) do
      File.expand_path("../fixtures/originals/mars-crater-large.jpg", __dir__)
    end

    before do
      FileUtils.mkdir_p(File.dirname(input_path))
      FileUtils.cp(original_image, input_path)
    end

    after do
      FileUtils.rm_rf(test_image_dir)
    end

    it "calculates dimensions for 16:9 on 2880x1800" do
      result = tag.send(:calculate_aspect_ratio_dimensions, input_path, "16:9", {})
      # 2880x1800 is 1.6 ratio, 16:9 is 1.778, so image is taller than target - crop height
      expect(result[:calculated_width]).to eq(2880)
      expect(result[:calculated_x]).to eq(0)
      expect(result[:calculated_height]).to be <= 1800
    end

    it "calculates dimensions for taller target ratio (4:3 on 2880x1800)" do
      result = tag.send(:calculate_aspect_ratio_dimensions, input_path, "4:3", {})
      # 4:3 is 1.333, image is 1.6, so image is wider - crop width
      expect(result[:calculated_height]).to eq(1800)
      expect(result[:calculated_width]).to be <= 2880
    end

    it "calculates dimensions for square ratio (1:1)" do
      result = tag.send(:calculate_aspect_ratio_dimensions, input_path, "1:1", {})
      # 1:1 is 1.0, image is 1.6, so image is wider - crop width
      expect(result[:calculated_height]).to eq(1800)
      expect(result[:calculated_width]).to eq(1800)
      expect(result[:calculated_y]).to eq(0)
    end
  end
end
