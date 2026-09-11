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

        validated_opacity = validate_opacity(opacity, min: 0.01, max: 0.99)

        @provider.alpha_opacity = validated_opacity
        @provider.execute(input_path, output_path)
        output_path
      end
    end
  end
end
