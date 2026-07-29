# frozen_string_literal: true

require "shellwords"
require "open3"
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

        # Build single vips command with all operations
        command = build_vips_command(input_path, output_path)
        execute_command(command)

        reset_operations
        output_path
      end

      def build_vips_command(input_path, output_path)
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
          build_resize_command(input_path, output_path)
        elsif has_crop
          build_crop_command(input_path, output_path)
        else
          build_copy_command(input_path, output_path)
        end
      end

      def build_alpha_pipeline(input_path, output_path, has_crop, has_resize)
        commands = []
        temp_path = input_path.gsub(/\.[^.]+$/, ".tmp_base.jpg")

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

        commands << build_alpha_command(base_path, output_path)
        commands << "rm -f #{temp_path.shellescape}" unless base_path == input_path
        commands.join(" && ")
      end

      def build_watermark_pipeline(input_path, output_path, has_crop, has_resize)
        temp_path = input_path.gsub(/\.[^.]+$/, ".tmp_base.jpg")
        final_path = output_path

        commands = []

        # Step 1: Process crop/resize/copy to produce base image
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

        # Step 2: Apply alpha opacity if present (before watermark)
        alpha_op = @operations.find { |op| op[:type] == :alpha_opacity }
        if alpha_op
          alpha_temp = input_path.gsub(/\.[^.]+$/, ".tmp_alpha.jpg")
          commands << build_alpha_command(base_path, alpha_temp)
          base_path = alpha_temp
        end

        # Step 3: Composite watermark over base
        commands << build_composite_command(base_path, final_path)

        # Step 4: Cleanup temp files
        temp_files = [temp_path, base_path == input_path ? nil : base_path].compact
        temp_files.each { |f| commands << "rm -f #{f.shellescape}" }

        commands.join(" && ")
      end

      def build_composite_command(base_path, output_path)
        wm_op = @operations.find { |op| op[:type] == :watermark }
        watermark_path = wm_op[:watermark_path]
        position = wm_op[:options][:position]
        opacity = wm_op[:options][:opacity]
        format_spec = build_format_spec(output_path)

        if opacity && opacity < 1.0
          wm_temp = watermark_path.gsub(/\.[^.]+$/, ".tmp_wm.png")
          alpha_value = opacity
          temp_cmd = ["vips", "linear", watermark_path.shellescape,
                      "'#{wm_temp}[alpha]'", "\"1 1 1 #{alpha_value}\"", "0"].join(" ")
          full_cmd = ["#{temp_cmd} && vips composite2",
                      base_path.shellescape, wm_temp.shellescape,
                      format_spec, "over",
                      position_to_vips_xy(position, base_path, watermark_path)].join(" ")
          # Add cleanup
          "#{full_cmd} && rm -f #{wm_temp.shellescape}"
        else
          ["vips", "composite2", base_path.shellescape,
           watermark_path.shellescape, format_spec, "over",
           position_to_vips_xy(position, base_path, watermark_path)].join(" ")
        end
      end

      def position_to_vips_xy(position, _base_path, watermark_path)
        # Get image dimensions to calculate x/y from compass positions
        # vips composite2 uses --x and --y for overlay placement
        case position.to_s
        when "northeast", "top-right"
          # Need watermark width; use shell substitution
          "--x $(vips header #{watermark_path.shellescape} width) --y 0"
        when "southwest", "bottom-left"
          "--x 0 --y $(vips header #{watermark_path.shellescape} height)"
        when "southeast", "bottom-right"
          "--x $(vips header #{watermark_path.shellescape} width) " \
          "--y $(vips header #{watermark_path.shellescape} height)"
        else
          "--x 0 --y 0" # northwest, top-left, center, centre, and default
        end
      end

      def build_alpha_command(input_path, output_path)
        alpha_op = @operations.find { |op| op[:type] == :alpha_opacity }
        opacity = alpha_op[:opacity]
        alpha_value = opacity.round(2)

        # vips linear multiplies alpha band: "1 1 1 alpha" scales alpha
        ["vips", "linear", input_path.shellescape, output_path.shellescape,
         "\"1 1 1 #{alpha_value}\"", "0"].join(" ")
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
        resize_data = resize_op[:options] || {}

        if resize_op[:width] && resize_op[:height]
          # Both dimensions specified - use VipsResize with vscale for exact dimensions
          # ResizeTag has already done the calculations, so we use both scale factors
          scale_x = resize_data[:scale_x]
          scale_y = resize_data[:scale_y]
          format_spec = build_format_spec(output_path)

          # Only add vscale if we have both scale factors
          if scale_x && scale_y
            ["vips", "VipsResize", input_path.shellescape, format_spec,
             scale_x.to_s, "--vscale=#{scale_y}"].join(" ")
          else
            # Fallback to scale_x only if scale_y is missing
            ["vips", "VipsResize", input_path.shellescape, format_spec,
             (scale_x || 1.0).to_s].join(" ")
          end
        else
          # Only one dimension - use VipsResize with scale_x (maintain aspect ratio)
          scale_x = resize_data[:scale_x] || 1.0
          format_spec = build_format_spec(output_path)
          ["vips", "VipsResize", input_path.shellescape, format_spec, scale_x.to_s].join(" ")
        end
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
          # Use libvips smartcrop for intelligent cropping
          crop_width = opts[:calculated_width]
          crop_height = opts[:calculated_height]

          # Map keep parameter to libvips interestingness
          interestingness = case keep.to_s
                            when "entropy" then "entropy"
                            when "center", "centre" then "centre"
                            else "attention" # default
                            end

          # vips smartcrop input.jpg output.jpg width height --interesting=attention
          ["vips", "smartcrop", input_path.shellescape, output_path.shellescape,
           crop_width.to_s, crop_height.to_s,
           "--interesting=#{interestingness}"].join(" ")
        else
          # Use basic extract_area for manual cropping or when no keep parameter
          crop_x = crop_op[:ratio] ? opts[:calculated_x] : (opts[:x] || 0)
          crop_y = crop_op[:ratio] ? opts[:calculated_y] : (opts[:y] || 0)
          crop_width = crop_op[:ratio] ? opts[:calculated_width] : opts[:width]
          crop_height = crop_op[:ratio] ? opts[:calculated_height] : opts[:height]

          # vips extract_area input.jpg output.jpg left top width height
          ["vips", "extract_area", input_path.shellescape, output_path.shellescape,
           crop_x.to_s, crop_y.to_s, crop_width.to_s, crop_height.to_s].join(" ")
        end
      end

      def build_copy_command(input_path, output_path)
        # vips copy input.jpg output.jpg[format]
        format_spec = build_format_spec(output_path)
        ["vips", "copy", input_path.shellescape, format_spec].join(" ")
      end

      def build_format_spec(output_path)
        # Build vips output specification with format and quality
        format_op = @operations.find { |op| op[:type] == :format }
        quality_op = @operations.find { |op| op[:type] == :quality }

        # Simple case: no format/quality operations
        return output_path.shellescape unless format_op || quality_op

        # Extract format from operation or output path
        ext = format_op ? format_op[:format] : File.extname(output_path).delete(".")
        base = output_path.gsub(/\.[^.]+$/, "")

        # Build format spec with quality if present
        # Use single quotes to preserve bracket syntax (shellescape breaks it)
        if quality_op
          quality = quality_op[:quality]
          "'#{base}.#{ext}[Q=#{quality}]'"
        else
          "'#{base}.#{ext}'"
        end
      end

      def execute_command(command)
        Jekyll.logger.debug "LibVips command: #{command}"

        # Execute command and capture output
        stdout, stderr, status = Open3.capture3(command)
        output = "#{stdout}#{stderr}"
        success = status.success?

        unless success
          # Filter out expected warnings and only log real errors
          raise "LibVips command failed: #{command}\nError: #{output}" unless output.include?("same file") || output.include?("VipsForeignSave")

          Jekyll.logger.warn "LibVips warning: #{output.strip}"
          return output.strip # Continue despite warnings

        end

        output.strip
      end
    end
  end
end
