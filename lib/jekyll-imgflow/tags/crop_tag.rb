# frozen_string_literal: true

require_relative "base_tag"

module JekyllImgFlow
  module Tags
    # Crop tag - processes image cropping (validation handled by Parser)
    class CropTag < BaseTag
      def process(input_path, output_path, options = {})
        ensure_output_dir(output_path)

        ratio = options[:ratio] || options[:aspect_ratio]
        has_pixel_crop = options[:width] || options[:height]

        validate_crop_request(ratio, has_pixel_crop)

        if ratio
          validate_ratio(ratio)
          handle_aspect_ratio_crop(input_path, output_path, ratio, options)
        else
          validate_pixel_dimensions(options)
          handle_pixel_crop(input_path, output_path, options)
        end

        @provider.execute(input_path, output_path)
      end

      private

      def validate_crop_request(ratio, has_pixel_crop)
        return if ratio || has_pixel_crop

        raise ArgumentError,
              "Crop operation requires ratio or at least one dimension (width or height)"
      end

      def validate_pixel_dimensions(options)
        validate_positive_integer(options[:width], "width") if options[:width]
        validate_positive_integer(options[:height], "height") if options[:height]
        validate_positive_integer(options[:x], "x") if options[:x]
        validate_positive_integer(options[:y], "y") if options[:y]
      end

      # Handle aspect ratio cropping
      def handle_aspect_ratio_crop(input_path, _output_path, ratio, options)
        # Calculate optimal crop dimensions for the aspect ratio
        calculated_options = calculate_aspect_ratio_dimensions(input_path, ratio, options)
        add_keep_option(calculated_options, options[:keep])

        # Pass ratio and calculated options to provider (uniform interface)
        @provider.crop(ratio, calculated_options)
      end

      # Handle flexible pixel-based cropping
      def handle_pixel_crop(input_path, _output_path, options)
        original_width, original_height = get_original_dimensions(input_path)

        crop_width = parse_dimension(options[:width], original_width)
        crop_height = parse_dimension(options[:height], original_height)

        raise ArgumentError, "At least width or height must be specified for cropping" unless crop_width || crop_height

        # Calculate missing dimension if only one provided
        crop_width ||= original_width # Keep original width
        crop_height ||= original_height # Keep original height

        # Parse positions with smart defaults - always provide values
        crop_x = parse_position_with_default(options[:x], crop_width, original_width)
        crop_y = parse_position_with_default(options[:y], crop_height, original_height)

        validate_crop_dimensions(crop_x, crop_y, crop_width, crop_height, original_width,
                                 original_height)

        crop_options = { x: crop_x, y: crop_y, width: crop_width, height: crop_height }
        add_keep_option(crop_options, options[:keep])

        @provider.crop(nil, crop_options)
      end

      def add_keep_option(crop_options, keep)
        return unless keep && %w[attention entropy center centre].include?(keep.to_s)

        crop_options[:keep] = keep
      end

      # Parse dimension (supports pixels and percentages)
      def parse_dimension(value, original_size)
        return if value.nil?

        if value.to_s.end_with?("%")
          # Percentage-based: "50%" → original_size * 0.5
          percentage = value.to_f / 100
          (original_size * percentage).round
        else
          # Absolute pixels: "800" → 800
          value.to_i
        end
      end

      # Parse position with smart defaults
      def parse_position(value, crop_size, original_size)
        return if value.nil?

        if value.to_s == "center"
          # Center the crop
          ((original_size - crop_size) / 2).round
        else
          # Absolute position
          value.to_i
        end
      end

      # Parse position with default to center if not specified
      def parse_position_with_default(value, crop_size, original_size)
        return ((original_size - crop_size) / 2).round if value.nil?

        if value.to_s == "center"
          # Center the crop
          ((original_size - crop_size) / 2).round
        else
          # Absolute position
          value.to_i
        end
      end

      # Validate crop dimensions don't exceed original image
      def validate_crop_dimensions(crop_x, crop_y, crop_width, crop_height, original_width,
                                   original_height)
        if crop_x.negative? || crop_y.negative?
          raise ArgumentError,
                "Crop position cannot be negative"
        end

        return if crop_x + crop_width <= original_width && crop_y + crop_height <= original_height

        raise ArgumentError, "Crop area exceeds original image dimensions"
      end

      # Calculate optimal dimensions for aspect ratio cropping
      def calculate_aspect_ratio_dimensions(input_path, ratio, _options)
        original_width, original_height = get_original_dimensions(input_path)

        # Parse ratio like "16:9"
        ratio_width, ratio_height = ratio.split(":").map(&:to_f)
        target_ratio = ratio_width / ratio_height
        original_ratio = original_width.to_f / original_height

        # Calculate crop dimensions
        if original_ratio > target_ratio
          # Image is wider than target ratio - crop width
          calculated_height = original_height
          calculated_width = (calculated_height * target_ratio).round
          calculated_x = ((original_width - calculated_width) / 2).round
          calculated_y = 0
        else
          # Image is taller than target ratio - crop height
          calculated_width = original_width
          calculated_height = (calculated_width / target_ratio).round
          calculated_x = 0
          calculated_y = ((original_height - calculated_height) / 2).round
        end

        {
          calculated_width: calculated_width,
          calculated_height: calculated_height,
          calculated_x: calculated_x,
          calculated_y: calculated_y
        }
      end

      # Validate ratio format (e.g., "16:9")
      def validate_ratio(ratio)
        return ratio if ratio.nil?

        # Convert symbol to string
        ratio_str = ratio.to_s

        # Validate format
        unless ratio_str.match?(/\A\d+:\d+\z/)
          raise ArgumentError,
                "Invalid ratio: '#{ratio}'. Must be in format 'width:height' (e.g., '16:9')."
        end

        # Validate numeric values
        width, height = ratio_str.split(":").map(&:to_i)
        if width <= 0 || height <= 0
          raise ArgumentError,
                "Invalid ratio: '#{ratio}'. Width and height must be positive numbers."
        end

        ratio_str
      end

      # validate_positive_integer inherited from BaseTag
    end
  end
end
