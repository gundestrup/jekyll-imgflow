# frozen_string_literal: true

require_relative "filename_generator"
require "benchmark"

module JekyllImgFlow
  # OperationProcessor - processes image operations using providers
  # Handles both single operations and batch operations
  class OperationProcessor
    attr_accessor :stats

    def initialize(provider, path_resolver, manifest = nil, config = nil)
      @provider = provider
      @path_resolver = path_resolver
      @filename_generator = FilenameGenerator.new
      @manifest = manifest
      @config = config
      @stats = ProcessingStats.new
    end

    # Process a single operation on an image
    # @param operation_type [Symbol] Type of operation (:resize, :crop, :quality, etc.)
    # @param input_path [String] Path to input image
    # @param output_path [String] Path to output image
    # @param params [Hash] Operation parameters
    # @return [String] Path to processed image
    def process_single_operation(operation_type, input_path, output_path, params)
      # Get the appropriate tag class for validation
      tag_class = JekyllImgFlow::Tags::TagRegistry.get_tag(operation_type)
      raise "Unknown operation: #{operation_type}" unless tag_class

      # Create tag instance and process
      tag = tag_class.new(@provider)
      tag.process(input_path, output_path, params)

      output_path
    end

    # Process an operation and return the output path
    # @param original_name [String] Original image filename
    # @param operation [Hash] Operation structure { type: :resize, params: { width: 800 } }
    # @param input_path [String] Path to input image
    # @param page_path [String] Optional page path for manifest tracking
    # @return [String] Path to processed image
    def process_operation(original_name, operation, input_path, page_path = nil)
      params = operation[:params]
      file_digest = operation[:file_digest] || @filename_generator.file_digest(input_path)
      version_type = determine_version_type(params)
      filename = @filename_generator.generate_filename(input_path, params)
      subdir = output_subdir(original_name)
      output_path = @path_resolver.resolve_source_output_path(filename, subdir)
      FileUtils.mkdir_p(File.dirname(output_path))

      process_output(operation, original_name, input_path, output_path, params)
      register_manifest(original_name, filename, params, version_type, page_path, file_digest, subdir)
      register_jekyll_static_file(output_path)
      output_path
    end

    def output_subdir(original_name)
      subdir = File.dirname(original_name)
      subdir == "." ? nil : subdir
    end

    def process_output(operation, original_name, input_path, output_path, params)
      if !operation[:force_processing] && output_up_to_date?(input_path, output_path)
        Jekyll.logger.debug "⏭️  ImgFlow: Output exists and up-to-date, skipping provider call for #{original_name}"
        @stats.record_cache_hit
      elsif AnimatedGifDetector.animated?(input_path)
        copy_animated_image(original_name, input_path, output_path)
      else
        process_image(operation[:type], input_path, output_path, params)
      end
    end

    def copy_animated_image(original_name, input_path, output_path)
      Jekyll.logger.warn "🖼️  ImgFlow: Skipping resize for animated GIF '#{original_name}' — " \
                         "copying original as-is to preserve animation."
      FileUtils.cp(input_path, output_path)
      @stats.record_cache_miss
    end

    def process_image(type, input_path, output_path, params)
      elapsed = Benchmark.measure { process_single_operation(type, input_path, output_path, params) }
      @stats.record_operation_time(type, elapsed.real)
      @stats.record_cache_miss
      record_compression_ratio(input_path, output_path, params)
    end

    def record_compression_ratio(input_path, output_path, params)
      return unless File.file?(input_path) && File.file?(output_path)

      format = params[:format] || File.extname(input_path).delete(".")
      @stats.record_compression_ratio(format.to_s, File.size(input_path), File.size(output_path))
    end

    def register_manifest(original_name, filename, params, version_type, page_path, file_digest, subdir)
      return unless @manifest

      relative_path = "/#{@path_resolver.resolve_relative_output_path(filename, subdir)}"
      provider_name = @provider&.class&.provider_name || "unknown"
      @manifest.register_version(original_name, relative_path, params, version_type, page_path,
                                 file_digest, provider_name)
    end

    # Register a generated file as a Jekyll::StaticFile so Jekyll copies it
    # to _site during the write phase. No-op for mock/test sites.
    # @param file_path [String] Absolute path to the generated file in source
    def register_jekyll_static_file(file_path)
      site = @config&.site
      return unless site.is_a?(Jekyll::Site)

      relative = file_path.delete_prefix("#{site.source}/")
      return if relative == file_path # not under site source

      add_static_file(site, relative) unless static_file_registered?(site, relative)
    end

    # @param site [Jekyll::Site] Jekyll site object
    # @param relative [String] Path relative to site source
    def static_file_registered?(site, relative)
      site.static_files.any? { |sf| sf.relative_path == "/#{relative}" }
    end

    # @param site [Jekyll::Site] Jekyll site object
    # @param relative [String] Path relative to site source
    def add_static_file(site, relative)
      site.static_files << Jekyll::StaticFile.new(
        site, site.source, File.dirname(relative), File.basename(relative)
      )
    end

    # Process multiple operations on an image in sequence (batch)
    # @param operations [Array<Hash>] Array of operations to process
    # @param input_path [String] Path to input image
    # @param final_output_path [String] Path to final output image
    # @return [String] Path to final processed image
    def process_batch_operations(operations, input_path, final_output_path)
      return input_path if operations.empty?

      current_input = input_path
      temp_files = []

      begin
        # Process each operation in sequence
        operations.each_with_index do |operation, index|
          operation_type = operation[:type]
          params = operation[:params] || {}

          # Determine output path
          if index == operations.length - 1
            # Last operation - use final output path
            output_path = final_output_path
          else
            # Intermediate operation - use temp file
            format = params[:format] || File.extname(input_path).delete(".")
            output_path = @path_resolver.temp_output_path(format)
            temp_files << output_path
          end

          # Process the operation
          current_input = process_single_operation(operation_type, current_input,
                                                   output_path, params)
        end

        current_input
      ensure
        # Cleanup temp files even on failure
        temp_files.each { |f| FileUtils.rm_f(f) }
      end
    end

    # Check if operation needs to be processed (cache check)
    # @param input_path [String] Path to input image
    # @param output_path [String] Path to output image
    # @param operations [Hash] Operations to apply
    # @return [Boolean] True if processing needed
    def needs_processing?(input_path, output_path, _operations = nil)
      # If output doesn't exist, needs processing
      return true unless File.exist?(output_path)

      # If input is newer than output, needs processing
      File.mtime(input_path) > File.mtime(output_path)
    end

    # Check if the output file exists and the input is not newer than the
    # output. Used to skip provider calls when the optimized file is already
    # on disk (e.g. legacy manifest, manifest out of sync).
    # @param input_path [String] Path to input image
    # @param output_path [String] Path to output image
    # @return [Boolean] True if output exists and is up-to-date
    def output_up_to_date?(input_path, output_path)
      File.file?(output_path) && File.mtime(input_path) <= File.mtime(output_path)
    end

    # Build operation structure from params hash
    # Combines all params into a single operation with flat params
    # @param params [Hash] Parameters hash
    # @return [Hash] Operation structure { type: :resize, params: { ... } }
    def build_operation_from_params(params)
      # Determine primary operation type
      type = if params[:width] || params[:height]
               :resize
             elsif params[:crop]
               :crop
             elsif params[:watermark]
               :watermark
             else
               :format
             end

      # Return unified operation structure with all params flattened
      {
        type: type,
        params: params.compact
      }
    end

    # Build operations array from tag parameters
    # @param tag_params [Hash] Parameters from tag
    # @return [Array<Hash>] Array of operation hashes
    def build_operations_from_params(tag_params)
      [build_operation_from_params(tag_params)]
    end

    # Determine if operations represent default or specialized version
    # @param params [Hash] Operation parameters
    # @return [Symbol] :default or :specialized
    def determine_version_type(params)
      @config&.determine_version_type(params) || :specialized
    end
  end
end
