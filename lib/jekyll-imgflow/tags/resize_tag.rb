# frozen_string_literal: true

require_relative "base_tag"

module JekyllImgFlow
  module Tags
    # Resize tag - validates and processes image resizing
    class ResizeTag < BaseTag
      def process(input_path, output_path, options = {})
        ensure_output_dir(output_path)

        # Validate inputs
        width = validate_positive_integer(options[:width], "width")
        height = validate_positive_integer(options[:height], "height")

        raise ArgumentError, "Either width or height must be specified for resize operation." if width.nil? && height.nil?

        # Get original dimensions
        original_width, original_height = get_image_dimensions(input_path)

        # Calculate missing dimension to maintain aspect ratio ONLY when one dimension is missing
        width, height = calculate_missing_dimension(width, height, original_width, original_height)

        # Calculate scale factors for provider
        scale_x = width && original_width ? width.to_f / original_width : nil
        scale_y = height && original_height ? height.to_f / original_height : nil

        # Provider receives ALL data - provider chooses what to use
        resize_data = {
          original_width: original_width,
          original_height: original_height,
          target_width: width,
          target_height: height,
          scale_x: scale_x,
          scale_y: scale_y
        }

        Jekyll.logger.debug "🔍 ResizeTag: About to execute provider - input: #{input_path}, output: #{output_path}"
        @provider.resize(width, height, resize_data)
        @provider.quality(options[:quality]) if options[:quality]
        @provider.convert_format(options[:format]) if options[:format]
        result = @provider.execute(input_path, output_path)
        Jekyll.logger.debug "🔍 ResizeTag: Provider executed - result: #{result}, output exists: #{File.exist?(output_path)}"
        result
      end

      private

      def calculate_missing_dimension(width, height, original_width, original_height)
        if width.nil? && height
          # Only height provided - calculate width to maintain aspect ratio
          aspect_ratio = original_width.to_f / original_height
          [(height * aspect_ratio).round, height]
        elsif height.nil? && width
          # Only width provided - calculate height to maintain aspect ratio
          aspect_ratio = original_height.to_f / original_width
          [width, (width * aspect_ratio).round]
        else
          # If both width and height are provided, use them as-is (allows aspect ratio changes)
          [width, height]
        end
      end

      # validate_positive_integer inherited from BaseTag
    end
  end
end
