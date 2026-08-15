# frozen_string_literal: true

require_relative "filename_generator"

module JekyllImgFlow
  # OperationProcessor - processes image operations using providers
  # Handles both single operations and batch operations
  class OperationProcessor
    def initialize(provider, path_resolver, manifest = nil, config = nil)
      @provider = provider
      @path_resolver = path_resolver
      @filename_generator = FilenameGenerator.new
      @manifest = manifest
      @config = config
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
      type = operation[:type]
      params = operation[:params]

      # Generate filename using FilenameGenerator (JPT compatible)
      filename = @filename_generator.generate_filename(input_path, params)
      # Write to _site during build (after Jekyll copies assets)
      actual_output_path = @path_resolver.resolve_output_path(filename)

      # Determine version type
      version_type = determine_version_type(params)

      # Ensure output directory exists before processing
      FileUtils.mkdir_p(File.dirname(actual_output_path))

      # Animated GIFs must not be resized or converted — the operation
      # would destroy the animation. Copy the original file as-is so the
      # manifest can track it and HTML references stay valid.
      if AnimatedGifDetector.animated?(input_path)
        Jekyll.logger.warn "🖼️  ImgFlow: Skipping resize for animated GIF " \
                           "'#{original_name}' — copying original as-is to " \
                           "preserve animation."
        FileUtils.cp(input_path, actual_output_path)
      else
        # Process the operation (create the image)
        process_single_operation(type, input_path, actual_output_path, params)
      end

      # Register in manifest
      if @manifest
        # Convert absolute path to relative for manifest storage
        relative_path = actual_output_path.sub(@path_resolver.site_dest, "")

        provider_name = @provider.class.provider_name
        @manifest.register_version(
          original_name,
          relative_path,
          params,
          version_type,
          page_path,
          nil, # file_digest
          provider_name
        )
      end

      actual_output_path
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
    def needs_processing?(input_path, output_path, operations)
      # If output doesn't exist, needs processing
      return true unless File.exist?(output_path)

      # If input is newer than output, needs processing
      return true if File.mtime(input_path) > File.mtime(output_path)

      # Check if operations changed by comparing cache key
      # stored alongside the output file
      cache_key = @filename_generator.generate_cache_key(operations)
      cache_file = "#{output_path}.cache_key"

      return true unless File.exist?(cache_file)

      stored_key = File.read(cache_file).strip
      return true if stored_key != cache_key

      # No cache key file - needs processing to create it

      false
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
