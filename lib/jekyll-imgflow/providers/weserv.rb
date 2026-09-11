# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Weserv provider implementation using the standardized tag interface
    class Weserv < HttpBase
      TIMEOUT = 30
      # SVGs without explicit pixel dimensions (e.g. width="100%") are valid
      # but cause librsvg to rasterize at the viewBox size, which can be huge.
      # When no resize operation is present, cap the rasterization at 2000px
      # on the longest edge so weserv processes the SVG at a reasonable size.
      SVG_DEFAULT_MAX_SIZE = 2000

      def service_url
        @config.respond_to?(:weserv_url) ? @config.weserv_url : nil
      end

      def build_combined_weserv_url(input_path)
        build_combined_url(input_path)
      end

      def build_combined_url(input_path)
        raise "weserv_url not set" unless service_url

        encoded_url = encode_file_url(input_path)
        params = ["url=#{URI.encode_www_form_component(encoded_url)}"]

        @operations.each { |operation| append_weserv_operation(operation, params) }

        ensure_svg_size_limit(input_path, params)

        "#{service_url}/?#{params.join('&')}"
      end

      private

      def ensure_svg_size_limit(input_path, params)
        return unless svg_file?(input_path)
        return if params.any? { |p| p.start_with?("w=", "h=", "crop=") || p.include?("cw=") }

        params << "w=#{SVG_DEFAULT_MAX_SIZE}"
      end

      def svg_file?(input_path)
        File.extname(input_path).downcase == ".svg"
      end

      def append_weserv_operation(operation, params)
        case operation[:type]
        when :resize
          params << if operation[:height]
                      "w=#{operation[:width]}&h=#{operation[:height]}&fit=fill"
                    else
                      "w=#{operation[:width]}"
                    end
        when :crop
          append_weserv_crop(operation, params)
        when :quality
          params << "q=#{operation[:quality]}"
        when :format
          params << "output=#{operation[:format]}"
        when :watermark
          append_weserv_watermark(operation, params)
        when :alpha_opacity
          params << "alpha=#{alpha_byte_value(operation[:opacity])}"
        end
      end

      def append_weserv_crop(operation, params)
        geo = crop_geometry(operation)

        if geo[:smartcrop]
          params << "crop=#{geo[:width]}x#{geo[:height]}"
          params << "a=smart"
          params << weserv_attention(geo[:keep])
        else
          params << "cx=#{geo[:x]}&cy=#{geo[:y]}&cw=#{geo[:width]}&ch=#{geo[:height]}"
        end
      end

      def weserv_attention(keep)
        case keep.to_s
        when "attention" then "a=attention"
        when "entropy" then "a=entropy"
        when "center", "centre" then "a=center"
        end
      end

      def append_weserv_watermark(operation, params)
        parts = watermark_parts(operation)
        params << "wm=#{encode_file_url(parts[:watermark_path])}"
        params << "wmpos=#{compass_to_short(parts[:position])}"
        params << "wmo=#{parts[:opacity]}" if parts[:opacity]
      end

      # Thin wrapper kept for test compatibility.
      def translate_weserv_position(position)
        compass_to_short(position)
      end
    end
  end
end
