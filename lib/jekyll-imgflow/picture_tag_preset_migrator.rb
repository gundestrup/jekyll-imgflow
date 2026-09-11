# frozen_string_literal: true

require "yaml"
require "fileutils"

module JekyllImgFlow
  # Migrates Jekyll Picture Tag presets to ImgFlow YAML preset format
  class PictureTagPresetMigrator
    PICTURE_TAG_CONFIG = "_data/picture.yml"
    IMGFLOW_PRESETS_DIR = "_data/imgflow/presets"

    def initialize(site_source)
      @site_source = site_source
      @picture_config_path = File.join(site_source, PICTURE_TAG_CONFIG)
      @imgflow_presets_dir = File.join(site_source, IMGFLOW_PRESETS_DIR)
    end

    # Migrate all Picture Tag presets to ImgFlow format
    # @return [Hash] Migration results
    def migrate_presets
      results = {
        migrated: [],
        skipped: [],
        errors: []
      }

      return results unless File.exist?(@picture_config_path)

      picture_config = load_picture_config
      return results unless picture_config["presets"]

      # Ensure ImgFlow presets directory exists
      FileUtils.mkdir_p(@imgflow_presets_dir)

      picture_config["presets"].each do |preset_name, preset_data|
        imgflow_preset = convert_preset_to_imgflow(preset_name, preset_data)

        if imgflow_preset
          save_imgflow_preset(preset_name, imgflow_preset)
          results[:migrated] << preset_name
        else
          results[:skipped] << { name: preset_name, reason: "No convertible operations" }
        end
      rescue StandardError => e
        results[:errors] << { name: preset_name, error: e.message }
      end

      results
    end

    # Get migration summary without actually migrating
    # @return [Hash] Preview of what would be migrated
    def preview_migration
      results = {
        found: [],
        convertible: [],
        non_convertible: []
      }

      return results unless File.exist?(@picture_config_path)

      picture_config = load_picture_config
      return results unless picture_config["presets"]

      picture_config["presets"].each do |preset_name, preset_data|
        results[:found] << preset_name

        if convertible_operations?(preset_data)
          imgflow_preset = convert_preset_to_imgflow(preset_name, preset_data)
          results[:convertible] << { name: preset_name, preview: imgflow_preset }
        else
          results[:non_convertible] << { name: preset_name,
                                         reason: "No convertible operations" }
        end
      end

      results
    end

    private

    # Load Picture Tag configuration
    # @return [Hash] Picture Tag config
    def load_picture_config
      YAML.safe_load_file(@picture_config_path) || {}
    end

    # Check if preset has operations that can be converted
    # @param preset_data [Hash] Picture Tag preset data
    # @return [Boolean] True if convertible
    def convertible_operations?(preset_data)
      convertible_keys = %w[widths base_width width height quality formats crop gravity]
      convertible_keys.any? { |key| preset_data[key] }
    end

    # Convert Picture Tag preset to ImgFlow YAML format
    # @param preset_name [String] Preset name
    # @param preset_data [Hash] Picture Tag preset data
    # @return [Hash, nil] ImgFlow preset data or nil if not convertible
    def convert_preset_to_imgflow(preset_name, preset_data)
      operations = []
      add_resize_operation(operations, preset_data)
      add_quality_operation(operations, preset_data)
      add_format_operation(operations, preset_data)
      add_crop_operation(operations, preset_data)
      add_position_operation(operations, preset_data)

      return if operations.empty?

      {
        "name" => preset_name,
        "description" => generate_description(preset_name, preset_data),
        "operations" => operations,
        "picture_tag_metadata" => {
          "original_widths" => preset_data["widths"],
          "original_base_width" => preset_data["base_width"],
          "original_pixel_ratios" => preset_data["pixel_ratios"],
          "original_sizes" => preset_data["sizes"],
          "dimension_attributes" => preset_data["dimension_attributes"]
        }.compact
      }
    end

    def add_resize_operation(operations, preset_data)
      width = preset_width(preset_data)
      operations << { "resize" => { "width" => width } } if width

      return unless preset_data["height"]

      if operations.any? && operations.last["resize"]
        operations.last["resize"]["height"] = preset_data["height"]
      else
        operations << { "resize" => { "height" => preset_data["height"] } }
      end
    end

    def preset_width(preset_data)
      return Array(preset_data["widths"]).max if preset_data["widths"]
      return preset_data["base_width"] if preset_data["base_width"]

      preset_data["width"] if preset_data["width"]
    end

    def add_quality_operation(operations, preset_data)
      return unless preset_data["quality"]

      operations << { "quality" => { "quality" => preset_data["quality"] } }
    end

    def add_format_operation(operations, preset_data)
      return unless preset_data["formats"]

      formats = Array(preset_data["formats"]).map do |format|
        format == "original" ? "jpg" : format
      end
      operations << { "format" => { "formats" => formats } }
    end

    def add_crop_operation(operations, preset_data)
      ratio_value = preset_data["ratio"] || preset_data["aspect_ratio"] || preset_data["crop"]
      operations << { "crop" => { "ratio" => ratio_value } } if ratio_value
    end

    def add_position_operation(operations, preset_data)
      position_value = preset_data["position"] || preset_data["gravity"]
      return unless position_value

      crop_op = operations.find { |op| op["crop"] }
      if crop_op
        crop_op["crop"]["position"] = position_value
      else
        operations << { "crop" => { "position" => position_value } }
      end
    end

    # Generate description for ImgFlow preset
    # @param preset_name [String] Preset name
    # @param preset_data [Hash] Original preset data
    # @return [String] Description
    def generate_description(preset_name, preset_data)
      parts = []
      add_width_description(parts, preset_data)
      parts << "height: #{preset_data['height']}" if preset_data["height"]
      parts << "quality: #{preset_data['quality']}" if preset_data["quality"]
      parts << "formats: #{Array(preset_data['formats']).join(',')}" if preset_data["formats"]
      parts << "crop: #{preset_data['crop']}" if preset_data["crop"]
      parts << "gravity: #{preset_data['gravity']}" if preset_data["gravity"]

      "Migrated from Picture Tag preset '#{preset_name}'. #{parts.join(', ')}"
    end

    def add_width_description(parts, preset_data)
      if preset_data["widths"]
        parts << "widths: #{Array(preset_data['widths']).join(',')}"
        parts << "using max width: #{Array(preset_data['widths']).max}"
      elsif preset_data["base_width"]
        parts << "base_width: #{preset_data['base_width']}"
        parts << "pixel_ratios: #{Array(preset_data['pixel_ratios']).join(',')}"
      elsif preset_data["width"]
        parts << "width: #{preset_data['width']}"
      end
    end

    # Save ImgFlow preset to YAML file
    # @param preset_name [String] Preset name
    # @param preset_data [Hash] ImgFlow preset data
    def save_imgflow_preset(preset_name, preset_data)
      filename = "#{preset_name}.yml"
      filepath = File.join(@imgflow_presets_dir, filename)

      File.write(filepath, YAML.dump(preset_data))
    end
  end
end
