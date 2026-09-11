# frozen_string_literal: true

require "uri"
require "net/http"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Imgproxy provider implementation using the standardized tag interface
    class Imgproxy < HttpBase
      TIMEOUT = 10 # seconds

      def service_url
        @config.respond_to?(:imgproxy_url) ? @config.imgproxy_url : nil
      end

      def build_combined_imgproxy_url(input_path)
        build_combined_url(input_path)
      end

      def build_combined_url(input_path)
        raise "imgproxy_url not set" unless service_url

        encoded_url = encode_file_url(input_path)
        operations = []

        @operations.each { |operation| append_imgproxy_operation(operation, operations) }

        preserve_input_format(input_path, operations)
        operations_path = operations.join("/")
        "#{service_url}/insecure/#{operations_path}/plain/#{encoded_url}"
      end

      private

      def append_imgproxy_operation(operation, operations)
        case operation[:type]
        when :resize
          operations << if operation[:height]
                          "rs:fill:#{operation[:width]}:#{operation[:height]}:1"
                        else
                          "rs:fit:#{operation[:width]}::1"
                        end
        when :crop
          append_imgproxy_crop(operation, operations)
        when :quality
          operations << "q:#{operation[:quality]}"
        when :format
          operations << "f:#{operation[:format]}"
        when :watermark
          append_imgproxy_watermark(operation, operations)
        when :alpha_opacity
          operations << "a:#{alpha_byte_value(operation[:opacity])}"
        end
      end

      def append_imgproxy_crop(operation, operations)
        geo = crop_geometry(operation)

        operations << if geo[:smartcrop]
                        # Use smartcrop with gravity:sm (libvips smart crop)
                        "g:sm"
                      else
                        # imgproxy crop format: c:width:height:gravity
                        # Use nowe (north-west) gravity with x/y offsets for pixel-precise cropping
                        "g:nowe:#{geo[:x]}:#{geo[:y]}"
                      end
        operations << "c:#{geo[:width]}:#{geo[:height]}"
      end

      def append_imgproxy_watermark(operation, operations)
        parts = watermark_parts(operation)
        encoded_watermark = encode_file_url(parts[:watermark_path])
        position_param = compass_to_short(parts[:position])
        operations << "wm:#{encoded_watermark}:#{position_param}:10:10"
      end

      def preserve_input_format(input_path, operations)
        return if op?(:format)

        ext = input_format_ext(input_path)
        operations << "f:#{ext}" unless ext.empty?
      end

      # Thin wrapper kept for test compatibility.
      def translate_imgproxy_position(position)
        compass_to_short(position)
      end
    end
  end
end
