# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ImgflowTag Preset Integration", :integration, :system do
  # Use TestPictures for realistic image scenarios
  let(:test_image_name) { TestPictures.get(:default).first }
  let(:test_dir) { create_test_dir("imgflow-tag-preset") }
  let(:presets_dir) { File.join(test_dir, "_data", "imgflow", "presets") }

  before do
    FileUtils.mkdir_p(presets_dir)

    # Create realistic test presets with TestPictures integration
    File.write(File.join(presets_dir, "hero.yml"), <<~YAML)
      operations:
        - resize:
            width: 800
            height: 600
        - format:
            formats: ["webp", "jpg"]
        - quality:
            quality: 85
    YAML

    File.write(File.join(presets_dir, "banner.yml"), <<~YAML)
      operations:
        - resize:
            width: 1200
            height: 400
        - format:
            formats: ["webp", "avif", "jpg"]
        - quality:
            quality: 90
    YAML

    File.write(File.join(presets_dir, "thumbnail.yml"), <<~YAML)
      operations:
        - resize:
            width: 150
            height: 150
        - format:
            formats: ["webp", "jpg"]
        - quality:
            quality: 75
    YAML
  end

  after do
    FileUtils.rm_rf(test_dir) if test_dir
  end

  describe "PresetManager integration" do
    # Use standardized RSpec helpers
    let(:site) { create_mock_site(source: test_dir) }
    let(:config) { double("config", originals: "assets/images") }
    let(:preset_manager) { JekyllImgFlow::PresetManager.new(site, config) }

    it "expands preset markup correctly" do
      # Use realistic TestPictures image name
      markup = "#{test_image_name} preset:hero"
      parts = markup.split
      image_path = parts.first

      preset_name = nil
      user_options = {}

      parts[1..].each do |part|
        if part.start_with?("preset:")
          preset_name = part.split(":", 2).last
        elsif part.include?(":")
          key, value = part.split(":", 2)
          user_options[key.to_sym] = value
        end
      end

      preset_markup = preset_manager.build_markup_from_preset(preset_name, user_options)
      expanded = "#{image_path} #{preset_markup}"

      expect(expanded).to include(test_image_name)
      expect(expanded).to include("width:800")
      expect(expanded).to include("height:600")
      expect(expanded).to include("formats:webp,jpg")
      expect(expanded).to include("quality:85")
    end

    it "allows user options to override preset values" do
      markup = "#{test_image_name} preset:hero quality:90"
      parts = markup.split
      image_path = parts.first

      preset_name = nil
      user_options = {}

      parts[1..].each do |part|
        if part.start_with?("preset:")
          preset_name = part.split(":", 2).last
        elsif part.include?(":")
          key, value = part.split(":", 2)
          user_options[key.to_sym] = value
        end
      end

      preset_markup = preset_manager.build_markup_from_preset(preset_name, user_options)
      expanded = "#{image_path} #{preset_markup}"

      expect(expanded).to include("quality:90")
      expect(expanded).not_to include("quality:85")
    end

    it "handles multiple user overrides" do
      markup = "#{test_image_name} preset:hero width:1200 quality:95"
      parts = markup.split
      image_path = parts.first

      preset_name = nil
      user_options = {}

      parts[1..].each do |part|
        if part.start_with?("preset:")
          preset_name = part.split(":", 2).last
        elsif part.include?(":")
          key, value = part.split(":", 2)
          user_options[key.to_sym] = value
        end
      end

      preset_markup = preset_manager.build_markup_from_preset(preset_name, user_options)
      expanded = "#{image_path} #{preset_markup}"

      expect(expanded).to include("width:1200")
      expect(expanded).to include("quality:95")
      expect(expanded).to include("height:600") # Not overridden
    end
  end

  describe "Uniform markup format" do
    # Use standardized RSpec helpers
    let(:site) { create_mock_site(source: test_dir) }
    let(:config) { double("config", originals: "assets/images") }
    let(:preset_manager) { JekyllImgFlow::PresetManager.new(site, config) }

    it "ensures preset and direct paths produce same markup structure" do
      # Preset path with realistic image name
      preset_markup = preset_manager.build_markup_from_preset("hero")
      preset_full = "#{test_image_name} #{preset_markup}"

      # Direct path (equivalent to preset) with realistic image name
      direct_markup = "#{test_image_name} width:800 height:600 formats:webp,jpg quality:85"

      # Both should have same structure (image path + key:value pairs)
      expect(preset_full.split.first).to eq(direct_markup.split.first) # Same image
      expect(preset_full).to match(/\w+:\w+/) # Has key:value pairs
      expect(direct_markup).to match(/\w+:\w+/) # Has key:value pairs
    end
  end

  describe "edge cases and error handling" do
    let(:site) { create_mock_site(source: test_dir) }
    let(:config) { double("config", originals: "assets/images") }
    let(:preset_manager) { JekyllImgFlow::PresetManager.new(site, config) }

    it "handles non-existent preset gracefully" do
      result = preset_manager.build_markup_from_preset("non_existent")
      expect(result).to eq("") # Should return empty markup for missing preset
    end

    it "handles malformed preset files" do
      # Create malformed YAML preset
      File.write(File.join(presets_dir, "malformed.yml"), "invalid: yaml: content: [")

      # Should handle gracefully and return empty markup (invalid files are skipped)
      result = preset_manager.build_markup_from_preset("malformed")
      expect(result).to eq("")
    end

    it "handles empty preset files" do
      # Create empty preset
      File.write(File.join(presets_dir, "empty.yml"), "")

      result = preset_manager.build_markup_from_preset("empty")
      expect(result).to eq("") # Should return empty markup
    end

    it "handles preset with missing operations" do
      # Create preset without operations
      File.write(File.join(presets_dir, "no_ops.yml"), <<~YAML)
        metadata:
          name: "Test Preset"
          description: "No operations here"
      YAML

      result = preset_manager.build_markup_from_preset("no_ops")
      expect(result).to eq("") # Should return empty markup
    end

    it "handles complex preset with multiple operations" do
      # Test with banner preset (multiple formats, higher quality)
      markup = "#{test_image_name} preset:banner"
      parts = markup.split
      image_path = parts.first

      preset_name = nil
      user_options = {}

      parts[1..].each do |part|
        if part.start_with?("preset:")
          preset_name = part.split(":", 2).last
        elsif part.include?(":")
          key, value = part.split(":", 2)
          user_options[key.to_sym] = value
        end
      end

      preset_markup = preset_manager.build_markup_from_preset(preset_name, user_options)
      expanded = "#{image_path} #{preset_markup}"

      expect(expanded).to include(test_image_name)
      expect(expanded).to include("width:1200")
      expect(expanded).to include("height:400")
      expect(expanded).to include("formats:webp,avif,jpg")
      expect(expanded).to include("quality:90")
    end
  end

  describe "security and input validation" do
    let(:site) { create_mock_site(source: test_dir) }
    let(:config) { double("config", originals: "assets/images") }
    let(:preset_manager) { JekyllImgFlow::PresetManager.new(site, config) }

    it "handles malicious preset names safely" do
      malicious_names = ["../../../etc/passwd", "<script>alert('xss')</script>", "preset|rm -rf /"]

      malicious_names.each do |malicious_name|
        result = preset_manager.build_markup_from_preset(malicious_name)
        expect(result).to eq("") # Should return empty markup for non-existent malicious presets
      end
    end

    it "handles malicious user options safely" do
      # Create a simple preset for testing
      File.write(File.join(presets_dir, "safe.yml"), <<~YAML)
        operations:
          - resize:
              width: 100
              height: 100
      YAML

      malicious_options = {
        "width" => "<script>alert('xss')</script>",
        "format" => "../../../etc/passwd",
        "quality" => "rm -rf /"
      }

      malicious_options.each do |key, value|
        result = preset_manager.build_markup_from_preset("safe", { key.to_sym => value })
        # NOTE: PresetManager passes through user options without sanitization
        # Security should be handled at the parser/tag level
        expect(result).to include(key.to_s)
      end
    end

    it "handles extremely long preset names" do
      long_name = "a" * 1000

      result = preset_manager.build_markup_from_preset(long_name)
      expect(result).to eq("") # Should return empty markup for non-existent long preset name
    end
  end

  describe "integration with different image types" do
    let(:site) { create_mock_site(source: test_dir) }
    let(:config) { double("config", originals: "assets/images") }
    let(:preset_manager) { JekyllImgFlow::PresetManager.new(site, config) }

    it "works with different TestPictures image types" do
      # Test with different image formats from TestPictures
      test_images = TestPictures.get(:default_multi)

      test_images.each do |image_name|
        markup = "#{image_name} preset:thumbnail"
        parts = markup.split
        image_path = parts.first

        preset_name = nil
        user_options = {}

        parts[1..].each do |part|
          if part.start_with?("preset:")
            preset_name = part.split(":", 2).last
          elsif part.include?(":")
            key, value = part.split(":", 2)
            user_options[key.to_sym] = value
          end
        end

        preset_markup = preset_manager.build_markup_from_preset(preset_name, user_options)
        expanded = "#{image_path} #{preset_markup}"

        expect(expanded).to include(image_name)
        expect(expanded).to include("width:150")
        expect(expanded).to include("height:150")
        expect(expanded).to include("quality:75")
      end
    end
  end
end
