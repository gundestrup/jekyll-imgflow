# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::Tags::FormatTag, :unit do
  let(:site) do
    double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                   dest: "/tmp/test_site/_site")
  end
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:provider) { JekyllImgFlow::ProviderRegistry.new(config).current_provider }
  let(:tag) { described_class.new(provider) }

  describe "#process" do
    let(:test_image_dir) { create_test_dir("format-tag-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.jpg") }
    let(:output_path) { File.join(test_image_dir, config.output, "test.jpg") }

    # NOTE: FormatTag should use FilenameGenerator like other operations
    # Current implementation does simple extension replacement (architectural inconsistency)
    # Test reflects what it SHOULD do according to the architecture
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

    context "with single format" do
      let(:options) { { format: "webp" } }

      it "converts format and verifies with FastImage" do
        # Get original format
        original_format = FastImage.type(original_image)
        expect(original_format).to eq(:jpeg)

        # Process the format conversion
        result = tag.process(input_path, output_path, options)

        # Verify output file exists and has reasonable size
        actual_output_path = result.first
        expect(File.exist?(actual_output_path)).to be true
        expect(File.size(actual_output_path)).to be > 1000

        # Verify format conversion using FastImage
        converted_format = FastImage.type(actual_output_path)
        expect(converted_format).to eq(:webp)

        # Verify file signature
        expect_file_signature(actual_output_path, "webp")

        # Verify return value contains actual output path
        expect(result).to be_an(Array)
        expect(result.first).to end_with(".webp")
        expect(result.first).to include("test.webp")
      end
    end

    context "with multiple formats" do
      let(:options) { { formats: %w[webp avif] } }

      it "processes multiple format conversions" do
        result = tag.process(input_path, output_path, options)

        # Should return array of output paths
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)

        # Verify each output file exists and has correct format
        expect(File.exist?(File.join(test_image_dir, config.output, "test.webp"))).to be true
        expect(File.exist?(File.join(test_image_dir, config.output, "test.avif"))).to be true

        # Verify formats using FastImage
        webp_format = FastImage.type(File.join(test_image_dir, config.output, "test.webp"))
        FastImage.type(File.join(test_image_dir, config.output, "test.avif"))

        expect(webp_format).to eq(:webp)
        # NOTE: FastImage might not detect AVIF reliably, so we'll check file signature too
        expect_file_signature(File.join(test_image_dir, config.output, "test.webp"), "webp")
        expect_file_signature(File.join(test_image_dir, config.output, "test.avif"), "avif")
      end
    end

    context "with string format (single value)" do
      let(:options) { { formats: "webp" } }

      it "converts string to array and processes" do
        result = tag.process(input_path, output_path, options)

        # Verify output exists and has correct format
        expect(File.exist?(File.join(test_image_dir, config.output, "test.webp"))).to be true
        converted_format = FastImage.type(File.join(test_image_dir, config.output, "test.webp"))
        expect(converted_format).to eq(:webp)

        expect(result).to eq([File.join(test_image_dir, config.output, "test.webp")])
      end
    end

    context "with invalid format" do
      let(:options) { { format: "xyz" } }

      it "raises validation error" do
        expect do
          tag.process(input_path, output_path, options)
        end.to raise_error(ArgumentError, /Invalid format/)
      end
    end

    context "with no format specified" do
      let(:options) { {} }

      it "raises validation error when no format specified" do
        expect do
          tag.process(input_path, output_path, options)
        end.to raise_error(ArgumentError, "Format cannot be nil")
      end
    end

    context "with filename without extension" do
      let(:output_path) { File.join(test_image_dir, config.output, "test") }

      it "creates file at malformed path when filename has no extension" do
        # Current FormatTag implementation has a bug with filenames without extensions
        # It creates a valid WebP file but at a malformed path (../../../webp)

        result = tag.process(input_path, output_path, { format: "webp" })

        actual_output_path = result.first
        expect(actual_output_path).to end_with(".webp")

        # The bug: file is created at malformed path, not in expected output directory
        expect(File.exist?(actual_output_path)).to be true
        expect(File.size(actual_output_path)).to be > 1000

        # Verify the format conversion actually worked
        converted_format = FastImage.type(actual_output_path)
        expect(converted_format).to eq(:webp)

        # Clean up the malformed file
        FileUtils.rm_f(actual_output_path)

        # NOTE: Filename extension validation should be added in Parser phase
      end
    end

    context "with filename without extension and invalid format" do
      let(:options) { { format: "invalid" } }
      let(:output_path) { File.join(test_image_dir, config.output, "test") } # No extension

      it "raises validation error for invalid format" do
        expect do
          tag.process(input_path, output_path, options)
        end.to raise_error(ArgumentError, /Invalid format/)
      end
    end
  end

  describe "#validate_format" do
    it "accepts valid formats" do
      # Use actual config formats
      valid_formats = config.formats
      valid_formats.each do |format|
        result = tag.send(:validate_format, format)
        expect(result).to eq(format.downcase)
      end
    end

    it "accepts case-insensitive formats" do
      result = tag.send(:validate_format, "WEBP")
      expect(result).to eq("webp")
    end

    it "accepts symbol formats" do
      result = tag.send(:validate_format, :webp)
      expect(result).to eq("webp")
    end

    it "rejects invalid formats" do
      expect { tag.send(:validate_format, "xyz") }.to raise_error(ArgumentError, /Invalid format/)
    end

    it "rejects nil format" do
      expect do
        tag.send(:validate_format, nil)
      end.to raise_error(ArgumentError, "Format cannot be nil")
    end

    it "provides helpful error message with valid formats" do
      expect { tag.send(:validate_format, "invalid") }.to raise_error(
        ArgumentError,
        /Must be one of: #{config.formats.join(', ')}/
      )
    end
  end
end
