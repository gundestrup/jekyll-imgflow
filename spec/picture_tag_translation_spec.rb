# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Picture Tag to ImgFlow Translation", :unit do
  let(:test_site_dir) { create_test_dir("picture-tag-translation-test") }
  let(:site) { double("site", config: TEST_CONFIG, source: test_site_dir) }
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:adaptor) { JekyllImgFlow::PictureTagAdaptor.new(site, config) }

  describe "Complete Picture Tag Feature Coverage" do
    it "translates basic Picture Tag syntax" do
      examples = [
        # Basic forms
        ["{% picture example.jpg %}", "example.jpg formats:webp,jpg"],
        ["{% picture my_preset example.jpg %}", "example.jpg preset:my_preset formats:webp,jpg"],

        # Crop ratios
        ["{% picture example.jpg 16:9 %}", "example.jpg ratio:16:9 formats:webp,jpg"],
        ["{% picture example.jpg 1:1 %}", "example.jpg ratio:1:1 formats:webp,jpg"],
        ["{% picture example.jpg 4:3 %}", "example.jpg ratio:4:3 formats:webp,jpg"],

        # Crop ratios with positions
        ["{% picture example.jpg 16:9 center %}",
         "example.jpg ratio:16:9 keep:center formats:webp,jpg"],
        ["{% picture example.jpg 1:1 entropy %}",
         "example.jpg ratio:1:1 keep:entropy formats:webp,jpg"],
        ["{% picture example.jpg 4:3 top %}",
         "example.jpg ratio:4:3 keep:top formats:webp,jpg"],

        # Media queries (art direction)
        ["{% picture example.jpg mobile: example_mobile.jpg 1:1 %}",
         "example.jpg ratio:1:1 keep:center formats:webp,jpg"],
        ["{% picture example.jpg tablet: example_tablet.jpg 4:3 %}",
         "example.jpg ratio:4:3 keep:center formats:webp,jpg"],
        ["{% picture example.jpg mobile: mobile.jpg 1:1 tablet: tablet.jpg 4:3 %}",
         "example.jpg ratio:1:1 keep:center formats:webp,jpg"],

        # Complex combinations
        ["{% picture hero example.jpg 16:9 entropy %}",
         "example.jpg preset:hero ratio:16:9 keep:entropy formats:webp,jpg"],
        ["{% picture thumbnail example.jpg 1:1 center %}",
         "example.jpg preset:thumbnail ratio:1:1 keep:center formats:webp,jpg"],

        # Quoted paths with spaces
        ["{% picture \"some example.jpg\" 16:9 %}", "some example.jpg ratio:16:9 formats:webp,jpg"],

        # Liquid variables
        ["{% picture \"{{ page.image }}\" %}", "{{ page.image }} formats:webp,jpg"],
        ["{% picture hero \"{{ post.image }}\" %}",
         "{{ post.image }} preset:hero formats:webp,jpg"]
      ]

      examples.each do |picture_tag, expected_imgflow|
        translation_result = adaptor.translate_to_imgflow(picture_tag)
        result = translation_result[:markup]
        expect(result).to eq(expected_imgflow),
                          "Failed translation: #{picture_tag} -> #{result} (expected: #{expected_imgflow})"
      end
    end

    it "handles HTML attributes correctly" do
      examples = [
        ["{% picture example.jpg --alt Example %}", "example.jpg formats:webp,jpg"],
        ["{% picture example.jpg --link /example %}", "example.jpg formats:webp,jpg"],
        ["{% picture example.jpg --picture class=\"hero\" %}", "example.jpg formats:webp,jpg"],
        ["{% picture example.jpg --img id=\"main\" %}", "example.jpg formats:webp,jpg"],
        ["{% picture example.jpg --alt Text --link /example %}", "example.jpg formats:webp,jpg"]
      ]

      examples.each do |picture_tag, expected_imgflow|
        translation_result = adaptor.translate_to_imgflow(picture_tag)
        result = translation_result[:markup]
        expect(result).to eq(expected_imgflow),
                          "HTML attributes should be skipped: #{picture_tag} -> #{result}"
      end
    end

    it "handles edge cases gracefully" do
      edge_cases = [
        ["{% picture %}", ""],
        ["{% picture   %}", ""],
        ["{% picture --alt Broken %}", ""],
        ["{% picture nonexistent.jpg %}", "nonexistent.jpg formats:webp,jpg"]
      ]

      edge_cases.each do |picture_tag, expected|
        translation_result = adaptor.translate_to_imgflow(picture_tag)
        result = translation_result[:markup]
        expect(result).to eq(expected),
                          "Edge case failed: #{picture_tag} -> #{result} (expected: #{expected})"
      end
    end
  end

  describe "Integration with ImgFlow Parser" do
    it "produces markup that ImgFlow Parser can handle" do
      picture_tags = [
        "{% picture example.jpg 16:9 %}",
        "{% picture hero example.jpg %}",
        "{% picture example.jpg mobile: mobile.jpg 1:1 %}",
        "{% picture example.jpg 4:3 entropy %}"
      ]

      picture_tags.each do |picture_tag|
        translation_result = adaptor.translate_to_imgflow(picture_tag)
        imgflow_markup = translation_result[:markup]

        # Should be parseable by ImgFlow Parser
        parsed = JekyllImgFlow::Parser.parse(imgflow_markup)

        expect(parsed[:image_path]).not_to be_nil
        expect(parsed[:operations]).to be_an(Array)
        expect(parsed[:error]).to be_nil
      end
    end

    it "handles complex real-world examples" do
      complex_examples = [
        # From Picture Tag documentation
        "{% picture hero example.jpg 16:9 entropy tablet: example2.jpg 3:2 mobile: example3.jpg 1:1 --alt Happy Puppy --picture class=\"hero\" --link / %}",

        # Multi-device art direction
        "{% picture featured.jpg mobile: featured_mobile.jpg 1:1 tablet: featured_tablet.jpg 4:3 desktop: featured_desktop.jpg 16:9 %}",

        # Preset with crop
        "{% picture thumbnail avatar.jpg 1:1 center --alt Profile Picture %}"
      ]

      complex_examples.each do |picture_tag|
        translation_result = adaptor.translate_to_imgflow(picture_tag)
        imgflow_markup = translation_result[:markup]

        # Should be parseable by ImgFlow Parser
        parsed = JekyllImgFlow::Parser.parse(imgflow_markup)

        expect(parsed[:image_path]).not_to be_nil
        expect(parsed[:operations]).to be_an(Array)
        expect(parsed[:error]).to be_nil
      end
    end
  end

  describe "Migration Scenarios" do
    it "supports gradual migration from Picture Tag to ImgFlow" do
      # Common Picture Tag patterns that users would want to migrate
      migration_examples = [
        # Simple hero images
        "{% picture hero banner.jpg %}",

        # Thumbnail crops
        "{% picture thumbnail profile.jpg 1:1 %}",

        # Responsive art direction
        "{% picture article photo.jpg mobile: photo_mobile.jpg 4:3 %}",

        # Complex layouts
        "{% picture gallery featured.jpg 16:9 entropy %}"
      ]

      migration_examples.each do |picture_tag|
        translation_result = adaptor.translate_to_imgflow(picture_tag)
        imgflow_markup = translation_result[:markup]

        # Should produce valid ImgFlow markup
        expect(imgflow_markup).not_to be_empty
        expect(imgflow_markup).to include("formats:")

        # Should be parseable
        parsed = JekyllImgFlow::Parser.parse(imgflow_markup)
        expect(parsed[:error]).to be_nil
      end
    end
  end
end
