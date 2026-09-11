# frozen_string_literal: true

require "shellwords"
require "yaml"

module JekyllImgFlow
  # PresetManager - translates YAML presets to tags:value format
  # Handles tag overrides (user tags override preset tags)
  # Passes combined markup to Parser for uniform validation flow
  #
  # Presets are loaded from two sources (user presets take precedence):
  # 1. Site presets:  _data/imgflow/presets/*.yml  (user-defined, override built-ins)
  # 2. Built-in presets: lib/jekyll-imgflow/presets/*.yml (shipped with the gem)
  class PresetManager
    BUILTIN_PRESETS_DIR = File.expand_path("presets", __dir__).freeze

    def initialize(site, config)
      @site = site
      @config = config
      @presets = load_presets
    end

    # Load presets from the site's _data/imgflow/presets/ directory,
    # then merge in built-in presets from the gem. User presets override
    # built-in presets of the same name.
    def load_presets
      presets = load_presets_from_dir(builtin_presets_dir)
      presets.merge(load_presets_from_dir(site_presets_dir))
    end

    # Path to built-in presets shipped with the gem
    def builtin_presets_dir
      BUILTIN_PRESETS_DIR
    end

    # Path to user-defined presets in the site
    def site_presets_dir
      File.join(@site.source, "_data", "imgflow", "presets")
    end

    # Load all preset YAML files from a directory
    # @param dir [String] Directory containing *.yml preset files
    # @return [Hash<String, Hash>] Preset name => preset data
    def load_presets_from_dir(dir)
      presets = {}
      return presets unless dir && Dir.exist?(dir)

      Dir.glob(File.join(dir, "*.yml")).each do |preset_file|
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

    # Get all available preset names (user + built-in)
    # @return [Array<String>] Array of preset names
    def available_presets
      @presets.keys
    end

    # Get names of built-in presets shipped with the gem
    # @return [Array<String>] Array of built-in preset names
    def builtin_preset_names
      names = []
      return names unless Dir.exist?(builtin_presets_dir)

      Dir.glob(File.join(builtin_presets_dir, "*.yml")).each do |file|
        names << File.basename(file, ".yml")
      end
      names
    end

    # Check if a preset is a built-in (shipped with the gem)
    # @param name [String] Preset name
    # @return [Boolean] True if the preset is built-in
    def builtin_preset?(name)
      builtin_preset_names.include?(name.to_s)
    end

    # Check if a preset is user-defined (in the site's _data/)
    # @param name [String] Preset name
    # @return [Boolean] True if the preset is user-defined
    def user_preset?(name)
      File.exist?(File.join(site_presets_dir, "#{name}.yml"))
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
      (preset["operations"] || []).each do |op|
        next unless op.is_a?(Hash)

        op.each do |op_type, params|
          next unless params.is_a?(Hash)

          merge_operation_tags(tags, op_type.to_s, params)
        end
      end

      tags
    end

    def merge_operation_tags(tags, op_type, params)
      case op_type
      when "resize"
        tags[:width] = params["width"] if params["width"]
        tags[:height] = params["height"] if params["height"]
      when "crop"
        tags[:ratio] = params["ratio"] if params["ratio"]
        tags[:aspect_ratio] = params["aspect_ratio"] if params["aspect_ratio"]
        tags[:width] = params["width"] if params["width"] && !tags[:width]
        tags[:height] = params["height"] if params["height"] && !tags[:height]
      when "format"
        merge_format_tag(tags, params)
      when "quality"
        tags[:quality] = params["quality"] if params["quality"]
      when "optimize"
        tags[:optimize] = true
        tags[:level] = params["level"] if params["level"]
      when "opacity"
        tags[:opacity] = params["opacity"] if params["opacity"]
      else
        merge_generic_tags(tags, params)
      end
    end

    def merge_format_tag(tags, params)
      if params["formats"]
        tag_value = params["formats"].is_a?(Array) ? params["formats"].join(",") : params["formats"]
        tags[:formats] = tag_value
      elsif params["format"]
        tags[:format] = params["format"]
      end
    end

    def merge_generic_tags(tags, params)
      params.each do |key, value|
        tag_value = value.is_a?(Array) ? value.join(",") : value
        tags[key.to_sym] = tag_value
      end
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
      tags.map { |key, value| "#{key}:#{Shellwords.escape(value.to_s)}" }.join(" ")
    end
  end
end
