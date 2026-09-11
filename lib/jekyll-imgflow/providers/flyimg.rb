# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Flyimg provider implementation using the standardized tag interface
    class Flyimg < HttpBase
      TIMEOUT = 60

      def service_url
        @config.respond_to?(:flyimg_url) ? @config.flyimg_url : nil
      end

      def build_combined_flyimg_url(input_path)
        build_combined_url(input_path)
      end

      def build_combined_url(input_path)
        raise "flyimg_url not set" unless service_url

        encoded_url = encode_file_url(input_path)
        options = []

        @operations.each { |operation| append_flyimg_operation(operation, options) }

        preserve_input_format(input_path, options)
        "#{service_url}/upload/#{options.join(',')}/#{encoded_url}"
      end

      private

      def append_flyimg_operation(operation, options)
        case operation[:type]
        when :resize
          append_flyimg_resize(operation, options)
        when :crop
          append_flyimg_crop(operation, options)
        when :quality
          options << "q_#{operation[:quality]}"
        when :format
          options << "o_#{operation[:format]}"
        when :watermark
          append_flyimg_watermark(operation, options)
        when :alpha_opacity
          options << "a_#{alpha_byte_value(operation[:opacity])}"
        end
      end

      def append_flyimg_resize(operation, options)
        # c_1 forces the image to fill the exact width x height area.
        # pns_0 allows upscaling when the source is smaller than the target
        # (Flyimg's pns/preserve-natural-size defaults to 1, blocking enlarge).
        options << "w_#{operation[:width]}"
        options << "pns_0"
        return unless operation[:height]

        options << "h_#{operation[:height]}"
        options << "c_1"
      end

      def append_flyimg_crop(operation, options)
        geo = crop_geometry(operation)

        if geo[:smartcrop]
          options << "w_#{geo[:width]}"
          options << "h_#{geo[:height]}"
          options << "c_1"
          options << "smc_1"
        else
          # Use basic cropping via extract (top-left / bottom-right coordinates)
          options << "e_1"
          options << "p1x_#{geo[:x]}"
          options << "p1y_#{geo[:y]}"
          options << "p2x_#{geo[:x] + geo[:width]}"
          options << "p2y_#{geo[:y] + geo[:height]}"
        end
      end

      def append_flyimg_watermark(operation, options)
        parts = watermark_parts(operation)
        encoded_watermark = encode_file_url(parts[:watermark_path])
        position_param = compass_to_short(parts[:position])
        opacity_param = (parts[:opacity] * 100).round
        options << "wm_#{encoded_watermark}_#{position_param}_#{opacity_param}"
      end

      def preserve_input_format(input_path, options)
        return if op?(:format)

        ext = input_format_ext(input_path)
        options << "o_#{map_format(ext)}" unless ext.empty?
      end

      def map_format(format)
        case format&.downcase
        when "jpeg", "jpg"
          "jpg"
        when "png"
          "png"
        when "webp"
          "webp"
        when "gif"
          "gif"
        else
          format&.downcase || format
        end
      end

      # Thin wrapper kept for test compatibility.
      def translate_flyimg_position(position)
        compass_to_short(position)
      end
    end
  end
end
