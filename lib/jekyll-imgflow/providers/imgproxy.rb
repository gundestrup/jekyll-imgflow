# frozen_string_literal: true

require "uri"
require "net/http"
require "tempfile"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Imgproxy provider implementation using the standardized tag interface
    class Imgproxy < BaseProvider
      TIMEOUT = 10 # seconds

      def available?
        # Check if imgproxy service is running
        return false unless @config.respond_to?(:imgproxy_url) && @config.imgproxy_url

        check_http_service(@config.imgproxy_url)
      end

      def execute(input_path, output_path)
        return if @operations.empty?

        # Build single Imgproxy URL with all operations combined
        url = build_combined_imgproxy_url(input_path)

        # Fetch the result in one request
        fetch_and_save(url, output_path)
        reset_operations
        output_path
      end

      def build_combined_imgproxy_url(input_path)
        raise "imgproxy_url not set" unless @config.imgproxy_url

        encoded_url = encode_file_url(input_path)
        operations = []

        # Add all operations to single URL path
        @operations.each do |operation|
          case operation[:type]
          when :resize
            # Tags now provide complete calculated values
            operations << if operation[:height]
                            "rs:fill:#{operation[:width]}:#{operation[:height]}:1"
                          else
                            "rs:fit:#{operation[:width]}::1"
                          end

          when :crop
            opts = operation[:options]
            params = operation[:params] || {}

            # Check for keep parameter (smartcrop support)
            keep = opts[:keep] || params[:keep] || params[:position]

            if operation[:ratio] && keep && SMARTCROP_POSITIONS.include?(keep.to_s)
              # Use smartcrop with gravity:sm (libvips smart crop)
              crop_width = opts[:calculated_width]
              crop_height = opts[:calculated_height]

              operations << "g:sm"
            else
              # Use basic cropping with explicit coordinates
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
              # imgproxy crop format: c:width:height:gravity
              # Use nowe (north-west) gravity with x/y offsets for pixel-precise cropping
              operations << "g:nowe:#{crop_x}:#{crop_y}"
            end
            operations << "c:#{crop_width}:#{crop_height}"

          when :quality
            imgproxy_quality = translate_quality_to_imgproxy(operation[:quality])
            operations << "q:#{imgproxy_quality}"

          when :format
            # Assume validated input from tags
            operations << "f:#{operation[:format]}"

          when :watermark
            watermark_path = operation[:watermark_path]
            position = operation[:options][:position]
            operation[:options][:opacity]

            # Imgproxy watermark parameters
            encoded_watermark = encode_file_url(watermark_path)
            position_param = translate_imgproxy_position(position)
            operations << "wm:#{encoded_watermark}:#{position_param}:10:10"

          when :alpha_opacity
            opacity = operation[:opacity]
            operations << "a:#{(opacity * 255).round}"
          end
        end

        # Preserve format when no explicit format operation is requested.
        # Without this, chained HTTP requests (e.g. quality-only steps after a
        # prior format conversion) would lose the previously converted format.
        unless @operations.any? { |op| op[:type] == :format }
          input_ext = File.extname(input_path).delete(".").downcase
          operations << "f:#{input_ext}" unless input_ext.empty?
        end

        # Build combined URL: base/insecure/operations/operations/.../plain/encoded_url
        operations_path = operations.join("/")
        "#{@config.imgproxy_url}/insecure/#{operations_path}/plain/#{encoded_url}"
      end

      private

      def translate_imgproxy_position(position)
        # Translate compass directions to Imgproxy position format
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
        raise "Imgproxy request failed" if response.empty?

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
        raise "Imgproxy request failed: #{e.message}"
      end

      def translate_quality_to_imgproxy(quality)
        quality
      end
    end
  end
end
