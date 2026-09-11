# frozen_string_literal: true

require "shellwords"
require "open3"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # ImageMagick provider implementation using the standardized tag interface
    class Imagemagick < CliBase
      # Cache rsvg delegate check across all instances (checked once per build)
      @rsvg_available = nil
      @svg_warning_shown = false

      def available?
        cli_available?("magick", "convert")
      end

      def before_execute(input_path)
        # Warn once per build about SVG performance with ImageMagick
        warn_svg_performance if svg?(input_path) && !self.class.instance_variable_get(:@svg_warning_shown)
      end

      def build_commands(input_path, output_path)
        build_combined_imagemagick_command(input_path, output_path)
      end

      def build_combined_imagemagick_command(input_path, output_path)
        # Start with base command.
        # For SVGs, set -density before the input so ImageMagick rasterizes
        # at a reasonable resolution instead of the full viewBox (which can
        # be 10000x8500 = 85M pixels, making each conversion take 10+ seconds).
        # With the rsvg delegate installed, -density controls the render DPI.
        # Without rsvg, ImageMagick uses its slow internal MSVG parser.
        command_parts = if svg?(input_path)
                          ["magick", "-density", svg_density.to_s, input_path.shellescape]
                        else
                          ["magick", input_path.shellescape]
                        end

        @operations.each { |operation| append_imagemagick_operation(operation, command_parts) }

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

      def append_imagemagick_operation(operation, command_parts)
        case operation[:type]
        when :resize
          command_parts << "-resize" << if operation[:height]
                                          "#{operation[:width]}x#{operation[:height]}!"
                                        else
                                          operation[:width].to_s
                                        end
        when :crop
          append_imagemagick_crop(operation, command_parts)
        when :quality
          command_parts << "-quality" << operation[:quality].to_s
        when :format
          # Format is handled by output filename extension.
          # Quality is set separately if needed.
          unless op?(:quality)
            default_quality = @config&.quality || raise("No quality configured")
            command_parts << "-quality" << default_quality.to_s
          end
        when :watermark
          append_imagemagick_watermark(operation, command_parts)
        when :alpha_opacity
          alpha_value = (operation[:opacity] * 100).round
          command_parts << "-alpha" << "set"
          command_parts << "-channel" << "A"
          command_parts << "-evaluate" << "multiply" << "#{alpha_value}%"
        end
      end

      def append_imagemagick_crop(operation, command_parts)
        geo = crop_geometry(operation)

        if geo[:smartcrop]
          # ImageMagick doesn't support smartcrop, but we handle the keep parameter
          # Use center gravity as a reasonable fallback for smartcrop requests
          command_parts << "-gravity" << "center"
        end

        crop_spec = "#{geo[:width]}x#{geo[:height]}+#{geo[:x]}+#{geo[:y]}"
        command_parts << "-crop" << crop_spec
      end

      def append_imagemagick_watermark(operation, command_parts)
        parts = watermark_parts(operation)
        gravity = translate_position(parts[:position])

        # Add watermark as composite operation
        command_parts << parts[:watermark_path].shellescape
        command_parts << "-gravity" << gravity
        command_parts << "-composite"
      end

      # Choose a rasterization density (DPI) for SVG input.
      # ImageMagick's internal SVG parser renders at the full viewBox size
      # (e.g. 10000x8500 = 85M pixels) before applying -resize, which is
      # extremely slow. Setting -density before the input tells the rsvg
      # delegate to render at a lower resolution.
      # We target ~2x the largest resize dimension for good quality,
      # assuming a ~10 inch viewBox (common for SVGs). This avoids the
      # massive internal canvas while preserving output quality.
      # For a 400px output: density = 80px/in / 10in = 8 DPI → renders at
      # ~800px instead of 10000px, giving ~10x speedup.
      def svg_density
        max_width = @operations.filter_map { |op| op[:type] == :resize && op[:width] }.max
        # Default to 36 DPI if no resize (e.g. format-only conversion)
        return 36 unless max_width

        # Target 2x output width for quality. Assume ~10 inch viewBox.
        # No upper cap — even 2000px output only needs 40 DPI.
        (max_width * 2 / 10).to_i
      end

      # Check if ImageMagick has the rsvg delegate installed.
      # Without it, ImageMagick uses its slow internal MSVG parser.
      # Install with: macOS: `brew install librsvg`, Ubuntu: `apt install librsvg2-bin`
      def rsvg_available?
        return self.class.instance_variable_get(:@rsvg_available) unless self.class.instance_variable_get(:@rsvg_available).nil?

        stdout, _, status = Open3.capture3("magick", "-list", "delegate")
        result = status.success? && stdout.include?("rsvg-convert")
        self.class.instance_variable_set(:@rsvg_available, result)
        result
      end

      # Warn once per build about SVG performance with ImageMagick.
      # Suggests installing rsvg-convert or using a different provider.
      def warn_svg_performance
        return if self.class.instance_variable_get(:@svg_warning_shown)

        self.class.instance_variable_set(:@svg_warning_shown, true)
        if rsvg_available?
          Jekyll.logger.info "ImgFlow:",
                             "ImageMagick processing SVG with rsvg delegate " \
                             "(density=#{svg_density})."
        else
          Jekyll.logger.warn "ImgFlow:",
                             "ImageMagick is processing SVGs without the rsvg " \
                             "delegate — this is VERY slow. Install librsvg " \
                             "(macOS: `brew install librsvg`, " \
                             "Ubuntu: `apt install librsvg2-bin`) or use a " \
                             "different provider (sharp/libvips) for SVGs."
        end
      end
    end
  end
end
