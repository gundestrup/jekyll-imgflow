# frozen_string_literal: true

require "fastimage"

module JekyllImgFlow
  module Tags
    # Base class for all ImgFlow tags
    class BaseTag
      def initialize(provider)
        @provider = provider
        @config = provider.config
        @default_quality = default_quality_from_config
      end

      def process(input_path, output_path, options = {})
        raise NotImplementedError, "Provider must implement #{self.class.name}#process"
      end

      protected

      def ensure_output_dir(output_path)
        dir = File.dirname(output_path)
        FileUtils.mkdir_p(dir)
      end

      def get_image_dimensions(image_path)
        return [nil, nil] unless File.exist?(image_path)

        begin
          FastImage.size(image_path)
        rescue FastImage::UnknownImageType, FastImage::ImageFetchError
          [nil, nil]
        end
      end

      # Like get_image_dimensions but raises if dimensions cannot be read.
      def get_original_dimensions(image_path)
        width, height = get_image_dimensions(image_path)
        raise ArgumentError, "Unable to determine original image dimensions" unless width && height

        [width, height]
      end

      def validate_positive_integer(value, name)
        return if value.nil?

        integer_value = value.to_i
        raise ArgumentError, "Invalid #{name}: '#{value}'. Must be a positive integer." if integer_value <= 0 || value.to_s != integer_value.to_s

        integer_value
      end

      def default_quality_from_config
        # Get default quality from provider's config
        # Config class already handles the fallback (cfg["quality"] || 85)
        @provider.config&.quality
      end

      def validate_quality(value)
        return @default_quality if value.nil?

        quality = value.to_i
        raise ArgumentError, "Invalid quality: '#{value}'. Must be between 1 and 100." unless quality.between?(1, 100)

        quality
      end

      def validate_opacity(value, min: 0.0, max: 1.0)
        raise ArgumentError, "Invalid opacity: '#{value}'. Must be between #{min} and #{max}." unless valid_numeric?(value)

        opacity = value.to_f
        raise ArgumentError, "Invalid opacity: '#{value}'. Must be between #{min} and #{max}." unless opacity.between?(min, max)

        opacity
      end

      def valid_numeric?(value)
        Float(value)
        true
      rescue ArgumentError, TypeError
        false
      end
    end
  end
end
