# frozen_string_literal: true

require_relative "base_tag"

module JekyllImgFlow
  module Tags
    # Watermark tag - validates and processes watermark operations
    class WatermarkTag < BaseTag
      def process(input_path, output_path, options = {})
        ensure_output_dir(output_path)

        watermark_path = options[:watermark]
        position = options[:position] || :bottom_right
        opacity = options[:opacity] || 0.7

        # Validate and translate position for providers
        translated_position = translate_watermark_position(position)
        translated_opacity = validate_opacity(opacity)

        @provider.add_watermark(watermark_path, position: translated_position,
                                                opacity: translated_opacity)
        @provider.execute(input_path, output_path)
        output_path
      end

      private

      def translate_watermark_position(position)
        # Translate abstract positions to provider-specific values
        case position
        when :top_left then "northwest"
        when :top_right then "northeast"
        when :bottom_left then "southwest"
        when :bottom_right then "southeast"
        when :center then "center"
        else position.to_s
        end
      end

      def validate_opacity(value)
        # Check if value is numeric before converting
        raise ArgumentError, "Invalid opacity: '#{value}'. Must be between 0.0 and 1.0." unless value.to_s.match?(/\A\d*\.?\d+\z/)

        opacity = value.to_f
        raise ArgumentError, "Invalid opacity: '#{value}'. Must be between 0.0 and 1.0." unless opacity.between?(0.0, 1.0)

        opacity
      end
    end
  end
end
