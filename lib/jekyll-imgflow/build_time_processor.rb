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
      @operation_processor = OperationProcessor.new(provider, @path_resolver, @manifest, @config)

      # Initialize batch manager
      @batch_manager = BatchManager.new(@operation_processor)

      # Store all components in site for sharing with ImgFlow tag
      return if @site.imgflow_components

      filename_generator = JekyllImgFlow::FilenameGenerator.new

      @site.imgflow_components = {
        config: @config,
        manifest: @manifest,
        path_resolver: @path_resolver,
        filename_generator: filename_generator,
        registry: @registry,
        provider: provider,
        operation_processor: @operation_processor
      }
    end

    # Process all changed images in originals folder
    def process_changed_images
      Jekyll.logger.info "🔄 BuildTimeProcessor: Processing changed images"

      # Get all original images
      original_paths = find_original_images
      Jekyll.logger.info "📸 Found #{original_paths.length} original images"

      # Build tasks for each original image
      original_paths.each do |path|
        original_name = File.basename(path)

        # Check if needs processing (file changed or provider changed)
        if needs_processing?(path)
          Jekyll.logger.info "🔧 Queuing default versions for: #{original_name}"

          # Build default tasks
          tasks = BatchManager.build_default_tasks(original_name, path, @config, @site)
          @batch_manager.add_tasks(tasks)
        else
          Jekyll.logger.debug "⏭️  Skipping #{original_name} - already up-to-date"
        end
      end

      # Process all queued tasks
      results = @batch_manager.process_all

      # Register completed tasks in manifest
      register_completed_tasks(@batch_manager.completed)

      # Save manifest so it's available when ImgflowTag runs
      @manifest.save

      Jekyll.logger.info "✅ BuildTimeProcessor complete: #{results[:completed]} completed, #{results[:failed]} failed"

      results
    end

    private

    # Register completed tasks in manifest
    # @param completed_tasks [Array<Hash>] Array of completed tasks from BatchManager
    def register_completed_tasks(completed_tasks)
      completed_tasks.each do |task|
        next unless task[:task] && task[:result]

        # Get provider name
        provider_name = @registry.current_provider.class.name.split("::").last.downcase

        # Convert absolute path to relative for manifest storage
        absolute_path = task[:result]
        relative_path = absolute_path.sub(@site.dest, "")

        # Register the version in manifest
        @manifest.register_version(
          task[:task][:original_name],
          relative_path,
          task[:task][:params],
          :default, # BuildTimeProcessor creates default versions
          nil, # page_path (default versions aren't tied to specific pages)
          nil, # file_digest
          provider_name
        )
      end

      Jekyll.logger.debug "📝 Registered #{completed_tasks.length} completed tasks in manifest"
    end

    # Find all original images in originals folder
    def find_original_images
      # Use PathResolver to get the originals directory path
      originals_dir = File.join(@site.source, @config.originals)
      input_formats = @config.input_formats

      Dir.glob(File.join(originals_dir, "**", "*.{#{input_formats.join(',')}}"))
         .reject { |path| AnimatedGifDetector.animated?(path) }
    end

    # Check if image needs processing
    # @param path [String] Path to original image
    # @return [Boolean] True if processing needed
    def needs_processing?(path)
      original_name = File.basename(path)

      # If no versions exist, needs processing
      return true unless @manifest.versions?(original_name)

      # Check if original file was modified
      versions = @manifest.get_versions(original_name)
      default_versions = versions["default"] || []

      return true if default_versions.empty?

      # Get the most recent version creation time
      latest_version = default_versions.max_by { |v| v["created_at"] || 0 }
      version_time = latest_version["created_at"]

      # If original is newer than versions, needs processing
      return true unless version_time

      original_mtime = File.mtime(path).to_i
      return true if original_mtime > version_time

      # No timestamp means we need to process

      # Check if provider changed
      current_provider = @registry.current_provider.class.provider_name
      version_providers = default_versions.map { |v| v["provider"] }
      version_providers.uniq!

      return true unless version_providers.include?(current_provider)

      # Up-to-date
      false
    end
  end
end
