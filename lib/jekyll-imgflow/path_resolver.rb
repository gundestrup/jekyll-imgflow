# frozen_string_literal: true

require "securerandom"
require "tmpdir"

module JekyllImgFlow
  # PathResolver - centralized path management for all image operations
  class PathResolver
    def initialize(config)
      @config = config
    end

    # Get path information for an image
    # @param image_name [String] Name of the image file
    # @return [Hash] Path information for different use cases
    def paths_for(image_name)
      {
        cli: File.join(@config.site.source, @config.originals, image_name), # Full filesystem path
        http: File.join(@config.originals, image_name), # Relative path for URLs
        name: image_name # Just the filename
      }
    end

    # Get CLI path (convenience method)
    def cli_path(image_name)
      paths_for(image_name)[:cli]
    end

    # Get HTTP path (convenience method)
    def http_path(image_name)
      paths_for(image_name)[:http]
    end

    # Resolve original path with validation
    # @param image_name [String] Name of the image file
    # @return [String] Full path to original image file
    # @raise [ArgumentError] If image cannot be resolved or doesn't exist
    def resolve_original_path(image_name)
      full_path = cli_path(image_name)

      # Validate path exists and is readable
      raise ArgumentError, "Cannot resolve image path: #{image_name} (not found: #{full_path})" unless File.exist?(full_path)

      raise ArgumentError, "Image path is not a file: #{image_name} (path: #{full_path})" unless File.file?(full_path)

      raise ArgumentError, "Image path not readable: #{image_name} (path: #{full_path})" unless File.readable?(full_path)

      # Validate input file format against config
      file_extension = File.extname(full_path).delete(".").downcase
      input_formats = @config.input_formats

      raise ArgumentError, "No input_formats configured in unified config" unless input_formats

      unless input_formats.include?(file_extension)
        raise ArgumentError,
              "Invalid input format: '#{file_extension}'. Must be one of: #{input_formats.join(', ')}."
      end

      full_path
    end

    # Resolve output path for generated filename
    # @param filename [String] Generated filename
    # @param subdir [String, nil] Optional subdirectory under output
    # @return [String] Full path to output file in _site (for specialized versions during rendering)
    def resolve_output_path(filename, subdir = nil)
      # Resolve output path relative to site destination
      File.join([@config.site.dest, @config.output, subdir, filename].compact)
    end

    # Resolve output path to source directory for default images
    # @param filename [String] Generated filename
    # @param subdir [String, nil] Optional subdirectory under output
    # @return [String] Full path to output file in source (for default versions during pre_render)
    def resolve_source_output_path(filename, subdir = nil)
      # Default images go to source directory so Jekyll can copy them to _site
      File.join([@config.site.source, @config.output, subdir, filename].compact)
    end

    # Resolve relative output path for manifest storage
    # @param filename [String] Generated filename
    # @param subdir [String, nil] Optional subdirectory under output
    # @return [String] Relative path from site root
    def resolve_relative_output_path(filename, subdir = nil)
      # Return path relative to site root (without leading /)
      File.join([@config.output, subdir, filename].compact)
    end

    # Get site destination directory
    # @return [String] Site destination path
    def site_dest
      @config.site.dest
    end

    # Generate temporary output path
    # @param format [String] File format extension
    # @return [String] Path to temporary file
    def temp_output_path(format)
      File.join(Dir.tmpdir, "imgflow-out-#{SecureRandom.hex}.#{format}")
    end

    # Generate temporary input path
    # @param extension [String] File extension
    # @return [String] Path to temporary file
    def temp_input_path(extension = "tmp")
      File.join(Dir.tmpdir, "imgflow-in-#{SecureRandom.hex}.#{extension}")
    end

    # Build public URL for image
    # @param relative_path [String] Relative path from site root
    # @param site [Jekyll::Site] Jekyll site object
    # @return [String] Public URL
    def build_url(relative_path, site)
      base_url = site.config["url"] || "http://localhost:4000"
      baseurl = site.config["baseurl"] || ""
      "#{base_url}#{baseurl}/#{relative_path}"
    end

    # Get relative path from site destination
    # @param full_path [String] Full filesystem path
    # @param site [Jekyll::Site] Jekyll site object
    # @return [String] Relative path
    def relative_from_dest(full_path, site)
      # Simple path manipulation - remove site.dest prefix and leading slash
      if full_path.start_with?(site.dest)
        relative = full_path[site.dest.length..]
        relative.start_with?("/") ? relative[1..] : relative
      else
        full_path
      end
    end
  end
end
