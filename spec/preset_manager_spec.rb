# frozen_string_literal: true

require "rspec"
require "tempfile"
require "fileutils"
require "spec_helper"

RSpec.describe JekyllImgFlow::PresetManager, :unit do
  let(:test_dir) { create_test_dir("preset-manager-new") }
  let(:presets_dir) { File.join(test_dir, "_data", "imgflow", "presets") }
  let(:site) { double("site", source: test_dir) }
  let(:config) { double("config", originals: "assets/images") }
  let(:preset_manager) { described_class.new(site, config) }

  before do
    FileUtils.mkdir_p(presets_dir)
  end

  after do
    FileUtils.rm_rf(test_dir) if test_dir
  end

  describe "New Architecture: YAML to tags:value translation" do
    context "Simple preset" do
      before do
        File.write(File.join(presets_dir, "simple.yml"), <<~YAML)
          operations:
            - resize:
                width: 400
                height: 300
            - format:
                formats: ["webp", "jpg"]
            - quality:
                quality: 85
        YAML
      end

      it "converts YAML to tags:value markup format" do
        markup = preset_manager.build_markup_from_preset("simple")

        expect(markup).to include("width:400")
        expect(markup).to include("height:300")
        expect(markup).to include("formats:webp,jpg")
        expect(markup).to include("quality:85")
      end

      it "returns markup that can be parsed by Parser" do
        markup = preset_manager.build_markup_from_preset("simple")

        # Markup should be in key:value format separated by spaces
        expect(markup).to match(/\w+:\w+/)
        expect(markup.split.length).to be >= 4
      end
    end

    context "Preset with user overrides" do
      before do
        File.write(File.join(presets_dir, "hero.yml"), <<~YAML)
          operations:
            - resize:
                width: 800
                height: 600
            - format:
                formats: ["avif", "webp", "jpg"]
            - quality:
                quality: 85
        YAML
      end

      it "allows user options to override preset values" do
        # User provides quality:90, should override preset quality:85
        markup = preset_manager.build_markup_from_preset("hero", { quality: 90 })

        expect(markup).to include("quality:90")
        expect(markup).not_to include("quality:85")
      end

      it "allows multiple user overrides" do
        # User overrides both width and quality
        markup = preset_manager.build_markup_from_preset("hero", { width: 1200, quality: 95 })

        expect(markup).to include("width:1200")
        expect(markup).to include("quality:95")
        expect(markup).to include("height:600") # Not overridden
      end

      it "preserves non-overridden preset values" do
        # User only overrides quality
        markup = preset_manager.build_markup_from_preset("hero", { quality: 90 })

        expect(markup).to include("width:800")
        expect(markup).to include("height:600")
        expect(markup).to include("formats:avif,webp,jpg")
      end
    end

    context "Complex preset with multiple operations" do
      before do
        File.write(File.join(presets_dir, "complex.yml"), <<~YAML)
          operations:
            - crop:
                ratio: "16:9"
            - resize:
                width: 1920
                height: 1080
            - format:
                formats: ["avif", "webp", "jpg"]
            - quality:
                quality: 90
            - optimize:
                level: high
        YAML
      end

      it "converts all operation types to tags:value format" do
        markup = preset_manager.build_markup_from_preset("complex")

        expect(markup).to include("ratio:16:9")
        expect(markup).to include("width:1920")
        expect(markup).to include("height:1080")
        expect(markup).to include("formats:avif,webp,jpg")
        expect(markup).to include("quality:90")
        expect(markup).to include("level:high")
      end
    end

    context "Preset with array values" do
      before do
        File.write(File.join(presets_dir, "formats.yml"), <<~YAML)
          operations:
            - format:
                formats: ["avif", "webp", "jpg", "png"]
        YAML
      end

      it "converts array values to comma-separated strings" do
        markup = preset_manager.build_markup_from_preset("formats")

        expect(markup).to include("formats:avif,webp,jpg,png")
      end
    end

    context "Non-existent preset" do
      it "returns empty string for non-existent preset" do
        markup = preset_manager.build_markup_from_preset("nonexistent")

        expect(markup).to eq("")
      end
    end
  end

  describe "Preset loading" do
    it "loads presets from _data/imgflow/presets/" do
      File.write(File.join(presets_dir, "test.yml"), <<~YAML)
        operations:
          - resize:
              width: 100
      YAML

      expect(preset_manager.preset_exists?("test")).to be true
    end

    it "returns available preset names" do
      File.write(File.join(presets_dir, "hero.yml"), "operations: []")
      File.write(File.join(presets_dir, "thumbnail.yml"), "operations: []")

      presets = preset_manager.available_presets
      expect(presets).to include("hero")
      expect(presets).to include("thumbnail")
    end
  end

  describe "Preset expansion" do
    before do
      File.write(File.join(presets_dir, "test.yml"), <<~YAML)
        operations:
          - resize:
              width: 400
              height: 300
          - format:
              formats: ["webp", "jpg"]
      YAML
    end

    it "converts YAML preset to tags:value markup" do
      markup = preset_manager.build_markup_from_preset("test")

      expect(markup).to include("width:400")
      expect(markup).to include("height:300")
      expect(markup).to include("formats:webp,jpg")
    end
  end

  describe "Additional operation type coverage" do
    it "handles single format param (not formats array)" do
      File.write(File.join(presets_dir, "single_format.yml"), <<~YAML)
        operations:
          - format:
              format: "webp"
      YAML

      markup = preset_manager.build_markup_from_preset("single_format")
      expect(markup).to include("format:webp")
    end

    it "handles opacity operation" do
      File.write(File.join(presets_dir, "opacity.yml"), <<~YAML)
        operations:
          - opacity:
              opacity: 0.5
      YAML

      markup = preset_manager.build_markup_from_preset("opacity")
      expect(markup).to include("opacity:0.5")
    end

    it "handles unknown operation types generically" do
      File.write(File.join(presets_dir, "unknown.yml"), <<~YAML)
        operations:
          - custom_op:
              blur: 5
              sharpen: 2
      YAML

      markup = preset_manager.build_markup_from_preset("unknown")
      expect(markup).to include("blur:5")
      expect(markup).to include("sharpen:2")
    end

    it "handles unknown operation with array value" do
      File.write(File.join(presets_dir, "array_unknown.yml"), <<~YAML)
        operations:
          - custom_op:
              filters: ["blur", "sharpen"]
      YAML

      markup = preset_manager.build_markup_from_preset("array_unknown")
      expect(markup).to include("filters:blur,sharpen")
    end
  end
end
