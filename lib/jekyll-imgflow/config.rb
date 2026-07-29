# frozen_string_literal: true

module JekyllImgFlow
  class Config
    attr_reader :site, :originals, :output, :input_formats, :sizes, :formats,
                :quality, :backend_priority, :imgproxy_url,
                :image_compressor_url, :weserv_url, :flyimg_url,
                :optimize_qualities

    def initialize(site)
      shared = site.config["shared_images_configs"] || {}
      overrides = site.config["imgflow"] || {}
      cfg = shared.merge(overrides)

      @site             = site
      @originals        = cfg["originals"]
      @output           = cfg["output"]
      @input_formats    = cfg["input_formats"]
      @sizes            = cfg["sizes"]
      @formats          = cfg["formats"]
      @quality          = cfg["quality"]
      @backend_priority = cfg["backend_priority"]

      # Validate required config fields
      raise ArgumentError, "No originals configured in unified config" unless @originals
      raise ArgumentError, "No output configured in unified config" unless @output
      raise ArgumentError, "No input_formats configured in unified config" unless @input_formats
      raise ArgumentError, "No formats configured in unified config" unless @formats
      raise ArgumentError, "No sizes configured in unified config" unless @sizes

      @imgproxy_url = cfg["imgproxy_url"]
      @image_compressor_url = cfg["image_compressor_url"]
      @weserv_url       = cfg["weserv_url"]
      @flyimg_url       = cfg["flyimg_url"]
      @optimize_qualities = cfg["optimize_qualities"] || {
        "low" => 30,
        "medium" => 50, # Uses default quality
        "high" => 85, # Uses default quality
        "maximum" => 95,
        "default" => 75
      }

      validate_backend_priority!
    end

    def cache_dir
      merged_config["cache_dir"] || ".cache/imgflow"
    end

    def docker_config
      {
        enabled: merged_config.key?("imgproxy_url") ||
          merged_config.key?("weserv_url") ||
          merged_config.key?("flyimg_url") ||
          merged_config.key?("image_compressor_url"),
        imgproxy_url: @imgproxy_url,
        weserv_url: @weserv_url,
        flyimg_url: @flyimg_url,
        image_compressor_url: @image_compressor_url
      }
    end

    def docker_enabled
      docker_config[:enabled]
    end

    def sharp_url
      merged_config["sharp_url"]
    end

    # Determine if params represent a default or specialized version
    # @param params [Hash] Operation parameters
    # @return [Symbol] :default or :specialized
    def determine_version_type(params)
      if params[:width] && @sizes.value?(params[:width]) &&
         (!params[:format] || @formats.include?(params[:format])) &&
         (!params[:quality] || params[:quality] == @quality)
        :default
      else
        :specialized
      end
    end

    # Format validation methods
    def supported_input_format?(format)
      normalized_format = format.to_s.downcase.delete(".")
      @input_formats.map(&:downcase).include?(normalized_format)
    end

    def supported_output_format?(format)
      normalized_format = format.to_s.downcase.delete(".")
      @formats.map(&:downcase).include?(normalized_format)
    end

    def validate_input_format!(format)
      return if supported_input_format?(format)

      raise ArgumentError,
            "Unsupported input format '#{format}'. Supported formats: #{@input_formats.join(', ')}"
    end

    def validate_output_format!(format)
      return if supported_output_format?(format)

      raise ArgumentError,
            "Unsupported output format '#{format}'. Supported formats: #{@formats.join(', ')}"
    end

    # Get normalized format lists
    def normalized_input_formats
      @input_formats.map(&:downcase)
    end

    def normalized_output_formats
      @formats.map(&:downcase)
    end

    private

    def merged_config
      shared = @site.config["shared_images_configs"] || {}
      overrides = @site.config["imgflow"] || {}
      shared.merge(overrides)
    end

    def validate_backend_priority!
      # No manual-only providers to validate
    end
  end
end
