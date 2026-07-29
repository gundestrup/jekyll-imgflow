# frozen_string_literal: true

require "shellwords"
require "open3"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Sharp provider implementation using the standardized tag interface
    class Sharp < BaseProvider
      def available?
        # Check if sharp CLI is available
        _, _, status = Open3.capture3("which", "sharp")
        status.success?
      end

      def execute(input_path, output_path)
        return if @operations.empty?

        # Build Sharp command
        command = build_sharp_command(input_path, output_path)
        execute_command(command)

        reset_operations
        output_path
      end

      def build_sharp_command(input_path, output_path)
        has_crop = @operations.any? { |op| op[:type] == :crop }
        has_resize = @operations.any? { |op| op[:type] == :resize }
        has_watermark = @operations.any? { |op| op[:type] == :watermark }

        if has_watermark
          build_watermark_pipeline(input_path, output_path, has_crop, has_resize)
        elsif has_crop && has_resize
          build_sequential_crop_resize(input_path, output_path)
        elsif has_resize
          build_resize_command(input_path, output_path)
        elsif has_crop
          build_crop_command(input_path, output_path)
        else
          build_copy_command(input_path, output_path)
        end
      end

      def build_watermark_pipeline(input_path, output_path, has_crop, has_resize)
        temp_path = input_path.gsub(/\.[^.]+$/, ".tmp_base.jpg")
        commands = []

        if has_crop && has_resize
          commands << build_sequential_crop_resize(input_path, temp_path)
          base_path = temp_path
        elsif has_resize
          commands << build_resize_command(input_path, temp_path)
          base_path = temp_path
        elsif has_crop
          commands << build_crop_command(input_path, temp_path)
          base_path = temp_path
        else
          base_path = input_path
        end

        commands << build_composite_command(base_path, output_path)
        commands << "rm -f #{temp_path.shellescape}" unless base_path == input_path
        commands.join(" && ")
      end

      def build_composite_command(base_path, output_path)
        wm_op = @operations.find { |op| op[:type] == :watermark }
        watermark_path = wm_op[:watermark_path]
        position = wm_op[:options][:position]
        opacity = wm_op[:options][:opacity]

        gravity = translate_position(position)

        command_parts = ["sharp", "-i", base_path.shellescape,
                         "-o", output_path.shellescape]

        format_op = @operations.find { |op| op[:type] == :format }
        quality_op = @operations.find { |op| op[:type] == :quality }
        command_parts += ["-f", format_op[:format]] if format_op
        command_parts += ["-q#{quality_op[:quality]}"] if quality_op

        if opacity && opacity < 1.0
          wm_temp = watermark_path.gsub(/\.[^.]+$/, ".tmp_wm.png")
          alpha_value = (opacity * 255).round
          temp_cmd = ["sharp", "-i", watermark_path.shellescape,
                      "-o", wm_temp.shellescape,
                      "ensureAlpha", alpha_value.to_s].join(" ")
          command_parts += ["composite", wm_temp.shellescape,
                            "--gravity", gravity, "--blend", "over"]
          "#{temp_cmd} && #{command_parts.join(' ')} " \
            "&& rm -f #{wm_temp.shellescape}"
        else
          command_parts += ["composite", watermark_path.shellescape,
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
        temp_path = input_path.gsub(/\.[^.]+$/, ".tmp_crop.jpg")

        # First command: crop only
        crop_cmd = build_crop_command(input_path, temp_path)

        # Second command: resize + format + quality + alpha (all together)
        resize_cmd = build_resize_command(temp_path, output_path)

        # Combine with && and cleanup temp file
        "#{crop_cmd} && #{resize_cmd} && rm -f #{temp_path.shellescape}"
      end

      def build_resize_command(input_path, output_path)
        resize_op = @operations.find { |op| op[:type] == :resize }

        # sharp -i input.jpg -o output.jpg resize width [height] -f format -q quality
        command_parts = ["sharp", "-i", input_path.shellescape, "-o", output_path.shellescape]

        # Add resize
        command_parts += if resize_op[:height]
                           ["resize", resize_op[:width].to_s, resize_op[:height].to_s]
                         else
                           ["resize", resize_op[:width].to_s]
                         end

        # Add format, quality, alpha
        format_op = @operations.find { |op| op[:type] == :format }
        quality_op = @operations.find { |op| op[:type] == :quality }
        alpha_op = @operations.find { |op| op[:type] == :alpha_opacity }

        command_parts += ["-f", format_op[:format]] if format_op
        command_parts += ["-q#{quality_op[:quality]}"] if quality_op
        if alpha_op
          alpha_value = (alpha_op[:opacity] * 255).round
          command_parts += ["alpha", "{alpha:#{alpha_value}}"]
        end

        command_parts.join(" ")
      end

      def build_crop_command(input_path, output_path)
        crop_op = @operations.find { |op| op[:type] == :crop }
        opts = crop_op[:options] || {}
        params = crop_op[:params] || {}

        # Check if we should use smartcrop (when keep parameter is specified)
        # JPT keep options: attention (default), entropy, center
        # Check both options (from CropTag) and params (from OperationProcessor)
        keep = opts[:keep] || params[:keep] || params[:position]

        if crop_op[:ratio] && keep && %w[attention entropy center
                                         centre].include?(keep.to_s)
          # Use smartcrop for intelligent cropping (Sharp uses libvips backend)
          crop_width = opts[:calculated_width]
          crop_height = opts[:calculated_height]

          # Map keep parameter to libvips interestingness
          interestingness = case keep.to_s
                            when "entropy" then "entropy"
                            when "center", "centre" then "centre"
                            else "attention" # default
                            end

          # sharp -i input.jpg -o output.jpg smartcrop width height --interesting=attention
          ["sharp", "-i", input_path.shellescape, "-o", output_path.shellescape,
           "smartcrop", crop_width.to_s, crop_height.to_s,
           "--interesting=#{interestingness}"].join(" ")
        else
          # Use basic extract for manual cropping or when no keep parameter
          crop_x = crop_op[:ratio] ? opts[:calculated_x] : (opts[:x] || 0)
          crop_y = crop_op[:ratio] ? opts[:calculated_y] : (opts[:y] || 0)
          crop_width = crop_op[:ratio] ? opts[:calculated_width] : opts[:width]
          crop_height = crop_op[:ratio] ? opts[:calculated_height] : opts[:height]

          # sharp -i input.jpg -o output.jpg extract top left width height
          ["sharp", "-i", input_path.shellescape, "-o", output_path.shellescape,
           "extract", crop_y.to_s, crop_x.to_s, crop_width.to_s, crop_height.to_s].join(" ")
        end
      end

      def build_copy_command(input_path, output_path)
        # sharp -i input.jpg -o output.jpg -f format -q quality
        command_parts = ["sharp", "-i", input_path.shellescape, "-o", output_path.shellescape]

        format_op = @operations.find { |op| op[:type] == :format }
        quality_op = @operations.find { |op| op[:type] == :quality }
        alpha_op = @operations.find { |op| op[:type] == :alpha_opacity }

        command_parts += ["-f", format_op[:format]] if format_op
        command_parts += ["-q#{quality_op[:quality]}"] if quality_op
        if alpha_op
          alpha_value = (alpha_op[:opacity] * 255).round
          command_parts += ["alpha", "{alpha:#{alpha_value}}"]
        end

        command_parts.join(" ")
      end
    end
  end
end
