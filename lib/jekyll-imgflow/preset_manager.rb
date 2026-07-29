# frozen_string_literal: true

require "yaml"

module JekyllImgFlow
  # PresetManager - translates YAML presets to tags:value format
  # Handles tag overrides (user tags override preset tags)
  # Passes combined markup to Parser for uniform validation flow
  class PresetManager
    def initialize(site, config)
      @site = site
      @config = config
      @presets = load_presets
    end

    # Load presets from _data/imgflow/presets/
    def load_presets
      presets = {}
      presets_dir = File.join(@site.source, "_data", "imgflow", "presets")

      return presets unless Dir.exist?(presets_dir)

      Dir.glob(File.join(presets_dir, "*.yml")).each do |preset_file|
        preset_name = File.basename(preset_file, ".yml")
        begin
          preset_data = YAML.safe_load_file(preset_file)
          presets[preset_name] = preset_data
        rescue Psych::SyntaxError => e
          Jekyll.logger.warn "ImgFlow: Invalid YAML in preset file #{preset_file}: #{e.message}"
          # Skip invalid preset files
        end
      end

      presets
    end

    # Get a preset by name
    # @param name [String] Preset name
    # @return [Hash, nil] Preset data or nil if not found
    def get_preset(name)
      @presets[name.to_s]
    end

    # Check if a preset exists
    # @param name [String] Preset name
    # @return [Boolean] True if preset exists
    def preset_exists?(name)
      @presets.key?(name.to_s)
    end

    # Get all available preset names
    # @return [Array<String>] Array of preset names
    def available_presets
      @presets.keys
    end

    # Build markup from preset (tags:value format)
    # @param preset_name [String] Name of preset
    # @param user_options [Hash] User-provided options that override preset values
    # @return [String] Markup string in tags:value format
    def build_markup_from_preset(preset_name, user_options = {})
      preset = get_preset(preset_name)
      return "" unless preset

      # Convert YAML operations to tags:value format
      preset_tags = yaml_to_tags(preset)

      # Merge with user options (user options override preset)
      merged_tags = merge_tags(preset_tags, user_options)

      # Convert to markup string
      tags_to_markup(merged_tags)
    end

    private

    # Convert YAML operations to tags hash
    # Note: Multiple operations of same type will have last one's values
    # This matches the override behavior where user tags override preset tags
    # @param preset [Hash] Preset data from YAML
    # @return [Hash] Tags in key => value format
    def yaml_to_tags(preset)
      tags = {}
      preset_operations = preset["operations"] || []

      preset_operations.each do |op|
        next unless op.is_a?(Hash)

        op.each do |op_type, params|
          next unless params.is_a?(Hash)

          # Store operation type for operations that don't have specific params
          # This allows Parser to detect the operation type
          case op_type.to_s
          when "resize"
            # Resize params: width, height (both optional, at least one required)
            tags[:width] = params["width"] if params["width"]
            tags[:height] = params["height"] if params["height"]
          when "crop"
            # Crop params: ratio or width/height
            tags[:ratio] = params["ratio"] if params["ratio"]
            tags[:aspect_ratio] = params["aspect_ratio"] if params["aspect_ratio"]
            tags[:width] = params["width"] if params["width"] && !tags[:width]
            tags[:height] = params["height"] if params["height"] && !tags[:height]
          when "format"
            # Format params: format or formats
            if params["formats"]
              tag_value = params["formats"].is_a?(Array) ? params["formats"].join(",") : params["formats"]
              tags[:formats] = tag_value
            elsif params["format"]
              tags[:format] = params["format"]
            end
          when "quality"
            tags[:quality] = params["quality"] if params["quality"]
          when "optimize"
            tags[:optimize] = true
            tags[:level] = params["level"] if params["level"]
          when "opacity"
            tags[:opacity] = params["opacity"] if params["opacity"]
          else
            # Generic handling for unknown operations
            params.each do |key, value|
              tag_value = value.is_a?(Array) ? value.join(",") : value
              tags[key.to_sym] = tag_value
            end
          end
        end
      end

      tags
    end

    # Merge preset tags with user options (user options override)
    # @param preset_tags [Hash] Tags from preset
    # @param user_options [Hash] User-provided options
    # @return [Hash] Merged tags
    def merge_tags(preset_tags, user_options)
      # User options override preset tags
      preset_tags.merge(user_options)
    end

    # Convert tags hash to markup string
    # @param tags [Hash] Tags in key => value format
    # @return [String] Markup string
    def tags_to_markup(tags)
      tags.map { |key, value| "#{key}:#{value}" }.join(" ")
    end
  end
end
