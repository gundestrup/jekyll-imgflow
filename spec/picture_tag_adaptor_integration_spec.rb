# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Picture Tag Adaptor Integration", :integration, :system do
  before(:all) do
    # Create test site once for all tests
    @test_site_dir = create_test_dir("picture-tag-adaptor-test")
    create_test_jekyll_site(@test_site_dir, :imgflow_only,
                            { test_images: TestPictures.get(:default) })

    # Create picture tag config for testing
    picture_config_dir = File.join(@test_site_dir, "_data")
    FileUtils.mkdir_p(picture_config_dir)

    File.write(File.join(picture_config_dir, "picture.yml"), <<~YAML)
      presets:
        hero:
          width: 1200
          height: 600
          quality: 90
          formats: [avif, webp, jpg]
        thumbnail:
          width: 150
          height: 150
          quality: 75
          formats: [webp, jpg]
    YAML

    # Create ImgFlow presets
    presets_dir = File.join(@test_site_dir, "_data", "imgflow", "presets")
    FileUtils.mkdir_p(presets_dir)

    File.write(File.join(presets_dir, "imgflow_hero.yml"), <<~YAML)
      operations:
        - resize:
            width: 1200
            height: 600
        - quality:
            quality: 90
        - format:
            formats: ["avif", "webp", "jpg"]
    YAML

    # Copy test image to root for easier access in tests
    test_image_name = TestPictures.get(:default).find { |img| img.include?("mars-crater") }
    source_image = fixture_image_path(test_image_name)
    target_image = File.join(@test_site_dir, "test.jpg")
    FileUtils.cp(source_image, target_image)
  end

  let(:test_site_dir) { @test_site_dir }
  let(:site) { create_mock_site(source: test_site_dir) }
  let(:components) { create_imgflow_components(site) }
  let(:config) { components[:config] }
  let(:adaptor) { JekyllImgFlow::PictureTagAdaptor.new(site, config) }
  let(:test_image_name) { TestPictures.get(:default).find { |img| img.include?("mars-crater") } }

  describe "end-to-end translation" do
    it "translates Picture Tag to ImgFlow and processes successfully" do
      # Picture Tag markup
      picture_markup = "{% picture hero test.jpg %}"

      # Translate to ImgFlow markup
      translation_result = adaptor.translate_to_imgflow(picture_markup)
      imgflow_markup = translation_result[:markup]

      expect(imgflow_markup).to include("test.jpg")
      expect(imgflow_markup).to include("preset:hero")
      expect(imgflow_markup).to include("formats:webp,jpg")

      # Test that the translated markup can be processed by ImgFlow
      parsed = JekyllImgFlow::Parser.parse(imgflow_markup)
      expect(parsed[:image_path]).to eq("test.jpg")
      expect(parsed[:operations].length).to be >= 1
      expect(parsed[:preset]).to eq("hero")
    end

    it "translates Picture Tag with crop to ImgFlow" do
      picture_markup = "{% picture test.jpg 16:9 %}"

      translation_result = adaptor.translate_to_imgflow(picture_markup)
      imgflow_markup = translation_result[:markup]

      expect(imgflow_markup).to include("test.jpg")
      expect(imgflow_markup).to include("ratio:16:9")
      expect(imgflow_markup).to include("formats:webp,jpg")

      # Test parsing
      parsed = JekyllImgFlow::Parser.parse(imgflow_markup)
      expect(parsed[:image_path]).to eq("test.jpg")
      expect(parsed[:operations].length).to be >= 2
    end

    it "translates Picture Tag with media queries to ImgFlow" do
      picture_markup = "{% picture test.jpg mobile: test_mobile.jpg 1:1 tablet: test_tablet.jpg 4:3 %}"

      translation_result = adaptor.translate_to_imgflow(picture_markup)
      imgflow_markup = translation_result[:markup]

      expect(imgflow_markup).to include("test.jpg")
      expect(imgflow_markup).to include("ratio:1:1") # Mobile takes priority
      expect(imgflow_markup).to include("formats:webp,jpg")

      # Test parsing
      parsed = JekyllImgFlow::Parser.parse(imgflow_markup)
      expect(parsed[:image_path]).to eq("test.jpg")
      expect(parsed[:operations].length).to be >= 2
    end

    it "translates Picture Tag with ImgFlow preset" do
      picture_markup = "{% picture imgflow_hero test.jpg %}"

      translation_result = adaptor.translate_to_imgflow(picture_markup)
      imgflow_markup = translation_result[:markup]

      expect(imgflow_markup).to include("test.jpg")
      expect(imgflow_markup).to include("preset:imgflow_hero")

      # Test parsing
      parsed = JekyllImgFlow::Parser.parse(imgflow_markup)
      expect(parsed[:image_path]).to eq("test.jpg")
      expect(parsed[:operations].length).to be >= 1
    end
  end

  describe "real-world examples" do
    it "handles hero image example" do
      picture_markup = "{% picture hero banner.jpg 16:9 entropy --alt Hero Banner --picture class=\"hero-image\" %}"

      translation_result = adaptor.translate_to_imgflow(picture_markup)
      imgflow_markup = translation_result[:markup]

      expect(imgflow_markup).to include("banner.jpg")
      expect(imgflow_markup).to include("preset:hero")
      expect(imgflow_markup).to include("ratio:16:9")
      expect(imgflow_markup).to include("keep:entropy")
      expect(imgflow_markup).to include("formats:webp,jpg")

      # Test parsing
      parsed = JekyllImgFlow::Parser.parse(imgflow_markup)
      expect(parsed[:image_path]).to eq("banner.jpg")
    end

    it "handles thumbnail example" do
      picture_markup = "{% picture thumbnail profile.jpg 1:1 center --alt Profile Picture %}"

      translation_result = adaptor.translate_to_imgflow(picture_markup)
      imgflow_markup = translation_result[:markup]

      expect(imgflow_markup).to include("profile.jpg")
      expect(imgflow_markup).to include("preset:thumbnail")
      expect(imgflow_markup).to include("ratio:1:1")
      expect(imgflow_markup).to include("keep:center")
      expect(imgflow_markup).to include("formats:webp,jpg")

      # Test parsing
      parsed = JekyllImgFlow::Parser.parse(imgflow_markup)
      expect(parsed[:image_path]).to eq("profile.jpg")
    end

    it "handles complex responsive example" do
      picture_markup = <<~MARKUP
        {% picture hero featured.jpg 16:9 entropy tablet: featured_tablet.jpg 3:2 mobile: featured_mobile.jpg 1:1 --alt Featured Image --picture class="featured" --link /featured %}
      MARKUP

      translation_result = adaptor.translate_to_imgflow(picture_markup)
      imgflow_markup = translation_result[:markup]

      expect(imgflow_markup).to include("featured.jpg")
      expect(imgflow_markup).to include("preset:hero")
      expect(imgflow_markup).to include("ratio:16:9")
      expect(imgflow_markup).to include("keep:entropy")
      expect(imgflow_markup).to include("formats:webp,jpg")

      # Test parsing
      parsed = JekyllImgFlow::Parser.parse(imgflow_markup)
      expect(parsed[:image_path]).to eq("featured.jpg")
    end
  end

  describe "migration scenarios" do
    it "supports gradual migration from Picture Tag to ImgFlow" do
      # Original Picture Tag syntax
      original_picture_tags = [
        "{% picture hero banner.jpg %}",
        "{% picture thumbnail avatar.jpg 1:1 %}",
        "{% picture gallery photo.jpg mobile: photo_mobile.jpg 1:1 %}",
        "{% picture content image.jpg --alt Content Image %}"
      ]

      # Translate all to ImgFlow
      translated_tags = original_picture_tags.map do |tag|
        translation_result = adaptor.translate_to_imgflow(tag)
        translation_result[:markup]
      end

      # All should be valid ImgFlow markup
      translated_tags.each do |imgflow_tag|
        expect(imgflow_tag).not_to be_empty
        expect(imgflow_tag).to include("formats:")

        # Should be parseable by ImgFlow
        parsed = JekyllImgFlow::Parser.parse(imgflow_tag)
        expect(parsed[:image_path]).not_to be_empty
        expect(parsed[:operations]).to be_an(Array)
      end
    end

    it "maintains compatibility with ImgFlow presets" do
      # Mixed usage: some Picture Tag presets, some ImgFlow presets
      mixed_tags = [
        "{% picture hero image.jpg %}", # Picture Tag preset
        "{% picture imgflow_hero image.jpg %}", # ImgFlow preset
        "{% picture thumbnail image.jpg %}", # Picture Tag preset
        "{% picture image.jpg 16:9 %}" # Direct ImgFlow syntax
      ]

      mixed_tags.each do |tag|
        translation_result = adaptor.translate_to_imgflow(tag)
        imgflow_tag = translation_result[:markup]
        expect(imgflow_tag).not_to be_empty

        # Should be parseable
        parsed = JekyllImgFlow::Parser.parse(imgflow_tag)
        expect(parsed[:image_path]).not_to be_empty
      end
    end
  end

  describe "error handling" do
    it "handles missing Picture Tag config gracefully" do
      # Remove picture config
      FileUtils.rm_f(File.join(test_site_dir, "_data", "picture.yml"))

      picture_markup = "{% picture unknown_preset test.jpg %}"
      translation_result = adaptor.translate_to_imgflow(picture_markup)
      imgflow_markup = translation_result[:markup]

      # Should fall back to basic ImgFlow syntax
      expect(imgflow_markup).to include("test.jpg")
      expect(imgflow_markup).to include("formats:webp,jpg")
    end

    it "handles malformed Picture Tag syntax" do
      malformed_tags = [
        "{% picture %}",
        "{% picture --alt Broken %}",
        "{% picture %}"
      ]

      malformed_tags.each do |tag|
        translation_result = adaptor.translate_to_imgflow(tag)
        imgflow_tag = translation_result[:markup]
        expect(imgflow_tag).to eq("")
      end
    end
  end
end
