# frozen_string_literal: true

require "English"
require "open3"
require "pathname"

module JekyllImgFlow
  module Providers
    # Base provider class - all providers must inherit from this
    class BaseProvider
      # Valid smartcrop position values
      SMARTCROP_POSITIONS = %w[attention entropy center centre].freeze

      attr_accessor :config

      def initialize(config = {})
        @config = config
        @operations = []
      end

      # Check if this provider is available (must be implemented by subclasses)
      def available?
        # Default: not available unless subclass implements actual check
        # This ensures providers explicitly check their availability
        false
      end

      # Helper method for HTTP providers to check service availability
      def check_http_service(url)
        return false unless url

        begin
          require "net/http"
          require "uri"

          uri = URI(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.read_timeout = 2
          http.open_timeout = 2

          request = Net::HTTP::Get.new(uri)
          http.request(request)

          # Consider available if we get any response (even 404 means service is running)
          true
        rescue StandardError
          false
        end
      end

      # Helper method for HTTP providers to construct HTTP URLs from file paths
      def encode_file_url(file_path)
        # If already a URL, return as-is
        return file_path if file_path.start_with?("http://", "https://")

        # For HTTP providers, construct proper HTTP URL
        site = @config.site

        # Get the relative path from site source using Pathname
        source_path = Pathname.new(site.source)
        file_pathname = Pathname.new(file_path)
        relative_path = if file_pathname.absolute? && file_path.to_s.start_with?(site.source)
                          file_pathname.relative_path_from(source_path).to_s
                        elsif file_path.start_with?("/")
                          file_path[1..]
                        else
                          file_path
                        end

        # URL-encode each path segment to handle spaces and special characters
        encoded_path = relative_path.split("/").map do |segment|
          URI.encode_www_form_component(segment)
        end.join("/")

        # Construct HTTP URL for the file
        # Use Jekyll server URL (localhost:4000 by default for development)
        # In production, this would be the actual site URL from config
        base_url = site.config["url"] || "http://localhost:4000"
        baseurl = site.config["baseurl"] || ""

        "#{base_url}#{baseurl}/#{encoded_path}"
      end

      # Operation collection methods - these should NOT execute immediately
      def resize(width, height, options = {})
        @operations << { type: :resize, width: width, height: height,
                         options: options }
      end

      def crop(ratio_or_width, height_val = nil, x_val = nil, y_val = nil)
        if height_val.is_a?(Hash)
          @operations << { type: :crop, ratio: ratio_or_width, options: height_val }
        elsif height_val
          options = { width: ratio_or_width, height: height_val, x: x_val, y: y_val }
          @operations << options.merge(type: :crop, ratio: nil, options: options)
        else
          @operations << { type: :crop, ratio: ratio_or_width, options: {} }
        end
      end

      def quality=(quality)
        @operations << { type: :quality, quality: quality }
      end

      def convert_format(format)
        @operations << { type: :format, format: format }
      end

      def quality(value)
        self.quality = value
      end

      def format(value)
        convert_format(value)
      end

      def optimize(level = :medium)
        @operations << { type: :optimize, level: level }
      end

      def opacity(value)
        self.alpha_opacity = value
      end

      def add_watermark(watermark_path, options = {})
        @operations << { type: :watermark, watermark_path: watermark_path,
                         options: options }
      end

      def alpha_opacity=(opacity)
        @operations << { type: :alpha_opacity, opacity: opacity }
      end

      def watermark(watermark_path, options = {})
        add_watermark(watermark_path, options)
      end

      def supports_operation?(operation)
        self.class.supports_operation?(operation)
      end

      # Final execution method - providers must implement this
      def execute(input_path, output_path)
        raise NotImplementedError, "Provider must implement execute method"
      end

      # Reset operations for next processing
      def reset_operations
        @operations = []
      end

      # Get current operations (for testing/debugging)
      def operations
        @operations.dup
      end

      # Helper methods
      protected

      def execute_command(command)
        stdout, stderr, status = Open3.capture3(command)
        raise "Command failed: #{command}\nError: #{stderr.strip}" unless status.success?

        stdout.strip
      end

      def get_image_dimensions(image_path)
        # Use FastImage for better performance and reliability
        require "fastimage"
        dimensions = FastImage.size(image_path)

        unless dimensions
          raise ArgumentError,
                "Unable to read image dimensions for #{image_path}. The file may be corrupted, empty, or in an unsupported format."
        end

        dimensions
      end

      class << self
        # Provider name for identification (override in subclasses)
        def provider_name
          name.split("::").last.downcase
        end

        # Provider capability methods
        def unsupported_operations
          [] # Default: no unsupported operations
        end

        def supports_operation?(operation)
          !unsupported_operations.include?(operation)
        end
      end
    end
  end
end
