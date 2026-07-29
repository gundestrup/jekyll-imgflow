# frozen_string_literal: true

require_relative "base_tag"

module JekyllImgFlow
  module Tags
    # Opacity tag - validates and processes alpha channel manipulation
    class OpacityTag < BaseTag
      def process(input_path, output_path, options = {})
        ensure_output_dir(output_path)

        # Opacity must be explicitly provided (no default)
        opacity = options[:opacity]
        raise ArgumentError, "Opacity parameter is required" if opacity.nil?

        validated_opacity = validate_opacity(opacity)

        @provider.alpha_opacity = validated_opacity
        @provider.execute(input_path, output_path)
        output_path
      end

      private

      def validate_opacity(value)
        # Check if value is numeric before converting
        raise ArgumentError, "Invalid opacity: '#{value}'. Must be between 0.01 and 0.99." unless value.to_s.match?(/\A\d*\.?\d+\z/)

        opacity = value.to_f
        raise ArgumentError, "Invalid opacity: '#{value}'. Must be between 0.01 and 0.99." unless opacity.between?(0.01, 0.99)

        opacity
      end
    end
  end
end
