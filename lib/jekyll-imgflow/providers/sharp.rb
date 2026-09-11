# frozen_string_literal: true

require "shellwords"
require "open3"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Sharp provider implementation using the standardized tag interface
    class Sharp < CliBase
      def available?
        cli_available?("sharp")
      end

      def build_commands(input_path, output_path)
        build_sharp_command(input_path, output_path)
      end

      def build_sharp_command(input_path, output_path)
        if op?(:watermark)
          build_watermark_pipeline(input_path, output_path, op?(:crop), op?(:resize))
        elsif op?(:crop) && op?(:resize)
          build_sequential_crop_resize(input_path, output_path)
        elsif op?(:resize)
          build_resize_command(input_path, output_path)
        elsif op?(:crop)
          build_crop_command(input_path, output_path)
        else
          build_copy_command(input_path, output_path)
        end
      end

      def build_watermark_pipeline(input_path, output_path, has_crop, has_resize)
        temp = temp_path(input_path, "tmp_base.jpg")
        commands = []

        if has_crop && has_resize
          commands << build_sequential_crop_resize(input_path, temp)
          base_path = temp
        elsif has_resize
          commands << build_resize_command(input_path, temp)
          base_path = temp
        elsif has_crop
          commands << build_crop_command(input_path, temp)
          base_path = temp
        else
          base_path = input_path
        end

        commands << build_composite_command(base_path, output_path)
        commands << "rm -f #{temp.shellescape}" unless base_path == input_path
        commands.join(" && ")
      end

      def build_composite_command(base_path, output_path)
        wm_op = find_op(:watermark)
        parts = watermark_parts(wm_op)
        gravity = translate_position(parts[:position])

        command_parts = ["sharp", "-i", base_path.shellescape,
                         "-o", output_path.shellescape]

        add_format_quality(command_parts)

        if parts[:opacity] && parts[:opacity] < 1.0
          wm_temp = temp_path(parts[:watermark_path], "tmp_wm.png")
          alpha_value = alpha_byte_value(parts[:opacity])
          temp_cmd = ["sharp", "-i", parts[:watermark_path].shellescape,
                      "-o", wm_temp.shellescape,
                      "ensureAlpha", alpha_value.to_s].join(" ")
          command_parts += ["composite", wm_temp.shellescape,
                            "--gravity", gravity, "--blend", "over"]
          "#{temp_cmd} && #{command_parts.join(' ')} " \
            "&& rm -f #{wm_temp.shellescape}"
        else
          command_parts += ["composite", parts[:watermark_path].shellescape,
                            "--gravity", gravity, "--blend", "over"]
          command_parts.join(" ")
        end
      end

      def translate_position(position)
        case position.to_s
        when "northwest" then "northwest"
        when "northeast" then "northeast"
        when "southwest" then "southwest"
        when "southeast" then "southeast"
        when "center" then "center"
        else position.to_s
        end
      end

      def build_sequential_crop_resize(input_path, output_path)
        # Build temp file path for intermediate crop result
        temp = temp_path(input_path, "tmp_crop.jpg")

        # First command: crop only
        crop_cmd = build_crop_command(input_path, temp)

        # Second command: resize + format + quality + alpha (all together)
        resize_cmd = build_resize_command(temp, output_path)

        # Combine with && and cleanup temp file
        "#{crop_cmd} && #{resize_cmd} && rm -f #{temp.shellescape}"
      end

      def build_resize_command(input_path, output_path)
        resize_op = find_op(:resize)

        # sharp -i input.jpg -o output.jpg resize width [height] -f format -q quality
        command_parts = ["sharp", "-i", input_path.shellescape, "-o", output_path.shellescape]

        # Add resize
        command_parts += if resize_op[:height]
                           ["resize", resize_op[:width].to_s, resize_op[:height].to_s]
                         else
                           ["resize", resize_op[:width].to_s]
                         end

        add_format_quality_alpha(command_parts)
        command_parts.join(" ")
      end

      def build_crop_command(input_path, output_path)
        crop_op = find_op(:crop)
        geo = crop_geometry(crop_op)

        if geo[:smartcrop]
          # Use smartcrop for intelligent cropping (Sharp uses libvips backend)
          interestingness = smartcrop_interestingness(geo[:keep])

          # sharp -i input.jpg -o output.jpg smartcrop width height --interesting=attention
          ["sharp", "-i", input_path.shellescape, "-o", output_path.shellescape,
           "smartcrop", geo[:width].to_s, geo[:height].to_s,
           "--interesting=#{interestingness}"].join(" ")
        else
          # Use basic extract for manual cropping or when no keep parameter
          # sharp -i input.jpg -o output.jpg extract top left width height
          ["sharp", "-i", input_path.shellescape, "-o", output_path.shellescape,
           "extract", geo[:y].to_s, geo[:x].to_s, geo[:width].to_s,
           geo[:height].to_s].join(" ")
        end
      end

      def build_copy_command(input_path, output_path)
        # sharp -i input.jpg -o output.jpg -f format -q quality
        command_parts = ["sharp", "-i", input_path.shellescape, "-o", output_path.shellescape]

        add_format_quality_alpha(command_parts)
        command_parts.join(" ")
      end

      # Sharp CLI calls JPEG "jpeg", while ImgFlow uses the standard "jpg"
      # extension in generated filenames and public configuration.
      def sharp_format(format)
        format.to_s == "jpg" ? "jpeg" : format
      end

      private

      def add_format_quality(command_parts)
        format_op = find_op(:format)
        quality_op = find_op(:quality)
        command_parts.push("-f", sharp_format(format_op[:format])) if format_op
        command_parts.push("-q#{quality_op[:quality]}") if quality_op
      end

      def add_format_quality_alpha(command_parts)
        add_format_quality(command_parts)
        alpha_op = find_op(:alpha_opacity)
        return unless alpha_op

        command_parts.push("alpha", "{alpha:#{alpha_byte_value(alpha_op[:opacity])}}")
      end
    end
  end
end
