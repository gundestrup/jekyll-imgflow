# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::PictureTagAdaptor, :unit do
  let(:site) { double("site", config: TEST_CONFIG) }
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:adaptor) { described_class.new(site, config) }

  # Test each translation function independently
  describe "#translate_operations" do
    it "translates crop ratios" do
      operations = ["16:9", "4:3"]
      result = adaptor.send(:translate_operations, operations)

      expect(result).to eq(["ratio:16:9", "ratio:4:3"])
    end

    it "translates crop with position" do
      operations = ["16:9 center"]
      result = adaptor.send(:translate_operations, operations)

      expect(result).to eq(["ratio:16:9", "keep:center"])
    end

    it "translates position only" do
      operations = ["entropy"]
      result = adaptor.send(:translate_operations, operations)

      expect(result).to eq(["keep:entropy"])
    end

    it "translates preset names" do
      operations = ["hero"]
      result = adaptor.send(:translate_operations, operations)

      expect(result).to eq(["preset:hero"])
    end

    it "translates width" do
      operations = ["800"]
      result = adaptor.send(:translate_operations, operations)

      expect(result).to eq(["width:800"])
    end

    it "handles mixed operations" do
      operations = ["hero", "16:9", "800"]
      result = adaptor.send(:translate_operations, operations)

      expect(result).to eq(["preset:hero", "ratio:16:9", "width:800"])
    end
  end

  describe "#translate_media_queries" do
    it "translates mobile crop as primary" do
      media_queries = {
        "mobile" => { image: "mobile.jpg", crop: { ratio: "1:1", keep: "center" } },
        "tablet" => { image: "tablet.jpg", crop: { ratio: "4:3", keep: "center" } }
      }
      result = adaptor.send(:translate_media_queries, media_queries)

      expect(result).to eq(["ratio:1:1", "keep:center"])
    end

    it "falls back to first available when no mobile" do
      media_queries = {
        "tablet" => { image: "tablet.jpg", crop: { ratio: "4:3", keep: "center" } }
      }
      result = adaptor.send(:translate_media_queries, media_queries)

      expect(result).to eq(["ratio:4:3", "keep:center"])
    end

    it "returns empty for no media queries" do
      result = adaptor.send(:translate_media_queries, {})

      expect(result).to eq([])
    end

    it "returns empty when crop is nil" do
      media_queries = {
        "mobile" => { image: "mobile.jpg", crop: nil }
      }
      result = adaptor.send(:translate_media_queries, media_queries)

      expect(result).to eq([])
    end
  end

  describe "#categorize_arguments" do
    it "categorizes image path" do
      args = ["example.jpg"]
      result = adaptor.send(:categorize_arguments, args)

      expect(result[:image]).to eq("example.jpg")
      expect(result[:operations]).to eq([])
      expect(result[:media_queries]).to eq({})
    end

    it "categorizes operations" do
      args = ["example.jpg", "16:9", "hero", "800"]
      result = adaptor.send(:categorize_arguments, args)

      expect(result[:image]).to eq("example.jpg")
      expect(result[:operations]).to eq(["16:9", "hero", "800"])
    end

    it "categorizes HTML attributes" do
      args = ["example.jpg", "--alt", "Alt", "Text", "--link", "/path"]
      result = adaptor.send(:categorize_arguments, args)

      expect(result[:image]).to eq("example.jpg")
      expect(result[:html_attributes][:alt]).to eq("Alt Text")
      expect(result[:html_attributes][:link]).to eq("/path")
    end

    it "categorizes element attributes" do
      args = ["example.jpg", "--picture", "class=hero", "data-test"]
      result = adaptor.send(:categorize_arguments, args)

      expect(result[:html_attributes][:picture]["class"]).to eq("hero")
      expect(result[:html_attributes][:picture]["data-test"]).to be(true)
    end

    it "categorizes media queries" do
      args = ["example.jpg", "mobile:", "mobile.jpg", "1:1"]
      result = adaptor.send(:categorize_arguments, args)

      expect(result[:media_queries]["mobile"][:image]).to eq("mobile.jpg")
      expect(result[:media_queries]["mobile"][:crop][:ratio]).to eq("1:1")
      expect(result[:media_queries]["mobile"][:crop][:keep]).to eq("center")
    end

    it "categorizes markup format" do
      args = ["example.jpg", "picture"]
      result = adaptor.send(:categorize_arguments, args)

      expect(result[:markup_format]).to eq("picture")
    end
  end

  # Test the complete flow with all argument types combined
  describe "#translate_to_imgflow - complete flow" do
    it "handles all argument types together" do
      picture_markup = "{% picture hero example.jpg 16:9 entropy mobile: mobile.jpg 1:1 --alt Hero Image --picture class=\"hero\" --link / %}"
      result = adaptor.translate_to_imgflow(picture_markup)

      # Check markup contains all translated parts
      expect(result[:markup]).to include("example.jpg")
      expect(result[:markup]).to include("preset:hero")
      expect(result[:markup]).to include("ratio:1:1") # Mobile crop takes priority
      expect(result[:markup]).to include("keep:center")
      expect(result[:markup]).to include("formats:webp,jpg")

      # Check attributes
      expect(result[:attributes][:alt]).to eq("Hero Image")
      expect(result[:attributes][:link]).to eq("/")
      expect(result[:attributes][:picture]["class"]).to eq("hero")
    end

    it "handles minimal input" do
      picture_markup = "{% picture example.jpg %}"
      result = adaptor.translate_to_imgflow(picture_markup)

      expect(result[:markup]).to eq("example.jpg formats:webp,jpg")
      expect(result[:attributes][:alt]).to be_nil
    end

    it "handles empty input" do
      picture_markup = "{% picture %}"
      result = adaptor.translate_to_imgflow(picture_markup)

      expect(result[:markup]).to eq("")
      expect(result[:attributes]).to eq({})
    end
  end

  # Helper method tests
  describe "#parse_crop_from_arg" do
    it "parses ratio only" do
      result = adaptor.send(:parse_crop_from_arg, "16:9")

      expect(result[:ratio]).to eq("16:9")
      expect(result[:keep]).to eq("center")
    end

    it "parses ratio with position" do
      result = adaptor.send(:parse_crop_from_arg, "16:9 entropy")

      expect(result[:ratio]).to eq("16:9")
      expect(result[:keep]).to eq("entropy")
    end

    it "returns nil for invalid input" do
      result = adaptor.send(:parse_crop_from_arg, "invalid")

      expect(result).to be_nil
    end
  end

  describe "#strip_quotes" do
    it "strips double quotes" do
      result = adaptor.send(:strip_quotes, '"text"')
      expect(result).to eq("text")
    end

    it "strips single quotes" do
      result = adaptor.send(:strip_quotes, "'text'")
      expect(result).to eq("text")
    end

    it "handles unquoted text" do
      result = adaptor.send(:strip_quotes, "text")
      expect(result).to eq("text")
    end

    it "handles empty string" do
      result = adaptor.send(:strip_quotes, "")
      expect(result).to eq("")
    end

    it "handles nil string" do
      result = adaptor.send(:strip_quotes, nil)
      expect(result).to eq("")
    end
  end

  describe "#to_imgflow_tag" do
    it "builds complete imgflow tag from picture markup" do
      result = adaptor.to_imgflow_tag("{% picture example.jpg --alt \"Test\" %}")

      expect(result).to start_with("{% imgflow")
      expect(result).to end_with("%}")
      expect(result).to include("example.jpg")
      expect(result).to include("alt:\"Test\"")
    end

    it "returns empty string for empty translation" do
      result = adaptor.to_imgflow_tag("{% picture %}")
      expect(result).to eq("")
    end

    it "includes picture-prefixed attributes in tag" do
      result = adaptor.to_imgflow_tag(
        "{% picture example.jpg --picture class=\"hero\" %}"
      )
      expect(result).to include("picture-class:\"hero\"")
    end

    it "includes img-prefixed attributes in tag" do
      result = adaptor.to_imgflow_tag(
        "{% picture example.jpg --img id=\"main\" %}"
      )
      expect(result).to include("img-id:\"main\"")
    end
  end

  describe "#parse_arguments" do
    it "handles single-quoted paths with spaces" do
      args = adaptor.send(:parse_arguments, "'some image.jpg' --alt Text")
      expect(args).to eq(["some image.jpg", "--alt", "Text"])
    end

    it "handles nested double quotes inside single quotes" do
      args = adaptor.send(:parse_arguments, "'it\\'s.jpg' --alt Text")
      expect(args.first).to include("it")
    end

    it "handles empty content" do
      args = adaptor.send(:parse_arguments, "")
      expect(args).to eq([])
    end

    it "handles multiple spaces between arguments" do
      args = adaptor.send(:parse_arguments, "image.jpg    --alt    Text")
      expect(args).to eq(["image.jpg", "--alt", "Text"])
    end
  end

  describe "#parse_element_attribute" do
    it "parses key=value with double quotes" do
      hash = {}
      adaptor.send(:parse_element_attribute, 'class="hero"', hash)
      expect(hash["class"]).to eq("hero")
    end

    it "parses key=value with single quotes" do
      hash = {}
      adaptor.send(:parse_element_attribute, "class='hero'", hash)
      expect(hash["class"]).to eq("hero")
    end

    it "parses key=value without quotes" do
      hash = {}
      adaptor.send(:parse_element_attribute, "data-id=123", hash)
      expect(hash["data-id"]).to eq("123")
    end

    it "parses boolean attribute (key only)" do
      hash = {}
      adaptor.send(:parse_element_attribute, "lazy", hash)
      expect(hash["lazy"]).to be(true)
    end

    it "parses hyphenated key" do
      hash = {}
      adaptor.send(:parse_element_attribute, 'data-src="img.jpg"', hash)
      expect(hash["data-src"]).to eq("img.jpg")
    end
  end

  describe "#formats?" do
    it "returns true when formats: is present" do
      expect(adaptor.send(:formats?, ["image.jpg", "formats:webp,jpg"])).to be true
    end

    it "returns false when formats: is absent" do
      expect(adaptor.send(:formats?, ["image.jpg", "width:800"])).to be false
    end

    it "returns false for empty array" do
      expect(adaptor.send(:formats?, [])).to be false
    end

    it "handles nil entries" do
      expect(adaptor.send(:formats?, [nil, "image.jpg"])).to be false
    end
  end

  describe "#determine_primary_crop" do
    it "prefers mobile crop" do
      crops = {
        "tablet" => { ratio: "4:3" },
        "mobile" => { ratio: "1:1" },
        "desktop" => { ratio: "16:9" }
      }
      result = adaptor.send(:determine_primary_crop, crops)
      expect(result[:ratio]).to eq("1:1")
    end

    it "falls back to tablet when no mobile" do
      crops = { "tablet" => { ratio: "4:3" }, "desktop" => { ratio: "16:9" } }
      result = adaptor.send(:determine_primary_crop, crops)
      expect(result[:ratio]).to eq("4:3")
    end

    it "falls back to default when no mobile or tablet" do
      crops = { "default" => { ratio: "16:9" } }
      result = adaptor.send(:determine_primary_crop, crops)
      expect(result[:ratio]).to eq("16:9")
    end

    it "falls back to first value when no known keys" do
      crops = { "custom" => { ratio: "2:1" } }
      result = adaptor.send(:determine_primary_crop, crops)
      expect(result[:ratio]).to eq("2:1")
    end

    it "returns nil for empty hash" do
      result = adaptor.send(:determine_primary_crop, {})
      expect(result).to be_nil
    end
  end

  describe "#parse_crop" do
    it "parses ratio with keep" do
      result = adaptor.send(:parse_crop, "16:9 entropy")
      expect(result[:ratio]).to eq("16:9")
      expect(result[:keep]).to eq("entropy")
    end

    it "parses ratio with default keep" do
      result = adaptor.send(:parse_crop, "16:9")
      expect(result[:ratio]).to eq("16:9")
      expect(result[:keep]).to eq("center")
    end

    it "returns empty hash for invalid input" do
      result = adaptor.send(:parse_crop, "invalid")
      expect(result).to eq({})
    end
  end

  describe "#default_html_attributes" do
    it "returns hash with all element types" do
      attrs = adaptor.send(:default_html_attributes)
      expect(attrs).to have_key(:img)
      expect(attrs).to have_key(:picture)
      expect(attrs).to have_key(:source)
      expect(attrs).to have_key(:a)
      expect(attrs).to have_key(:parent)
      expect(attrs[:alt]).to be_nil
      expect(attrs[:link]).to be_nil
      expect(attrs[:img]).to eq({})
    end
  end
end
