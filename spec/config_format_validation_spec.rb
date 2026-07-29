# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::Config, "Format Validation", :unit do
  let(:site) { double("site", config: TEST_CONFIG) }
  let(:config) { described_class.new(site) }

  describe "#supported_input_format?" do
    it "returns true for supported input formats" do
      # Test formats from TEST_CONFIG
      expect(config.supported_input_format?("jpg")).to be true
      expect(config.supported_input_format?("jpeg")).to be true
      expect(config.supported_input_format?("png")).to be true
      expect(config.supported_input_format?("webp")).to be true
      expect(config.supported_input_format?("gif")).to be true
    end

    it "returns false for unsupported input formats" do
      expect(config.supported_input_format?("bmp")).to be false
      expect(config.supported_input_format?("ico")).to be false
      expect(config.supported_input_format?("unknown")).to be false
    end

    it "handles format with dot prefix" do
      expect(config.supported_input_format?(".jpg")).to be true
      expect(config.supported_input_format?(".png")).to be true
    end

    it "is case insensitive" do
      expect(config.supported_input_format?("JPG")).to be true
      expect(config.supported_input_format?("PNG")).to be true
      expect(config.supported_input_format?("WebP")).to be true
    end
  end

  describe "#supported_output_format?" do
    it "returns true for supported output formats" do
      # Test formats from TEST_CONFIG
      expect(config.supported_output_format?("webp")).to be true
      expect(config.supported_output_format?("avif")).to be true
      expect(config.supported_output_format?("jpg")).to be true
      expect(config.supported_output_format?("png")).to be true
    end

    it "returns false for unsupported output formats" do
      expect(config.supported_output_format?("gif")).to be false
      expect(config.supported_output_format?("tiff")).to be false
      expect(config.supported_output_format?("svg")).to be false
    end

    it "handles format with dot prefix" do
      expect(config.supported_output_format?(".webp")).to be true
      expect(config.supported_output_format?(".jpg")).to be true
    end

    it "is case insensitive" do
      expect(config.supported_output_format?("WEBP")).to be true
      expect(config.supported_output_format?("AVIF")).to be true
      expect(config.supported_output_format?("JPG")).to be true
    end
  end

  describe "#validate_input_format!" do
    it "does not raise error for supported formats" do
      expect(config.validate_input_format!("jpg")).to be_nil
      expect(config.validate_input_format!("png")).to be_nil
      expect(config.validate_input_format!("webp")).to be_nil
    end

    it "raises ArgumentError for unsupported formats" do
      expect do
        config.validate_input_format!("bmp")
      end.to raise_error(ArgumentError, /Unsupported input format/)
      expect do
        config.validate_input_format!("unknown")
      end.to raise_error(ArgumentError,
                         /Unsupported input format/)
    end

    it "includes supported formats in error message" do
      config.validate_input_format!("bmp")
    rescue ArgumentError => e
      expect(e.message).to include("jpg")
      expect(e.message).to include("png")
      expect(e.message).to include("webp")
    end
  end

  describe "#validate_output_format!" do
    it "does not raise error for supported formats" do
      expect(config.validate_output_format!("webp")).to be_nil
      expect(config.validate_output_format!("avif")).to be_nil
      expect(config.validate_output_format!("jpg")).to be_nil
    end

    it "raises ArgumentError for unsupported formats" do
      expect do
        config.validate_output_format!("gif")
      end.to raise_error(ArgumentError,
                         /Unsupported output format/)
      expect do
        config.validate_output_format!("tiff")
      end.to raise_error(ArgumentError,
                         /Unsupported output format/)
    end

    it "includes supported formats in error message" do
      config.validate_output_format!("gif")
    rescue ArgumentError => e
      expect(e.message).to include("webp")
      expect(e.message).to include("avif")
      expect(e.message).to include("jpg")
    end
  end

  describe "#normalized_input_formats" do
    it "returns lowercase format list" do
      formats = config.normalized_input_formats
      expect(formats).to be_an(Array)
      formats.each do |format|
        expect(format).to eq(format.downcase)
      end
    end

    it "includes all configured input formats" do
      formats = config.normalized_input_formats
      expect(formats).to include("jpg", "jpeg", "png", "webp")
    end
  end

  describe "#normalized_output_formats" do
    it "returns lowercase format list" do
      formats = config.normalized_output_formats
      expect(formats).to be_an(Array)
      formats.each do |format|
        expect(format).to eq(format.downcase)
      end
    end

    it "includes all configured output formats" do
      formats = config.normalized_output_formats
      expect(formats).to include("webp", "avif", "jpg", "png")
    end
  end

  describe "integration with _config.yml" do
    it "uses config file for format validation" do
      # This ensures format validation is driven by _config.yml
      # not hardcoded in the application

      # Input formats from config should work
      config.input_formats.each do |format|
        expect(config.supported_input_format?(format)).to be true
      end

      # Output formats from config should work
      config.formats.each do |format|
        expect(config.supported_output_format?(format)).to be true
      end
    end

    it "rejects formats not in config" do
      # Formats not in config should be rejected
      non_input_format = "xyz123"
      non_output_format = "abc456"

      expect(config.supported_input_format?(non_input_format)).to be false
      expect(config.supported_output_format?(non_output_format)).to be false
    end
  end
end
