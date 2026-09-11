# frozen_string_literal: true

require "open3"
require "pathname"
require "fileutils"

module JekyllImgFlow
  module Providers
    # Base provider class - all providers must inherit from this
    class BaseProvider
      # Valid smartcrop position values
      SMARTCROP_POSITIONS = %w[attention entropy center centre].freeze

      # Short compass → provider position mapping used by HTTP providers.
      COMPASS_TO_SHORT = {
        "northwest" => "tl",
        "northeast" => "tr",
        "southwest" => "bl",
        "southeast" => "br",
        "center" => "c"
      }.freeze

      attr_accessor :config

      def initialize(config = {})
        @config = config
        @operations = []
      end

      # Operation lookup helpers — used by all providers to avoid
      # repeating `@operations.find { |op| op[:type] == :xxx }`.
      def find_op(type)
        @operations.find { |op| op[:type] == type }
      end

      def op?(type)
        @operations.any? { |op| op[:type] == type }
      end

      # Normalize a crop operation into a geometry hash.
      # Returns { smartcrop:, keep:, x:, y:, width:, height: } where
      # smartcrop is true when ratio + keep + valid smartcrop position.
      def crop_geometry(operation)
        opts = operation[:options] || {}
        params = operation[:params] || {}
        keep = opts[:keep] || params[:keep] || params[:position]
        smartcrop = operation[:ratio] && keep && SMARTCROP_POSITIONS.include?(keep.to_s)
        coords = if operation[:ratio]
                   { x: opts[:calculated_x], y: opts[:calculated_y],
                     width: opts[:calculated_width], height: opts[:calculated_height] }
                 else
                   { x: opts[:x] || 0, y: opts[:y] || 0,
                     width: opts[:width], height: opts[:height] }
                 end
        coords.merge(smartcrop: smartcrop, keep: keep)
      end

      # Extract watermark operation parts into a hash.
      def watermark_parts(operation)
        {
          watermark_path: operation[:watermark_path],
          position: operation[:options][:position],
          opacity: operation[:options][:opacity]
        }
      end

      # Shared compass → short position mapping (tl/tr/bl/br/c).
      # HTTP providers (imgproxy, weserv, flyimg) all use this mapping.
      def compass_to_short(position)
        COMPASS_TO_SHORT[position.to_s] || position.to_s
      end

      # Input format extension (lowercased, no dot) for format preservation.
      def input_format_ext(input_path)
        File.extname(input_path).delete(".").downcase
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

      # Check if the input file is an SVG (vector format).
      # SVGs require special handling: they have no fixed pixel dimensions,
      # so providers must choose a rasterization size.
      def svg?(input_path)
        File.extname(input_path).downcase == ".svg"
      end

      def execute_command(command)
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec -- provider commands shell-escape paths; pipelines are intentional for Sharp watermark operations.
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
        KNOWN_OPERATIONS = %i[crop format opacity optimize quality resize
                              watermark alpha_opacity].freeze

        def unsupported_operations
          [] # Default: no unsupported operations
        end

        def supports_operation?(operation)
          return false unless KNOWN_OPERATIONS.include?(operation)

          !unsupported_operations.include?(operation)
        end
      end
    end

    # Shared base for HTTP-based providers (imgproxy, weserv, flyimg).
    # Subclasses must implement `service_url`, `build_combined_url`, and
    # define a `TIMEOUT` constant. They may optionally override
    # `provider_label` for error messages.
    class HttpBase < BaseProvider
      def available?
        url = service_url
        return false unless url

        check_http_service(url)
      end

      def execute(input_path, output_path)
        return if @operations.empty?

        url = build_combined_url(input_path)
        fetch_and_save(url, output_path)
        output_path
      ensure
        reset_operations
      end

      protected

      # Subclasses override to return the configured service URL or nil.
      def service_url
        raise NotImplementedError
      end

      # Subclasses override to build the full request URL.
      def build_combined_url(_input_path)
        raise NotImplementedError
      end

      # Label used in error messages (defaults to class name).
      def provider_label
        self.class.name.split("::").last
      end

      def timeout
        self.class::TIMEOUT
      end

      def fetch_and_save(url, output_path)
        response = fetch_with_timeout(url)
        raise "#{provider_label} request failed" if response.empty?

        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, response)
      end

      def fetch_with_timeout(url)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port,
                        use_ssl: uri.scheme == "https",
                        open_timeout: timeout,
                        read_timeout: timeout) do |http|
          request = Net::HTTP::Get.new(uri)
          response = http.request(request)

          raise "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

          response.body
        end
      rescue StandardError => e
        raise "#{provider_label} request failed: #{e.message}"
      end
    end
  end
end
