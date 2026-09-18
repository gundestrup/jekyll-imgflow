# frozen_string_literal: true

module JekyllImgFlow
  # BuildTimeProcessor - processes images during Jekyll build
  # Generates default image versions for all originals
  class BuildTimeProcessor
    def initialize(site)
      @site = site
      @config = Config.new(site)
      @manifest = ManifestManager.new(site)
      @path_resolver = PathResolver.new(@config)
      @registry = ProviderRegistry.new(@config)

      # Initialize operation processor with current provider
      provider = @registry.current_provider
      @operation_processor = OperationProcessor.new(provider, @path_resolver, @manifest, @config) if provider

      # Initialize batch manager
      @batch_manager = BatchManager.new(@operation_processor)

      # Store all components in site for sharing with ImgFlow tag
      @filename_generator = JekyllImgFlow::FilenameGenerator.new

      @site.imgflow_components = {
        config: @config,
        manifest: @manifest,
        path_resolver: @path_resolver,
        filename_generator: @filename_generator,
        registry: @registry,
        provider: provider,
        operation_processor: @operation_processor,
        stats: @operation_processor&.stats,
        preset_manager: JekyllImgFlow::PresetManager.new(@site, @config)
      }
    end

    # Process all changed images in originals folder
    def process_changed_images
      return { completed: 0, failed: 0 } unless @operation_processor

      Jekyll.logger.info "🔄 BuildTimeProcessor: Processing changed images"

      # Get all original images
      original_paths = find_original_images
      Jekyll.logger.info "📸 Found #{original_paths.length} original images"

      # Clean up manifest entries for deleted originals
      prepare_manifest(original_paths)

      # Build tasks for each original image
      queue_default_tasks(original_paths)

      # Process all queued tasks
      results = @batch_manager.process_all
      register_skipped_tasks(@batch_manager.completed)

      # Persist newly processed defaults; unchanged builds keep page-usage resets in memory
      # until post_write saves the final stable manifest.
      @manifest.save unless results[:completed].zero? && results[:failed].zero?

      Jekyll.logger.info "✅ BuildTimeProcessor complete: #{results[:completed]} completed, #{results[:failed]} failed"

      results
    end

    private

    def prepare_manifest(original_paths)
      originals_dir = File.join(@site.source, @config.originals)
      current_originals = original_paths.map { |path| path.sub("#{originals_dir}/", "") }
      @manifest.cleanup_deleted_originals(current_originals)
      @manifest.cleanup_obsolete_defaults(expected_default_operations)
      @manifest.reset_page_usage unless incremental_build?
    end

    def queue_default_tasks(original_paths)
      originals_dir = File.join(@site.source, @config.originals)
      original_paths.reject { |path| AnimatedGifDetector.animated?(path) }.each do |path|
        queue_tasks_for(path, path.sub("#{originals_dir}/", ""))
      end
    end

    def queue_tasks_for(path, original_name)
      file_digest = @filename_generator.file_digest(path)
      unless needs_processing?(original_name, path, file_digest)
        expected_default_operations.length.times { @operation_processor.stats.record_cache_hit }
        Jekyll.logger.debug "⏭️  Skipping #{original_name} - already up-to-date"
        return
      end

      Jekyll.logger.info "🔧 Queuing default versions for: #{original_name}"

      tasks = BatchManager.build_default_tasks(
        original_name, path, @config, @site, file_digest: file_digest
      )
      force_processing = source_digest_changed?(original_name, file_digest)
      tasks.each { |task| task[:force_processing] = force_processing }
      @batch_manager.add_tasks(tasks)
    end

    def register_skipped_tasks(completed_tasks)
      provider_name = @registry.current_provider&.class&.provider_name || "unknown"
      completed_tasks.each do |completed|
        next unless completed[:status] == :skipped

        task = completed[:task]
        @operation_processor.stats.record_cache_hit
        relative_path = task[:output_path].sub(@site.source, "")
        @manifest.register_version(
          task[:original_name], relative_path, task[:params], :default, nil,
          task[:file_digest], provider_name
        )
      end
    end

    # Find all original images in originals folder
    def find_original_images
      # Use PathResolver to get the originals directory path
      originals_dir = File.join(@site.source, @config.originals)
      input_formats = @config.input_formats

      Dir.glob(File.join(originals_dir, "**", "*.{#{input_formats.join(',')}}"))
    end

    # Check if image needs processing
    # @param original_name [String] Path to original image relative to originals directory
    # @param path [String, nil] Full path to original image (defaults to original_name)
    # @return [Boolean] True if processing needed
    def needs_processing?(original_name, path = nil, file_digest = nil)
      path ||= original_name
      original_name = File.basename(original_name) if original_name == path
      return true unless File.file?(path)

      file_digest ||= @filename_generator.file_digest(path)
      default_versions = @manifest.get_versions(original_name)["default"] || []
      current_provider = @registry.current_provider&.class&.provider_name || "unknown"

      expected_default_operations.any? do |operations|
        version = find_default_version(default_versions, operations)
        !current_default_version?(version, current_provider, file_digest)
      end
    end

    def find_default_version(default_versions, operations)
      default_versions.find do |candidate|
        @manifest.same_operations?(candidate["operations"], operations)
      end
    end

    def expected_default_operations
      @config.sizes.each_value.flat_map do |width|
        @config.formats.map do |format|
          { width: width, format: format, quality: @config.quality }
        end
      end
    end

    def source_digest_changed?(original_name, file_digest)
      digests = (@manifest.get_versions(original_name)["default"] || []).filter_map do |version|
        version["file_digest"]
      end
      digests.any? && digests.any? { |digest| digest != file_digest }
    end

    def incremental_build?
      @site.is_a?(Jekyll::Site) && @site.incremental?
    end

    def current_default_version?(version, current_provider, file_digest)
      return false unless version && version["provider"] == current_provider
      return false unless version["file_digest"] == file_digest

      output_path = version["output"]
      return false unless output_path

      absolute_path = File.expand_path(output_path.delete_prefix("/"), @site.source)
      output_root = File.expand_path(@config.output, @site.source)
      return false unless absolute_path.start_with?("#{output_root}#{File::SEPARATOR}")

      File.file?(absolute_path)
    end
  end
end
