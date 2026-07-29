# frozen_string_literal: true

require_relative "base_tag"

module JekyllImgFlow
  module Tags
    # Format tag - validates and processes format conversion
    class FormatTag < BaseTag
      def process(input_path, output_path, options = {})
        formats = options[:formats] || [options[:format]]

        # Handle case where formats is a single string instead of array
        formats = Array(formats)

        # Validate formats against unified config
        validated_formats = formats.map { |format| validate_format(format) }
        results = []

        validated_formats.each do |format|
          # Simple file extension replacement
          last_dot = output_path.rindex(".")
          format_output_path = if last_dot
                                 output_path[0...last_dot] + ".#{format}"
                               else
                                 output_path + ".#{format}"
                               end
          ensure_output_dir(format_output_path)

          # Reset provider operations before each format conversion
          @provider.reset_operations
          @provider.convert_format(format)
          @provider.execute(input_path, format_output_path)
          results << format_output_path
        end

        results
      end

      private

      def validate_format(format)
        raise ArgumentError, "Format cannot be nil" if format.nil?

        # Get allowed formats from unified config (no fallback)
        allowed_formats = @config.formats
        raise ArgumentError, "No formats configured in unified config" unless allowed_formats

        format_str = format.to_s.downcase

        # Validate format is allowed in config
        unless allowed_formats.include?(format_str)
          raise ArgumentError,
                "Invalid format: '#{format}'. Must be one of: #{allowed_formats.join(', ')}."
        end

        # Standardize format names (prefer canonical forms)
        case format_str
        when "jpeg" then "jpg" # Standardize to jpg
        else format_str
        end
      end
    end
  end
end
