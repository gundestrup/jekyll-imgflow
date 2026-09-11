# frozen_string_literal: true

require "json"
require "fileutils"

module JekyllImgFlow
  # Manages the manifest of generated images
  # Tracks default vs specialized versions and page usage for cleanup
  class ManifestManager
    VERSION_TYPES = %w[default specialized].freeze
    attr_reader :manifest_path

    def initialize(site)
      @site = site
      @config = JekyllImgFlow::Config.new(site)
      @file_cleaner = GeneratedFileCleaner.new(site, @config)
      @manifest_path = File.join(@site.source, @config.cache_dir, "imgflow-manifest.json")
      @legacy_manifest_paths = legacy_manifest_paths
      @manifest = load_manifest(manifest_load_path)
      @current_provider = current_provider

      # Check if provider changed and invalidate cache if needed
      handle_provider_change if provider_changed?
    end

    # Load existing manifest or create new one
    def load_manifest(path = @manifest_path)
      return empty_manifest unless path && File.exist?(path)

      load_manifest_file(path)
    rescue JSON::ParserError => e
      Jekyll.logger.warn "ImgFlow: Corrupt manifest file, starting fresh: #{e.message}"
      empty_manifest
    end

    def load_manifest_file(path)
      data = JSON.parse(File.read(path))
      images = manifest_images(data)
      migrate_legacy_manifest(images)
    end

    def manifest_images(data)
      if data.is_a?(Hash) && data.key?("images")
        @cached_provider = data["provider"]
        data["images"] || {}
      else
        @cached_provider = nil
        data
      end
    end

    def empty_manifest
      @cached_provider = nil
      {}
    end

    # Detect and migrate legacy manifest entries (pre-0.1.11 format).
    # Old entries have operations like {"width": 400} without format/quality
    # and no file_digest. Clearing them lets the build re-register existing
    # output files without reprocessing (output_up_to_date? check handles this).
    def migrate_legacy_manifest(images)
      legacy = images.any? do |_name, data|
        versions = data.dig("versions", "default") || []
        versions.any? { |v| v["file_digest"].nil? || !v["operations"].key?("format") }
      end
      if legacy
        Jekyll.logger.info "ImgFlow: Detected legacy manifest format, " \
                           "clearing entries for re-registration."
        images.clear
      end
      images
    end

    # Save manifest to disk
    def save
      # Store current provider at top level of manifest
      manifest_data = {
        "provider" => @current_provider,
        "images" => @manifest
      }
      content = JSON.pretty_generate(manifest_data)
      if File.exist?(@manifest_path) && File.binread(@manifest_path) == content
        cleanup_legacy_manifests
        return
      end

      directory = File.dirname(@manifest_path)
      temporary_path = "#{@manifest_path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
      FileUtils.mkdir_p(directory)
      File.open(temporary_path, "wb") do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary_path, @manifest_path)
      cleanup_legacy_manifests
    ensure
      FileUtils.rm_f(temporary_path) if temporary_path
    end

    # Get current provider from site config
    def current_provider = @config.backend_priority&.first || "unknown"

    # Clean up manifest entries for deleted original images
    # @param current_originals [Array<String>] Paths relative to the originals directory
    def cleanup_deleted_originals(current_originals)
      current_set = current_originals.to_set

      @manifest.each_key do |original_name|
        next if current_set.include?(original_name)

        data = @manifest.delete(original_name)
        VERSION_TYPES.each do |type|
          (data.dig("versions", type) || []).each do |version|
            @file_cleaner.delete(version["output"])
          end
        end
        Jekyll.logger.debug "🗑️  Removed manifest entry for deleted original: #{original_name}"
      end
    end

    def cleanup_obsolete_defaults(expected_operations)
      @manifest.each_value do |data|
        versions = data.dig("versions", "default") || []
        versions.reject! do |version|
          obsolete = expected_operations.none? do |operations|
            same_operations?(version["operations"], operations)
          end
          @file_cleaner.delete(version["output"]) if obsolete
          obsolete
        end
      end
    end

    def reset_page_usage
      @manifest.each_value do |data|
        (data.dig("versions", "specialized") || []).each do |version|
          version["used_on"] = []
        end
      end
    end

    # Normalize operations for consistent comparison after JSON persistence.
    def normalize_operations(operations)
      case operations
      when Hash
        operations.to_h do |key, value|
          [key.to_s, normalize_operations(value)]
        end
      when Array
        operations.map { |value| normalize_operations(value) }
      when Symbol
        operations.to_s
      else
        operations
      end
    end

    def same_operations?(left, right) = normalize_operations(left) == normalize_operations(right)

    # Check if a specific image version exists and is up-to-date
    def version_exists?(original_name, operations, type = :specialized, file_digest = nil)
      return false unless @manifest[original_name]

      # Provider change is already handled in initialize, so just check operations
      versions = @manifest.dig(original_name, "versions", type.to_s) || []
      Jekyll.logger.debug "🔍 ManifestManager: Looking for operations: #{operations.inspect} in #{versions.length} #{type} versions"

      result = versions.any? do |version|
        same_operations?(version["operations"], operations) &&
          (!file_digest || version["file_digest"] == file_digest)
      end
      Jekyll.logger.debug "🔍 ManifestManager: Final result: #{result}"
      result
    end

    # Check if the provider has changed since the manifest was created
    def provider_changed?
      # If no cached provider, this is a new manifest
      return false if @cached_provider.nil?

      # Provider changed if current doesn't match cached
      @cached_provider != @current_provider
    end

    # Handle provider change by invalidating cache and cleaning optimized directory
    def handle_provider_change
      Jekyll.logger.warn "ImgFlow:",
                         "Provider changed from '#{@cached_provider}' to '#{@current_provider}'"
      Jekyll.logger.warn "ImgFlow:", "Invalidating cache and cleaning optimized directory..."

      deleted_count = @file_cleaner.clear
      Jekyll.logger.warn "ImgFlow:",
                         "Deleted #{deleted_count} cached images from optimized directory"

      # Clear manifest cache
      @manifest.clear
      Jekyll.logger.warn "ImgFlow:",
                         "Manifest cache cleared - all images will be regenerated with '#{@current_provider}'"

      # Update cached provider to current
      @cached_provider = @current_provider
    end

    # Get output path for a specific version
    def get_version_output(original_name, operations, type = :specialized)
      return unless @manifest[original_name]

      versions = @manifest.dig(original_name, "versions", type.to_s) || []
      version = versions.find { |v| same_operations?(v["operations"], operations) }
      version&.dig("output")
    end

    # Update page usage for an existing version
    # This is a convenience method that calls register_version
    def update_page_usage(original_name, operations, type, page_path)
      Jekyll.logger.debug "🔍 update_page_usage: original_name=#{original_name}, operations=#{operations.inspect}, type=#{type}, page_path=#{page_path}"

      # Get the existing version's output path (already relative)
      output_path = get_version_output(original_name, operations, type)
      Jekyll.logger.debug "🔍 update_page_usage: output_path=#{output_path}"
      return unless output_path

      # Get the existing version to preserve provider
      versions = @manifest.dig(original_name, "versions", type.to_s) || []
      version = versions.find { |v| same_operations?(v["operations"], operations) }
      provider = version&.dig("provider")
      Jekyll.logger.debug "🔍 update_page_usage: provider=#{provider}, current used_on=#{version&.dig('used_on')&.inspect}"

      # Call register_version to update page usage (output_path is already relative)
      register_version(original_name, output_path, operations, type, page_path, nil, provider)
      Jekyll.logger.debug "🔍 update_page_usage: completed register_version call"
    end

    # Register a new image version
    def register_version(original_name, output_path, operations, type, page_path,
                         file_digest = nil, provider = nil)
      image = manifest_image(original_name, file_digest)
      image["file_digest"] = file_digest if file_digest
      versions = image["versions"][type.to_s] ||= []
      normalized = normalize_operations(operations)
      page_paths = normalize_page_paths(page_path)
      version = versions.find { |entry| same_operations?(entry["operations"], normalized) }

      if version
        update_version(version, output_path, page_paths, file_digest, provider)
      else
        versions << new_version(output_path, normalized, type, page_paths, file_digest, provider)
      end
    end

    def manifest_image(original_name, file_digest)
      @manifest[original_name] ||= {
        "versions" => { "default" => [], "specialized" => [] },
        "file_digest" => file_digest
      }
    end

    def normalize_page_paths(page_path)
      if page_path.is_a?(Array)
        page_path
      else
        (page_path ? [page_path] : [])
      end
    end

    def update_version(version, output_path, page_paths, file_digest, provider)
      version["used_on"] ||= []
      page_paths.each { |path| version["used_on"] << path if path && !version["used_on"].include?(path) }
      version["output"] = output_path
      version["file_digest"] = file_digest if file_digest
      version["provider"] = provider if provider
    end

    def new_version(output_path, operations, type, page_paths, file_digest, provider)
      {
        "output" => output_path,
        "operations" => operations,
        "type" => type.to_s,
        "used_on" => page_paths,
        "created_at" => Time.now.to_i,
        "file_digest" => file_digest,
        "provider" => provider
      }
    end

    # Check if image version is default type
    def default_version?(original_name, operations)
      return false unless @manifest[original_name]

      versions = @manifest.dig(original_name, "versions", "default") || []
      versions.any? { |v| same_operations?(v["operations"], operations) }
    end

    # Find orphaned specialized images (not used on any page)
    def find_orphans
      orphans = []

      @manifest.each do |original_name, data|
        specialized = data.dig("versions", "specialized") || []
        specialized.each do |version|
          next unless version["used_on"].nil? || version["used_on"].empty?

          orphans << {
            "original" => original_name,
            "output" => version["output"],
            "operations" => version["operations"]
          }
        end
      end

      orphans
    end

    # Remove page from all image version usage tracking
    def remove_page_usage(page_path)
      @manifest.each_value do |data|
        VERSION_TYPES.each do |type|
          versions = data.dig("versions", type) || []
          versions.each do |version|
            version["used_on"]&.delete(page_path)
          end
        end
      end
    end

    # Cleanup orphaned specialized images
    def cleanup_orphans
      orphans = find_orphans
      cleaned = []

      orphans.each do |orphan|
        if @file_cleaner.delete(orphan["output"])
          cleaned << orphan["output"]
          Jekyll.logger.info "🗑️  Cleaned orphaned image: #{orphan['output']}"
        end

        # Remove from manifest
        versions = @manifest.dig(orphan["original"], "versions", "specialized") || []
        versions.reject! { |v| same_operations?(v["operations"], orphan["operations"]) }
      end

      cleaned
    end

    # Get all versions for an original image
    def get_versions(original_name)
      @manifest.dig(original_name, "versions") || { "default" => [], "specialized" => [] }
    end

    # Check if original image has any versions
    def versions?(original_name)
      return false unless @manifest[original_name]

      versions = @manifest[original_name]["versions"]
      (versions["default"]&.any? || false) || (versions["specialized"]&.any? || false)
    end

    private

    def legacy_manifest_paths
      [
        File.join(@site.source, "assets", "images", "imgflow-manifest.json"),
        File.join(@site.dest, "assets", "images", "imgflow-manifest.json")
      ].reject { |path| path == @manifest_path }
    end

    def manifest_load_path
      return @manifest_path if File.exist?(@manifest_path)

      @legacy_manifest_paths.find { |path| File.exist?(path) }
    end

    def cleanup_legacy_manifests
      @legacy_manifest_paths.each { |path| FileUtils.rm_f(path) }
    end
  end
end
