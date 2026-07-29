# frozen_string_literal: true

require "net/http"
require "uri"
require "tempfile"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Weserv provider implementation using the standardized tag interface
    class Weserv < BaseProvider
      TIMEOUT = 10

      def available?
        # Check if weserv service is running
        return false unless @config.respond_to?(:weserv_url) && @config.weserv_url

        check_http_service(@config.weserv_url)
      end

      def execute(input_path, output_path)
        return if @operations.empty?

        # Build single Weserv URL with all operations combined
        url = build_combined_weserv_url(input_path)

        # Fetch the result in one request
        fetch_and_save(url, output_path)
        reset_operations
        output_path
      end

      def build_combined_weserv_url(input_path)
        raise "weserv_url not set" unless @config.weserv_url

        encoded_url = encode_file_url(input_path)
        params = ["url=#{URI.encode_www_form_component(encoded_url)}"]

        # Add all operations to single URL
        @operations.each do |operation|
          case operation[:type]
          when :resize
            # Tags now provide complete calculated values
            params << if operation[:height]
                        "w=#{operation[:width]}&h=#{operation[:height]}&fit=fill"
                      else
                        "w=#{operation[:width]}"
                      end

          when :crop
            opts = operation[:options]
            op_params = operation[:params] || {}

            # Check for keep parameter (smartcrop support)
            keep = opts[:keep] || op_params[:keep] || op_params[:position]

            if operation[:ratio] && keep && SMARTCROP_POSITIONS.include?(keep.to_s)
              # Use smartcrop (WeServ supports smartcrop)
              crop_width = opts[:calculated_width]
              crop_height = opts[:calculated_height]

              # Add smartcrop parameters according to WeServ docs
              params << "crop=#{crop_width}x#{crop_height}"
              params << "a=smart" # smart attention

              # Map keep parameter to WeServ attention type
              case keep.to_s
              when "attention" then params << "a=attention"
              when "entropy" then params << "a=entropy"
              when "center", "centre" then params << "a=center"
              end
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
              params << "cx=#{crop_x}&cy=#{crop_y}&cw=#{crop_width}&ch=#{crop_height}"
            end

          when :quality
            weserv_quality = translate_quality_to_weserv(operation[:quality])
            params << "q=#{weserv_quality}"

          when :format
            # Assume validated input from tags
            params << "output=#{operation[:format]}"

          when :watermark
            watermark_path = operation[:watermark_path]
            position = operation[:options][:position]
            opacity = operation[:options][:opacity]

            # Weserv watermark parameters
            params << "wm=#{encode_file_url(watermark_path)}"
            params << "wmpos=#{translate_weserv_position(position)}"
            params << "wmo=#{opacity}" if opacity

          when :alpha_opacity
            opacity = operation[:opacity]
            params << "alpha=#{(opacity * 255).round}"
          end
        end

        query_string = params.join("&")
        "#{@config.weserv_url}/?#{query_string}"
      end

      private

      def translate_weserv_position(position)
        # Translate compass directions to Weserv position format
        case position
        when "northwest" then "tl"
        when "northeast" then "tr"
        when "southwest" then "bl"
        when "southeast" then "br"
        when "center" then "c"
        else position
        end
      end

      def fetch_and_save(url, output_path)
        response = fetch_with_timeout(url)
        raise "Weserv request failed" if response.empty?

        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, response)
      end

      def fetch_with_timeout(url)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port,
                        use_ssl: uri.scheme == "https",
                        open_timeout: TIMEOUT,
                        read_timeout: TIMEOUT) do |http|
          request = Net::HTTP::Get.new(uri)
          response = http.request(request)

          raise "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

          response.body
        end
      rescue StandardError => e
        raise "Weserv request failed: #{e.message}"
      end

      def translate_quality_to_weserv(quality)
        quality
      end
    end
  end
end
