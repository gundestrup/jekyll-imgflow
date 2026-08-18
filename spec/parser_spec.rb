# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::Parser, :unit do
  let(:test_image_name) { TestPictures.get(:default).first } # Use helper
  let(:site) { double("site", config: TEST_CONFIG, source: "/tmp/test_site") }

  describe ".parse" do
    context "simple tag syntax" do
      it "parses image path and width" do
        result = described_class.parse("image.jpg width:800", nil)

        expect(result[:image_path]).to eq("image.jpg")
        expect(result[:operations]).to be_an(Array)
        expect(result[:operations].first[:params]).to include(width: 800)
      end

      it "removes quotes around an image path" do
        result = described_class.parse('"subdir/more_subdir/photo.jpg" resize width:800', nil)

        expect(result[:image_path]).to eq("subdir/more_subdir/photo.jpg")
        expect(result[:operations].first[:params]).to include(width: 800)
      end

      it "parses multiple operations" do
        result = described_class.parse("image.jpg width:800 height:600 quality:85", nil)

        params = result[:operations].first[:params]
        expect(params).to include(width: 800, height: 600, quality: 85)
      end

      it "parses format option" do
        result = described_class.parse("image.jpg width:800 format:webp", nil)

        params = result[:operations].first[:params]
        expect(params).to include(width: 800, format: "webp")
      end
    end

    context "preset syntax" do
      it "parses preset reference" do
        result = described_class.parse("image.jpg preset:hero", nil)

        expect(result[:image_path]).to eq("image.jpg")
        expect(result[:preset]).to eq("hero")
      end
    end

    context "HTML attributes" do
      it "parses alt attribute" do
        result = described_class.parse("image.jpg width:800 alt:Test", nil)

        expect(result[:html_attributes]).to include(alt: "Test")
      end

      it "parses class attribute" do
        result = described_class.parse("image.jpg width:800 class:hero", nil)

        expect(result[:html_attributes]).to include(class: "hero")
      end

      it "parses quoted values" do
        result = described_class.parse('image.jpg alt:"Hero Image" class:"banner large"', nil)

        expect(result[:html_attributes][:alt]).to include("Hero")
        expect(result[:html_attributes][:class]).to include("banner")
      end
    end

    context "value type parsing" do
      it "parses integer values" do
        result = described_class.parse("image.jpg width:800 quality:85", nil)

        params = result[:operations].first[:params]
        expect(params[:width]).to be_a(Integer)
        expect(params[:width]).to eq(800)
        expect(params[:quality]).to be_a(Integer)
        expect(params[:quality]).to eq(85)
      end

      it "parses float values" do
        result = described_class.parse("image.jpg opacity:0.7 ratio:1.5", nil)

        # Find the alpha_opacity operation (not the first one due to crop+resize logic)
        opacity_op = result[:operations].find { |op| op[:type] == :alpha_opacity }
        expect(opacity_op).not_to be_nil

        params = opacity_op[:params]
        expect(params[:opacity]).to be_a(Float)
        expect(params[:opacity]).to eq(0.7)
      end

      it "parses string values" do
        result = described_class.parse("image.jpg format:webp class:hero", nil)

        params = result[:operations].first[:params]
        expect(params[:format]).to be_a(String)
        expect(params[:format]).to eq("webp")
      end
    end

    context "liquid variables" do
      it "parses already-resolved liquid variables" do
        # NOTE: Liquid resolves {{ my_width }} to 1200 BEFORE Parser sees it
        # Parser receives: "#{test_image_name} width:1200"
        context_obj = double("context", registers: { site: site })
        result = described_class.parse("#{test_image_name} width:1200", context_obj)

        expect(result[:image_path]).to eq(test_image_name)
        params = result[:operations].first[:params]
        expect(params[:width]).to eq(1200)
      end

      it "parses string values from resolved variables" do
        # NOTE: Liquid resolves {{ my_format }} to "webp" BEFORE Parser sees it
        # Parser receives: "#{test_image_name} format:webp"
        context_obj = double("context", registers: { site: site })
        result = described_class.parse("#{test_image_name} format:webp", context_obj)

        expect(result[:image_path]).to eq(test_image_name)
        params = result[:operations].first[:params]
        expect(params[:format]).to eq("webp")
      end

      it "generates TestPictures-compatible filenames from resolved variables" do
        # Test end-to-end: Liquid resolves variables → Parser parses → FilenameGenerator generates
        # Use nil context to avoid file validation (parser testing focus)
        result = described_class.parse("#{test_image_name} width:800 format:webp quality:85", nil)

        # Use FilenameGenerator to test the complete flow
        filename_generator = JekyllImgFlow::FilenameGenerator.new
        combined_params = {}
        result[:operations].each do |op|
          combined_params.merge!(op[:params])
        end

        generated_filename = filename_generator.generate_filename(test_image_name, combined_params)
        expected_filename = TestPictures.expected_filename(test_image_name, :md, :webp)

        expect(generated_filename).to eq(expected_filename)
      end
    end

    context "edge cases" do
      it "handles empty markup" do
        result = described_class.parse("", nil)

        expect(result).to be_a(Hash)
        expect(result[:image_path]).to be_nil
      end

      it "handles markup with only image path" do
        result = described_class.parse(test_image_name, nil)

        expect(result[:image_path]).to eq(test_image_name)
        expect(result[:operations]).to be_an(Array)
      end

      it "handles special characters in image path" do
        result = described_class.parse("#{test_image_name} width:800", nil)

        expect(result[:image_path]).to eq(test_image_name)
        expect(result[:operations].first[:params]).to include(width: 800)
      end
    end

    describe "opacity parsing" do
      it "generates different hashes with opacity parameter" do
        # Test that opacity affects hash generation
        result = described_class.parse("#{test_image_name} width:800 opacity:0.5", nil)

        filename_generator = JekyllImgFlow::FilenameGenerator.new
        combined_params = {}
        result[:operations].each do |op|
          combined_params.merge!(op[:params])
        end

        generated_filename = filename_generator.generate_filename(test_image_name, combined_params)

        # Should be different from default TestPictures hash (opacity changes hash)
        expected_default = TestPictures.expected_filename(test_image_name, :md, :jpg)
        expect(generated_filename).not_to eq(expected_default)
      end
    end

    context "TestPictures integration" do
      it "parses operations that match TestPictures expectations" do
        # Test parser with real TestPictures image
        result = described_class.parse("#{test_image_name} width:800 format:webp quality:85", nil)

        expect(result[:image_path]).to eq(test_image_name)
        expect(result[:operations]).to be_an(Array)

        # Extract operations for validation
        resize_op = result[:operations].find { |op| op[:type] == :resize }
        format_op = result[:operations].find { |op| op[:type] == :format }
        quality_op = result[:operations].find { |op| op[:type] == :quality }

        expect(resize_op[:params]).to include(width: 800)
        expect(format_op[:params]).to include(format: "webp")
        expect(quality_op[:params]).to include(quality: 85)
      end

      it "generates operations that produce TestPictures-compatible filenames" do
        # Parse markup that should produce TestPictures md size webp
        result = described_class.parse("#{test_image_name} width:800 format:webp quality:85", nil)

        # Use FilenameGenerator to test end-to-end
        filename_generator = JekyllImgFlow::FilenameGenerator.new

        # Combine operations as the system would
        combined_params = {}
        result[:operations].each do |op|
          combined_params.merge!(op[:params])
        end

        generated_filename = filename_generator.generate_filename(test_image_name, combined_params)
        expected_filename = TestPictures.expected_filename(test_image_name, :md, :webp)

        expect(generated_filename).to eq(expected_filename)
      end

      it "handles parser behavior (no default quality) correctly" do
        # Test parser without quality (parser doesn't add defaults)
        result = described_class.parse("#{test_image_name} width:800 format:webp", nil)

        # Generate filename with parser operations (no quality)
        filename_generator = JekyllImgFlow::FilenameGenerator.new
        combined_params = {}
        result[:operations].each do |op|
          combined_params.merge!(op[:params])
        end

        generated_filename = filename_generator.generate_filename(test_image_name, combined_params)
        expected_specialized = TestPictures.specialized_filename(test_image_name, :md, :webp)

        expect(generated_filename).to eq(expected_specialized)
      end
    end
  end

  describe "key=value format parsing" do
    it "parses markup with = separator" do
      result = described_class.parse("image.jpg width=800 height=600")
      expect(result[:image_path]).to eq("image.jpg")
      expect(result[:raw_options][:width]).to eq(800)
      expect(result[:raw_options][:height]).to eq(600)
    end
  end

  describe "structured data validation" do
    it "validates structured data with image_path and operations" do
      data = { image_path: "test.jpg", operations: [{ type: :resize, params: { width: 800 } }] }
      result = described_class.parse(data)
      expect(result[:image_path]).to eq("test.jpg")
      expect(result[:operations]).to eq(data[:operations])
    end

    it "returns error for structured data without image_path" do
      data = { image_path: nil, operations: [] }
      result = described_class.parse(data)
      expect(result[:image_path]).to be_nil
      expect(result[:error]).to eq("No image path found in structured data")
    end

    it "uses html_attributes from structured data" do
      data = { image_path: "test.jpg", operations: [], html_attributes: { alt: "Test" } }
      result = described_class.parse(data)
      expect(result[:html_attributes][:alt]).to eq("Test")
    end
  end

  describe "extract_image_path fallback" do
    it "extracts first word from markup when no image_path in options" do
      result = described_class.parse("photo.jpg width:800")
      expect(result[:image_path]).to eq("photo.jpg")
    end

    it "returns nil for empty markup" do
      result = described_class.parse("")
      expect(result[:image_path]).to be_nil
      expect(result[:error]).to eq("No image path found in markup")
    end
  end
end
