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

      # Handle multi-width presets - use the largest width as primary
      if preset_data["widths"]
        max_width = Array(preset_data["widths"]).max
        operations << { "resize" => { "width" => max_width } }
      elsif preset_data["base_width"]
        # For pixel-ratio presets, use base_width
        operations << { "resize" => { "width" => preset_data["base_width"] } }
      elsif preset_data["width"]
        # Direct width setting
        operations << { "resize" => { "width" => preset_data["width"] } }
      end

      # Handle height (less common in Picture Tag)
      if preset_data["height"]
        if operations.any? && operations.last["resize"]
          # Add height to existing resize operation
          operations.last["resize"]["height"] = preset_data["height"]
        else
          operations << { "resize" => { "height" => preset_data["height"] } }
        end
      end

      # Convert quality (if specified)
      operations << { "quality" => { "quality" => preset_data["quality"] } } if preset_data["quality"]

      # Convert formats - Picture Tag uses 'original', ImgFlow uses actual format
      if preset_data["formats"]
        formats = Array(preset_data["formats"]).map do |format|
          case format
          when "original"
            "jpg" # Default to jpg for 'original'
          else
            format
          end
        end
        operations << { "format" => { "formats" => formats } }
      end

      # Convert crop (aspect ratio) - handle both ratio and aspect_ratio with precedence
      ratio_value = preset_data["ratio"] || preset_data["aspect_ratio"] || preset_data["crop"]
      operations << { "crop" => { "ratio" => ratio_value } } if ratio_value

      # Convert gravity/position - handle both position and gravity with precedence
      position_value = preset_data["position"] || preset_data["gravity"]
      if position_value
        if operations.any? { |op| op["crop"] }
          # Add to existing crop operation
          crop_op = operations.find { |op| op["crop"] }
          crop_op["crop"]["position"] = position_value
        else
          # Create new crop operation
          operations << { "crop" => { "position" => position_value } }
        end
      end

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

    # Generate description for ImgFlow preset
    # @param preset_name [String] Preset name
    # @param preset_data [Hash] Original preset data
    # @return [String] Description
    def generate_description(preset_name, preset_data)
      operations = []

      if preset_data["widths"]
        operations << "widths: #{Array(preset_data['widths']).join(',')}"
        operations << "using max width: #{Array(preset_data['widths']).max}"
      elsif preset_data["base_width"]
        operations << "base_width: #{preset_data['base_width']}"
        operations << "pixel_ratios: #{Array(preset_data['pixel_ratios']).join(',')}"
      elsif preset_data["width"]
        operations << "width: #{preset_data['width']}"
      end

      operations << "height: #{preset_data['height']}" if preset_data["height"]
      operations << "quality: #{preset_data['quality']}" if preset_data["quality"]
      operations << "formats: #{Array(preset_data['formats']).join(',')}" if preset_data["formats"]
      operations << "crop: #{preset_data['crop']}" if preset_data["crop"]
      operations << "gravity: #{preset_data['gravity']}" if preset_data["gravity"]

      "Migrated from Picture Tag preset '#{preset_name}'. #{operations.join(', ')}"
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
