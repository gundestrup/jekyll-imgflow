# frozen_string_literal: true

require "open3"
require "fileutils"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Libvips provider implementation using the standardized tag interface
    class Libvips < CliBase
      def available?
        cli_available?("vips")
      end

      def build_commands(input_path, output_path)
        build_vips_commands(input_path, output_path)
      end

      def run_command(cmd)
        execute_command(cmd)
      end

      # Build all vips commands as an array of command arrays.
      # Each sub-array is passed directly to Open3.capture3 (no shell).
      # Returns Array[Array[String]].
      def build_vips_commands(input_path, output_path)
        flags = operation_flags
        operation_builder = select_operation_builder(flags)
        operation_builder.call(input_path, output_path)
      end

      def select_operation_builder(flags)
        return ->(input, output) { build_watermark_pipeline(input, output, flags[:crop], flags[:resize]) } if flags[:watermark]
        return ->(input, output) { build_alpha_pipeline(input, output, flags[:crop], flags[:resize]) } if flags[:alpha]
        return ->(input, output) { build_sequential_crop_resize(input, output) } if flags[:crop] && flags[:resize]
        return ->(input, output) { [build_resize_command(input, output)] } if flags[:resize]
        return ->(input, output) { crop_commands(input, output) } if flags[:crop]

        ->(input, output) { [build_copy_command(input, output)] }
      end

      def operation_flags
        {
          crop: op?(:crop),
          resize: op?(:resize),
          watermark: op?(:watermark),
          alpha: op?(:alpha_opacity)
        }
      end

      def crop_commands(input_path, output_path)
        svg?(input_path) ? build_svg_crop_pipeline(input_path, output_path) : [build_crop_command(input_path, output_path)]
      end

      # Convenience wrapper for backward compatibility with tests.
      # Returns the commands joined as a debug string.
      def build_vips_command(input_path, output_path)
        build_vips_commands(input_path, output_path).map do |cmd|
          if cmd.is_a?(Array) && cmd.first == :cleanup
            "rm -f #{cmd[1]}"
          else
            cmd.join(" ")
          end
        end.join(" && ")
      end

      def build_alpha_pipeline(input_path, output_path, has_crop, has_resize)
        temp = temp_path(input_path, "tmp_base.jpg")
        commands, base_path = build_base_pipeline(input_path, temp, has_crop, has_resize)
        commands << build_alpha_command(base_path, output_path)
        commands << [:cleanup, temp] unless base_path == input_path
        commands
      end

      def build_watermark_pipeline(input_path, output_path, has_crop, has_resize)
        temp = temp_path(input_path, "tmp_base.jpg")
        commands, base_path = build_base_pipeline(input_path, temp, has_crop, has_resize)
        base_path, commands = apply_watermark_alpha(base_path, input_path, commands)
        commands.concat(build_composite_commands(base_path, output_path))
        cleanup_paths(commands, input_path, temp, base_path)
        commands
      end

      def build_base_pipeline(input_path, temp_path, has_crop, has_resize)
        return [build_sequential_crop_resize(input_path, temp_path), temp_path] if has_crop && has_resize
        return [[build_resize_command(input_path, temp_path)], temp_path] if has_resize
        return [[build_crop_command(input_path, temp_path)], temp_path] if has_crop

        [[], input_path]
      end

      def apply_watermark_alpha(base_path, input_path, commands)
        alpha_op = find_op(:alpha_opacity)
        return [base_path, commands] unless alpha_op

        alpha_temp = temp_path(input_path, "tmp_alpha.jpg")
        [alpha_temp, commands << build_alpha_command(base_path, alpha_temp)]
      end

      def cleanup_paths(commands, input_path, temp_path, base_path)
        temp_files = [temp_path, base_path == input_path ? nil : base_path].compact
        temp_files.each { |file| commands << [:cleanup, file] }
      end

      def build_composite_commands(base_path, output_path)
        wm_op = find_op(:watermark)
        parts = watermark_parts(wm_op)

        if parts[:opacity] && parts[:opacity] < 1.0
          wm_temp = temp_path(parts[:watermark_path], "tmp_wm.png")
          alpha_value = parts[:opacity]
          # Step 1: Apply alpha to watermark
          alpha_cmd = ["vips", "linear", parts[:watermark_path],
                       "#{wm_temp}[alpha]", "1 1 1 #{alpha_value}", "0"]
          # Step 2: Composite
          xy_args = position_to_vips_xy(parts[:position], base_path, parts[:watermark_path])
          composite_cmd = ["vips", "composite2", base_path, wm_temp,
                           build_format_spec(output_path), "over"] + xy_args
          # Step 3: Cleanup wm_temp
          [alpha_cmd, composite_cmd, [:cleanup, wm_temp]]
        else
          xy_args = position_to_vips_xy(parts[:position], base_path, parts[:watermark_path])
          [["vips", "composite2", base_path, parts[:watermark_path],
            build_format_spec(output_path), "over"] + xy_args]
        end
      end

      # Return x/y arguments as an array of strings (no shell substitution).
      # Pre-computes image dimensions via vips header in Ruby.
      def position_to_vips_xy(position, _base_path, watermark_path)
        case position.to_s
        when "northeast", "top-right"
          width = vips_image_dimension(watermark_path, "width")
          ["--x", width.to_s, "--y", "0"]
        when "southwest", "bottom-left"
          height = vips_image_dimension(watermark_path, "height")
          ["--x", "0", "--y", height.to_s]
        when "southeast", "bottom-right"
          width = vips_image_dimension(watermark_path, "width")
          height = vips_image_dimension(watermark_path, "height")
          ["--x", width.to_s, "--y", height.to_s]
        else
          ["--x", "0", "--y", "0"] # northwest, top-left, center, centre, and default
        end
      end

      # Get an image dimension (width or height) using vips header.
      # Returns integer or 0 if vips is unavailable.
      def vips_image_dimension(image_path, field)
        return 0 unless %w[width height].include?(field)

        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec -- Open3 receives an argument array and field is allowlisted.
        stdout, _, status = Open3.capture3("vips", "header", image_path, field)
        return 0 unless status.success?

        stdout.strip.to_i
      rescue StandardError
        0
      end

      def build_alpha_command(input_path, output_path)
        alpha_op = find_op(:alpha_opacity)
        alpha_value = alpha_op[:opacity].round(2)

        # vips linear multiplies alpha band: "1 1 1 alpha" scales alpha
        ["vips", "linear", input_path, output_path,
         "1 1 1 #{alpha_value}", "0"]
      end

      def build_sequential_crop_resize(input_path, output_path)
        if svg?(input_path)
          # SVG: use thumbnail with --crop to do crop+resize in one step
          resize_op = find_op(:resize)
          format_spec = build_format_spec(output_path)
          width = resize_op[:width]
          height = resize_op[:height]
          [["vips", "thumbnail", input_path, format_spec,
            width.to_s, "--height=#{height}", "--crop=attention"]]
        else
          temp = temp_path(input_path, "tmp_crop.jpg")
          [build_crop_command(input_path, temp),
           build_resize_command(temp, output_path),
           [:cleanup, temp]]
        end
      end

      def build_resize_command(input_path, output_path)
        resize_op = find_op(:resize)
        format_spec = build_format_spec(output_path)
        width = resize_op[:width]
        height = resize_op[:height]

        # Use `vips thumbnail` for all resize operations. thumbnail is the
        # recommended high-level resize API — it uses shrink-on-load for
        # JPEGs (efficient), handles SVGs safely by bounding render size
        # during load, and supports all image formats.
        # See https://www.libvips.org/API/current/func.thumbnail.html
        if width && height
          # Both dimensions: thumbnail to width, cap height, crop to fill
          ["vips", "thumbnail", input_path, format_spec,
           width.to_s, "--height=#{height}", "--crop=attention"]
        else
          # Only width: thumbnail maintains aspect ratio
          ["vips", "thumbnail", input_path, format_spec, width.to_s]
        end
      end

      def build_crop_command(input_path, output_path)
        crop_op = find_op(:crop)
        geo = crop_geometry(crop_op)
        return build_smartcrop_command(geo, input_path, output_path) if geo[:smartcrop]

        build_extract_command(geo, input_path, output_path)
      end

      def build_smartcrop_command(geo, input_path, output_path)
        interestingness = smartcrop_interestingness(geo[:keep])
        ["vips", "smartcrop", input_path, output_path,
         geo[:width].to_s, geo[:height].to_s,
         "--interesting=#{interestingness}"]
      end

      def build_extract_command(geo, input_path, output_path)
        ["vips", "extract_area", input_path, output_path,
         geo[:x].to_s, geo[:y].to_s, geo[:width].to_s, geo[:height].to_s]
      end

      # SVG crop: use `vips thumbnail` with --crop to crop during thumbnailing.
      # This avoids the coordinate mismatch that occurs when rasterizing at a
      # different size than the SVG's viewBox (which caused "bad extract area").
      # thumbnail --crop uses smartcrop (attention/entropy/centre) to select
      # the most interesting region — this is the correct behavior for SVGs
      # since they have no fixed pixel dimensions.
      def build_svg_crop_pipeline(input_path, output_path)
        crop_op = find_op(:crop)
        geo = crop_geometry(crop_op)
        crop_width = geo[:width] || 1000
        crop_height = geo[:height] || 1000
        format_spec = build_format_spec(output_path)
        interestingness = smartcrop_interestingness(geo[:keep])

        [["vips", "thumbnail", input_path, format_spec,
          crop_width.to_s, "--height=#{crop_height}",
          "--crop=#{interestingness}"]]
      end

      def build_copy_command(input_path, output_path)
        format_spec = build_format_spec(output_path)
        # For SVGs, `vips copy` rasterizes at intrinsic size (potentially
        # huge). Use thumbnail with a large cap to bound the render safely.
        return ["vips", "thumbnail", input_path, format_spec, "2000"] if svg?(input_path)

        # vips copy input.jpg output.jpg[format]
        ["vips", "copy", input_path, format_spec]
      end

      # Build vips output specification with format and quality.
      # Returns a raw string — no shell quoting needed since commands
      # are executed via Open3.capture3 array form (no shell).
      def build_format_spec(output_path)
        # Build vips output specification with format and quality
        format_op = find_op(:format)
        quality_op = find_op(:quality)

        # Simple case: no format/quality operations
        return output_path unless format_op || quality_op

        # Extract format from operation or output path
        ext = format_op ? format_op[:format] : File.extname(output_path).delete(".")
        base = output_path.gsub(/\.[^.]+$/, "")

        # Build format spec with quality if present
        if quality_op
          quality = quality_op[:quality]
          "#{base}.#{ext}[Q=#{quality}]"
        else
          "#{base}.#{ext}"
        end
      end

      # Execute a command array via Open3.capture3 (no shell invocation).
      # @param command [Array<String>] Command and arguments as array
      def execute_command(command)
        if command.is_a?(Array) && command.first == :cleanup
          FileUtils.rm_f(command[1])
          return
        end

        Jekyll.logger.debug "LibVips command: #{command.join(' ')}"

        # Execute command array directly (no shell)
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec -- command is an argument array; no shell is invoked.
        stdout, stderr, status = Open3.capture3(*command)
        output = "#{stdout}#{stderr}"
        success = status.success?

        unless success
          cmd_str = command.join(" ")
          # Filter out expected warnings and only log real errors
          raise "LibVips command failed: #{cmd_str}\nError: #{output}" unless output.include?("same file") || output.include?("VipsForeignSave")

          Jekyll.logger.warn "LibVips warning: #{output.strip}"
          return output.strip # Continue despite warnings

        end

        output.strip
      end
    end
  end
end
