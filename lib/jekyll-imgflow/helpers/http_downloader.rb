# frozen_string_literal: true

require "securerandom"
require "fileutils"
require "tmpdir"
require "net/http"
require "uri"

module JekyllImgFlow
  module Helpers
    # HTTP Downloader - handles downloading images from HTTP/HTTPS/file:// URLs
    class HttpDownloader
      # Download a file from URL to temporary location
      # @param url [String] URL to download (http://, https://, or file://)
      # @return [String] Path to downloaded temporary file
      def self.download(url)
        uri = URI(url)

        # Handle file:// URLs for local file processing
        if uri.scheme == "file"
          download_file_url(uri)
        else
          download_http_url(uri)
        end
      end

      private_class_method def self.download_file_url(uri)
        # For file:// URLs, copy the local file to temp
        source_path = uri.path
        ext = File.extname(source_path)
        tmp = File.join(Dir.tmpdir, "imgflow-#{SecureRandom.hex}#{ext}")
        FileUtils.cp(source_path, tmp)
        tmp
      end

      private_class_method def self.download_http_url(uri)
        # For HTTP/HTTPS URLs, download the file
        ext = File.extname(uri.path)
        tmp = File.join(Dir.tmpdir, "imgflow-#{SecureRandom.hex}#{ext}")

        begin
          response = Net::HTTP.get_response(uri)

          # Handle redirects
          if response.is_a?(Net::HTTPRedirection)
            location = response["location"]
            raise "Redirect without location" unless location

            # Follow the redirect
            redirect_uri = URI(location)
            redirect_uri = URI("#{uri.scheme}://#{uri.host}#{location}") if location.start_with?("/")

            response = Net::HTTP.get_response(redirect_uri)
          end

          raise "HTTP request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          File.write(tmp, response.body, mode: "wb")
        rescue StandardError => e
          FileUtils.rm_f(tmp)
          raise "Failed to download #{uri}: #{e.message}"
        end

        tmp
      end
    end
  end
end
