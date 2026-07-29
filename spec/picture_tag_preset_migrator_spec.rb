# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::PictureTagPresetMigrator, :unit do
  let(:test_site_dir) { create_test_dir("preset-migration-test") }
  let(:migrator) { described_class.new(test_site_dir) }

  before do
    # Create test Picture Tag config
    picture_config_dir = File.join(test_site_dir, "_data")
    FileUtils.mkdir_p(picture_config_dir)

    File.write(File.join(picture_config_dir, "picture.yml"), <<~YAML)
      presets:
        # Multi-width preset (most common Picture Tag pattern)
        default:
          formats: [webp, original]
          widths: [200, 400, 800, 1200, 1600]
          sizes:
            mobile: calc(100vw - 16px)
          dimension_attributes: true
      #{'  '}
        # Pixel-ratio preset (for thumbnails, avatars)
        thumbnail:
          crop: "1:1"
          base_width: 150
          pixel_ratios: [1, 1.5, 2]
          fallback_width: 150
          formats: [webp, original]
          attributes:
            picture: 'class="thumbnail"'
      #{'  '}
        # Simple width-based preset
        hero:
          formats: [avif, webp, original]
          widths: [800, 1200, 1600]
          quality: 90
          dimension_attributes: true
      #{'  '}
        # Avatar with crop
        avatar:
          crop: "1:1"
          base_width: 100
          pixel_ratios: [1, 1.5, 2]
          fallback_width: 100
          formats: [webp, original]
      #{'  '}
        # Direct URL preset (special case)
        direct:
          markup: direct_url
          fallback_format: webp
          fallback_width: 600
      #{'  '}
        # Lazy loading preset
        lazy:
          markup: data_auto
          formats: [webp, original]
          noscript: true
          attributes:
            parent: class="lazy"
      #{'  '}
        # Empty preset (no convertible operations)
        empty:
          description: "No operations"
          markup: auto
    YAML
  end

  describe "#preview_migration" do
    it "identifies all Picture Tag presets" do
      results = migrator.preview_migration

      expect(results[:found]).to contain_exactly(
        "default", "thumbnail", "hero", "avatar", "direct", "lazy", "empty"
      )
    end

    it "identifies convertible presets" do
      results = migrator.preview_migration

      expect(results[:convertible].length).to eq(5)
      convertible_names = results[:convertible].map { |p| p[:name] }
      expect(convertible_names).to contain_exactly("default", "thumbnail", "hero", "avatar", "lazy")
    end

    it "identifies non-convertible presets" do
      results = migrator.preview_migration

      expect(results[:non_convertible].length).to eq(2)
      non_convertible_names = results[:non_convertible].map { |p| p[:name] }
      expect(non_convertible_names).to contain_exactly("direct", "empty")
    end

    it "generates correct ImgFlow preset preview for multi-width preset" do
      results = migrator.preview_migration

      default_preset = results[:convertible].find { |p| p[:name] == "default" }
      expect(default_preset[:preview]["name"]).to eq("default")
      expect(default_preset[:preview]["operations"]).to include(
        { "resize" => { "width" => 1600 } }, # Max width from widths array
        { "format" => { "formats" => %w[webp jpg] } } # 'original' converted to 'jpg'
      )
    end

    it "generates correct ImgFlow preset preview for pixel-ratio preset" do
      results = migrator.preview_migration

      thumbnail_preset = results[:convertible].find { |p| p[:name] == "thumbnail" }
      expect(thumbnail_preset[:preview]["name"]).to eq("thumbnail")
      expect(thumbnail_preset[:preview]["operations"]).to include(
        { "resize" => { "width" => 150 } }, # base_width
        { "crop" => { "ratio" => "1:1" } },
        { "format" => { "formats" => %w[webp jpg] } }
      )
    end
  end

  describe "#migrate_presets" do
    it "creates ImgFlow preset files" do
      results = migrator.migrate_presets

      expect(results[:migrated]).to contain_exactly(
        "default", "thumbnail", "hero", "avatar", "lazy"
      )

      # Check that files were created
      expect(File.exist?(File.join(test_site_dir, "_data", "imgflow", "presets",
                                   "default.yml"))).to be true
      expect(File.exist?(File.join(test_site_dir, "_data", "imgflow", "presets",
                                   "thumbnail.yml"))).to be true
      expect(File.exist?(File.join(test_site_dir, "_data", "imgflow", "presets",
                                   "hero.yml"))).to be true
      expect(File.exist?(File.join(test_site_dir, "_data", "imgflow", "presets",
                                   "avatar.yml"))).to be true
      expect(File.exist?(File.join(test_site_dir, "_data", "imgflow", "presets",
                                   "lazy.yml"))).to be true
    end

    it "skips non-convertible presets" do
      results = migrator.migrate_presets

      expect(results[:skipped].length).to eq(2)
      skipped_names = results[:skipped].map { |s| s[:name] }
      expect(skipped_names).to contain_exactly("direct", "empty")
    end

    it "generates correct YAML content for multi-width preset" do
      migrator.migrate_presets

      # Check default preset content
      default_file = File.join(test_site_dir, "_data", "imgflow", "presets", "default.yml")
      default_content = YAML.load_file(default_file)

      expect(default_content["name"]).to eq("default")
      expect(default_content["operations"]).to include(
        { "resize" => { "width" => 1600 } }, # Max width from widths array
        { "format" => { "formats" => %w[webp jpg] } } # 'original' converted to 'jpg'
      )

      # Check metadata is preserved
      expect(default_content["picture_tag_metadata"]["original_widths"]).to eq([200, 400, 800,
                                                                                1200, 1600])
      expect(default_content["picture_tag_metadata"]["dimension_attributes"]).to be true
    end

    it "generates correct YAML content for pixel-ratio preset" do
      migrator.migrate_presets

      thumbnail_file = File.join(test_site_dir, "_data", "imgflow", "presets", "thumbnail.yml")
      thumbnail_content = YAML.load_file(thumbnail_file)

      expect(thumbnail_content["operations"]).to include(
        { "resize" => { "width" => 150 } }, # base_width
        { "crop" => { "ratio" => "1:1" } },
        { "format" => { "formats" => %w[webp jpg] } }
      )

      # Check metadata
      expect(thumbnail_content["picture_tag_metadata"]["original_base_width"]).to eq(150)
      expect(thumbnail_content["picture_tag_metadata"]["original_pixel_ratios"]).to eq([1, 1.5, 2])
    end

    it "generates meaningful descriptions for Picture Tag presets" do
      migrator.migrate_presets

      default_file = File.join(test_site_dir, "_data", "imgflow", "presets", "default.yml")
      default_content = YAML.load_file(default_file)

      expect(default_content["description"]).to include("Migrated from Picture Tag preset 'default'")
      expect(default_content["description"]).to include("widths: 200,400,800,1200,1600")
      expect(default_content["description"]).to include("using max width: 1600")
      expect(default_content["description"]).to include("formats: webp,original")
    end
  end

  describe "edge cases" do
    it "handles missing picture config file" do
      # Remove the config file
      FileUtils.rm_f(File.join(test_site_dir, "_data", "picture.yml"))

      results = migrator.migrate_presets
      expect(results[:migrated]).to be_empty
      expect(results[:skipped]).to be_empty
      expect(results[:errors]).to be_empty
    end

    it "handles empty picture config" do
      File.write(File.join(test_site_dir, "_data", "picture.yml"), "{}")

      results = migrator.migrate_presets
      expect(results[:migrated]).to be_empty
      expect(results[:skipped]).to be_empty
      expect(results[:errors]).to be_empty
    end

    it "handles picture config without presets" do
      File.write(File.join(test_site_dir, "_data", "picture.yml"), <<~YAML)
        some_other_config: value
      YAML

      results = migrator.migrate_presets
      expect(results[:migrated]).to be_empty
      expect(results[:skipped]).to be_empty
      expect(results[:errors]).to be_empty
    end

    it "creates presets directory if it doesn't exist" do
      # Remove the presets directory
      FileUtils.rm_rf(File.join(test_site_dir, "_data", "imgflow"))

      migrator.migrate_presets

      expect(Dir.exist?(File.join(test_site_dir, "_data", "imgflow", "presets"))).to be true
    end
  end

  describe "field mapping" do
    it "maps Picture Tag fields to ImgFlow operations correctly" do
      # Test specific field mappings
      File.write(File.join(test_site_dir, "_data", "picture.yml"), <<~YAML)
        presets:
          field_test:
            width: 800
            height: 600
            quality: 85
            formats: [webp, jpg]
            aspect_ratio: "4:3"
            gravity: entropy
            ratio: "16:9"  # Should take precedence over aspect_ratio
            position: top   # Should take precedence over gravity
      YAML

      migrator.migrate_presets

      test_file = File.join(test_site_dir, "_data", "imgflow", "presets", "field_test.yml")
      test_content = YAML.load_file(test_file)

      operations = test_content["operations"]

      # Check resize operation
      resize_op = operations.find { |op| op["resize"] }
      expect(resize_op["resize"]).to eq({ "width" => 800, "height" => 600 })

      # Check quality operation
      quality_op = operations.find { |op| op["quality"] }
      expect(quality_op["quality"]).to eq({ "quality" => 85 })

      # Check format operation
      format_op = operations.find { |op| op["format"] }
      expect(format_op["format"]).to eq({ "formats" => %w[webp jpg] })

      # Check crop operation (ratio should take precedence over aspect_ratio)
      crop_op = operations.find { |op| op["crop"] }
      expect(crop_op["crop"]).to eq({ "ratio" => "16:9", "position" => "top" })
    end
  end
end
