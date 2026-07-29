# frozen_string_literal: true

require "shellwords"
require "open3"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # ImageMagick provider implementation using the standardized tag interface
    class Imagemagick < BaseProvider
      def available?
        # Check if magick or convert CLI is available
        _, _, status1 = Open3.capture3("which", "magick")
        _, _, status2 = Open3.capture3("which", "convert")
        status1.success? || status2.success?
      end

      def execute(input_path, output_path)
        return if @operations.empty?

        # Build single ImageMagick command with all operations combined
        command = build_combined_imagemagick_command(input_path, output_path)
        execute_command(command)

        reset_operations
        output_path
      end

      def build_combined_imagemagick_command(input_path, output_path)
        # Start with base command
        command_parts = ["magick", input_path.shellescape]

        # Add all operations
        @operations.each do |operation|
          case operation[:type]
          when :resize
            # Tags now provide complete calculated values
            command_parts << "-resize" << if operation[:height]
                                            "#{operation[:width]}x#{operation[:height]}!"
                                          else
                                            operation[:width].to_s
                                          end

          when :crop
            opts = operation[:options]
            params = operation[:params] || {}

            # Check for keep parameter (ImageMagick doesn't support smartcrop, but we handle it gracefully)
            keep = opts[:keep] || params[:keep] || params[:position]

            if operation[:ratio] && keep && SMARTCROP_POSITIONS.include?(keep.to_s)
              # ImageMagick doesn't support smartcrop, but we handle the keep parameter
              # Use center gravity as a reasonable fallback for smartcrop requests
              crop_width = opts[:calculated_width]
              crop_height = opts[:calculated_height]
              crop_x = opts[:calculated_x]
              crop_y = opts[:calculated_y]

              # Use gravity center for smartcrop-like behavior
              crop_spec = "#{crop_width}x#{crop_height}+#{crop_x}+#{crop_y}"
              command_parts << "-gravity" << "center"
            else
              # Use basic cropping
              if operation[:ratio]
                crop_x = opts[:calculated_x]
                crop_y = opts[:calculated_y]
                crop_width = opts[:calculated_width]
                crop_height = opts[:calculated_height]
              else
                crop_x = opts[:x]
                crop_y = opts[:y]
                crop_width = opts[:width]
                crop_height = opts[:height]
              end
              crop_spec = "#{crop_width}x#{crop_height}+#{crop_x}+#{crop_y}"
            end
            command_parts << "-crop" << crop_spec

          when :quality
            magick_quality = translate_quality_to_imagemagick(operation[:quality])
            command_parts << "-quality" << magick_quality.to_s

          when :format
            # Assume validated input from tags
            # Format is handled by output filename extension
            # Quality is set separately if needed
            unless @operations.any? { |op| op[:type] == :quality }
              default_quality = @config&.quality || raise("No quality configured")
              command_parts << "-quality" << default_quality.to_s
            end

          when :watermark
            watermark_path = operation[:watermark_path]
            position = operation[:options][:position]

            # Translate compass directions to ImageMagick gravity format
            gravity = translate_position(position)

            # Add watermark as composite operation
            command_parts << watermark_path.shellescape
            command_parts << "-gravity" << gravity
            command_parts << "-composite"

          when :alpha_opacity
            opacity = operation[:opacity]
            alpha_value = (opacity * 100).round
            command_parts << "-alpha" << "set"
            command_parts << "-channel" << "A"
            command_parts << "-evaluate" << "multiply" << "#{alpha_value}%"
          end
        end

        # Add output filename
        command_parts << output_path.shellescape

        command_parts.join(" ")
      end

      def translate_position(position)
        case position
        when "northwest" then "NorthWest"
        when "northeast" then "NorthEast"
        when "southwest" then "SouthWest"
        when "southeast" then "SouthEast"
        when "center" then "Center"
        else position
        end
      end

      private

      def translate_quality_to_imagemagick(quality)
        # ImageMagick uses 1-100 directly, no translation needed
        quality
      end
    end
  end
end
