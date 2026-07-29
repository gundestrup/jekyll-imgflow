# frozen_string_literal: true

require "net/http"
require "uri"
require "tempfile"
require_relative "base_provider"

module JekyllImgFlow
  module Providers
    # Flyimg provider implementation using the standardized tag interface
    class Flyimg < BaseProvider
      TIMEOUT = 10

      def available?
        # Check if flyimg service is running
        return false unless @config.respond_to?(:flyimg_url) && @config.flyimg_url

        check_http_service(@config.flyimg_url)
      end

      def execute(input_path, output_path)
        return if @operations.empty?

        # Build single Flyimg URL with all operations combined
        url = build_combined_flyimg_url(input_path)

        # Fetch the result in one request
        fetch_and_save(url, output_path)
        reset_operations
        output_path
      end

      def build_combined_flyimg_url(input_path)
        raise "flyimg_url not set" unless @config.flyimg_url

        encoded_url = encode_file_url(input_path)
        options = []

        # Add all operations to single options string
        @operations.each do |operation|
          case operation[:type]
          when :resize
            # Tags now provide complete calculated values.
            # c_1 forces the image to fill the exact width x height area.
            # pns_0 allows upscaling when the source is smaller than the target
            # (Flyimg's pns/preserve-natural-size defaults to 1, blocking enlarge).
            options << "w_#{operation[:width]}"
            options << "pns_0"
            if operation[:height]
              options << "h_#{operation[:height]}"
              options << "c_1"
            end

          when :crop
            opts = operation[:options]
            params = operation[:params] || {}

            # Check for keep parameter (smartcrop support)
            keep = opts[:keep] || params[:keep] || params[:position]

            if operation[:ratio] && keep && SMARTCROP_POSITIONS.include?(keep.to_s)
              # Use smartcrop (Flyimg's smc option picks the best crop area)
              crop_width = opts[:calculated_width]
              crop_height = opts[:calculated_height]

              options << "w_#{crop_width}"
              options << "h_#{crop_height}"
              options << "c_1"
              options << "smc_1"
            else
              # Use basic cropping via extract (top-left / bottom-right coordinates)
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
              options << "e_1"
              options << "p1x_#{crop_x}"
              options << "p1y_#{crop_y}"
              options << "p2x_#{crop_x + crop_width}"
              options << "p2y_#{crop_y + crop_height}"
            end

          when :quality
            flyimg_quality = translate_quality_to_flyimg(operation[:quality])
            options << "q_#{flyimg_quality}"

          when :format
            # Assume validated input from tags
            options << "o_#{operation[:format]}"

          when :watermark
            watermark_path = operation[:watermark_path]
            position = operation[:options][:position]
            opacity = operation[:options][:opacity]

            # Flyimg watermark parameters
            encoded_watermark = encode_file_url(watermark_path)
            position_param = translate_flyimg_position(position)
            opacity_param = (opacity * 100).round
            options << "wm_#{encoded_watermark}_#{position_param}_#{opacity_param}"

          when :alpha_opacity
            opacity = operation[:opacity]
            options << "a_#{(opacity * 255).round}"
          end
        end

        # Preserve format when no explicit format operation is requested.
        # Without this, chained HTTP requests (e.g. quality-only steps after a
        # prior format conversion) would lose the previously converted format.
        unless @operations.any? { |op| op[:type] == :format }
          input_ext = File.extname(input_path).delete(".").downcase
          options << "o_#{map_format(input_ext)}" unless input_ext.empty?
        end

        # Build combined URL: base/upload/options/options,.../encoded_url
        options_string = options.join(",")
        "#{@config.flyimg_url}/upload/#{options_string}/#{encoded_url}"
      end

      private

      def translate_flyimg_position(position)
        # Translate compass directions to Flyimg position format
        case position
        when "northwest" then "tl"
        when "northeast" then "tr"
        when "southwest" then "bl"
        when "southeast" then "br"
        when "center" then "c"
        else position
        end
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

      def fetch_and_save(url, output_path)
        response = fetch_with_timeout(url)
        raise "Flyimg request failed" if response.empty?

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
        raise "Flyimg request failed: #{e.message}"
      end

      def translate_quality_to_flyimg(quality)
        quality
      end
    end
  end
end
