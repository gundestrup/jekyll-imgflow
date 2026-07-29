# frozen_string_literal: true

require_relative "base_tag"

module JekyllImgFlow
  module Tags
    # Optimize tag - validates and processes optimization levels
    class OptimizeTag < BaseTag
      def process(input_path, output_path, options = {})
        ensure_output_dir(output_path)

        level = options[:level] || :medium
        quality = translate_optimize_level_to_quality(level)

        # Validate the translated quality
        quality = validate_quality(quality)

        @provider.quality = quality
        @provider.execute(input_path, output_path)
      end

      private

      def translate_optimize_level_to_quality(level)
        # Use config optimize_qualities for single source of truth
        optimize_configs = @provider.config.optimize_qualities || raise("No optimize_qualities configured")

        level_key = level.to_s
        quality = optimize_configs[level_key]

        # Use configured value, or default quality for medium/high
        if quality.nil? && %w[medium high].include?(level_key)
          quality = @default_quality || raise("No default quality configured")
        elsif quality.nil?
          # Use default config for unknown levels
          quality = optimize_configs["default"] || raise("No default optimize quality configured")
        end

        quality
      end

      def validate_quality(value)
        return @default_quality if value.nil?

        quality = value.to_i
        raise ArgumentError, "Invalid quality: '#{value}'. Must be between 1 and 100." unless quality.between?(1, 100)

        quality
      end
    end
  end
end
