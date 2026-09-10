# frozen_string_literal: true

require "open3"
require "fileutils"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Libvips provider implementation using the standardized tag interface
    class Libvips < BaseProvider
      def available?
        # Check if vips CLI is available
        _, _, status = Open3.capture3("which", "vips")
        status.success?
      end

      def execute(input_path, output_path)
        return if @operations.empty?

        # Build and execute vips commands (array form, no shell).
        # Cleanup markers ([:cleanup, path]) are handled by execute_command.
        commands = build_vips_commands(input_path, output_path)
        commands.each { |cmd_array| execute_command(cmd_array) }

        output_path
      ensure
        reset_operations
      end

      # Build all vips commands as an array of command arrays.
      # Each sub-array is passed directly to Open3.capture3 (no shell).
      # Returns Array[Array[String]].
      def build_vips_commands(input_path, output_path)
        has_crop = @operations.any? { |op| op[:type] == :crop }
        has_resize = @operations.any? { |op| op[:type] == :resize }
        has_watermark = @operations.any? { |op| op[:type] == :watermark }
        has_alpha = @operations.any? { |op| op[:type] == :alpha_opacity }

        if has_watermark
          build_watermark_pipeline(input_path, output_path, has_crop, has_resize)
        elsif has_alpha
          build_alpha_pipeline(input_path, output_path, has_crop, has_resize)
        elsif has_crop && has_resize
          build_sequential_crop_resize(input_path, output_path)
        elsif has_resize
          [build_resize_command(input_path, output_path)]
        elsif has_crop
          svg?(input_path) ? build_svg_crop_pipeline(input_path, output_path) : [build_crop_command(input_path, output_path)]
        else
          [build_copy_command(input_path, output_path)]
        end
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
        commands = []
        temp_path = input_path.gsub(/\.[^.]+$/, ".tmp_base.jpg")

        if has_crop && has_resize
          commands.concat(build_sequential_crop_resize(input_path, temp_path))
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

        commands << build_alpha_command(base_path, output_path)
        commands << [:cleanup, temp_path] unless base_path == input_path
        commands
      end

      def build_watermark_pipeline(input_path, output_path, has_crop, has_resize)
        temp_path = input_path.gsub(/\.[^.]+$/, ".tmp_base.jpg")

        commands = []

        # Step 1: Process crop/resize/copy to produce base image
        if has_crop && has_resize
          commands.concat(build_sequential_crop_resize(input_path, temp_path))
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

        # Step 2: Apply alpha opacity if present (before watermark)
        alpha_op = @operations.find { |op| op[:type] == :alpha_opacity }
        if alpha_op
          alpha_temp = input_path.gsub(/\.[^.]+$/, ".tmp_alpha.jpg")
          commands << build_alpha_command(base_path, alpha_temp)
          base_path = alpha_temp
        end

        # Step 3: Composite watermark over base
        commands.concat(build_composite_commands(base_path, output_path))

        # Step 4: Cleanup temp files
        temp_files = [temp_path, base_path == input_path ? nil : base_path].compact
        temp_files.each { |f| commands << [:cleanup, f] }

        commands
      end

      def build_composite_commands(base_path, output_path)
        wm_op = @operations.find { |op| op[:type] == :watermark }
        watermark_path = wm_op[:watermark_path]
        position = wm_op[:options][:position]
        opacity = wm_op[:options][:opacity]

        if opacity && opacity < 1.0
          wm_temp = watermark_path.gsub(/\.[^.]+$/, ".tmp_wm.png")
          alpha_value = opacity
          # Step 1: Apply alpha to watermark
          alpha_cmd = ["vips", "linear", watermark_path,
                       "#{wm_temp}[alpha]", "1 1 1 #{alpha_value}", "0"]
          # Step 2: Composite
          xy_args = position_to_vips_xy(position, base_path, watermark_path)
          composite_cmd = ["vips", "composite2", base_path, wm_temp,
                           build_format_spec(output_path), "over"] + xy_args
          # Step 3: Cleanup wm_temp
          [alpha_cmd, composite_cmd, [:cleanup, wm_temp]]
        else
          xy_args = position_to_vips_xy(position, base_path, watermark_path)
          [["vips", "composite2", base_path, watermark_path,
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
        alpha_op = @operations.find { |op| op[:type] == :alpha_opacity }
        opacity = alpha_op[:opacity]
        alpha_value = opacity.round(2)

        # vips linear multiplies alpha band: "1 1 1 alpha" scales alpha
        ["vips", "linear", input_path, output_path,
         "1 1 1 #{alpha_value}", "0"]
      end

      def build_sequential_crop_resize(input_path, output_path)
        if svg?(input_path)
          # SVG: use thumbnail with --crop to do crop+resize in one step
          resize_op = @operations.find { |op| op[:type] == :resize }
          format_spec = build_format_spec(output_path)
          width = resize_op[:width]
          height = resize_op[:height]
          [["vips", "thumbnail", input_path, format_spec,
            width.to_s, "--height=#{height}", "--crop=attention"]]
        else
          temp_path = input_path.gsub(/\.[^.]+$/, ".tmp_crop.jpg")
          [build_crop_command(input_path, temp_path),
           build_resize_command(temp_path, output_path),
           [:cleanup, temp_path]]
        end
      end

      def build_resize_command(input_path, output_path)
        resize_op = @operations.find { |op| op[:type] == :resize }
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
        crop_op = @operations.find { |op| op[:type] == :crop }
        opts = crop_op[:options] || {}
        params = crop_op[:params] || {}
        keep = opts[:keep] || params[:keep] || params[:position]

        if crop_op[:ratio] && keep && %w[attention entropy center
                                         centre].include?(keep.to_s)
          crop_width = opts[:calculated_width]
          crop_height = opts[:calculated_height]
          interestingness = case keep.to_s
                            when "entropy" then "entropy"
                            when "center", "centre" then "centre"
                            else "attention"
                            end
          ["vips", "smartcrop", input_path, output_path,
           crop_width.to_s, crop_height.to_s,
           "--interesting=#{interestingness}"]
        else
          crop_x = crop_op[:ratio] ? opts[:calculated_x] : (opts[:x] || 0)
          crop_y = crop_op[:ratio] ? opts[:calculated_y] : (opts[:y] || 0)
          crop_width = crop_op[:ratio] ? opts[:calculated_width] : opts[:width]
          crop_height = crop_op[:ratio] ? opts[:calculated_height] : opts[:height]
          ["vips", "extract_area", input_path, output_path,
           crop_x.to_s, crop_y.to_s, crop_width.to_s, crop_height.to_s]
        end
      end

      # SVG crop: use `vips thumbnail` with --crop to crop during thumbnailing.
      # This avoids the coordinate mismatch that occurs when rasterizing at a
      # different size than the SVG's viewBox (which caused "bad extract area").
      # thumbnail --crop uses smartcrop (attention/entropy/centre) to select
      # the most interesting region — this is the correct behavior for SVGs
      # since they have no fixed pixel dimensions.
      def build_svg_crop_pipeline(input_path, output_path)
        crop_op = @operations.find { |op| op[:type] == :crop }
        opts = crop_op[:options] || {}
        crop_width = crop_op[:ratio] ? opts[:calculated_width] : (opts[:width] || 1000)
        crop_height = crop_op[:ratio] ? opts[:calculated_height] : (opts[:height] || 1000)
        format_spec = build_format_spec(output_path)

        keep = opts[:keep] || crop_op[:params]&.[](:keep) || crop_op[:params]&.[](:position)
        interestingness = case keep.to_s
                          when "entropy" then "entropy"
                          when "center", "centre" then "centre"
                          else "attention"
                          end

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
        format_op = @operations.find { |op| op[:type] == :format }
        quality_op = @operations.find { |op| op[:type] == :quality }

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
