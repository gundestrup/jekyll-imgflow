# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"

module JekyllImgFlow
  # Manages the manifest of generated images
  # Tracks default vs specialized versions and page usage for cleanup
  class ManifestManager
    VERSION_TYPES = %w[default specialized].freeze
    attr_reader :manifest_path

    def initialize(site)
      @site = site
      # Place manifest in _site - rebuilt on each Jekyll build
      @manifest_path = File.join(@site.dest, "assets", "images", "imgflow-manifest.json")
      @manifest = load_manifest
      @current_provider = current_provider

      # Check if provider changed and invalidate cache if needed
      handle_provider_change if provider_changed?
    end

    # Load existing manifest or create new one
    def load_manifest
      if File.exist?(@manifest_path)
        begin
          data = JSON.parse(File.read(@manifest_path))

          # Handle new format with provider at top level
          if data.is_a?(Hash) && data.key?("images")
            @cached_provider = data["provider"]
            data["images"] || {}
          else
            # Old format - just image data
            @cached_provider = nil
            data
          end
        rescue JSON::ParserError => e
          Jekyll.logger.warn "ImgFlow: Corrupt manifest file, starting fresh: #{e.message}"
          @cached_provider = nil
          {}
        end
      else
        @cached_provider = nil
        {}
      end
    end

    # Save manifest to disk
    def save
      # Store current provider at top level of manifest
      manifest_data = {
        "provider" => @current_provider,
        "images" => @manifest
      }

      FileUtils.mkdir_p(File.dirname(@manifest_path))
      File.write(@manifest_path, JSON.pretty_generate(manifest_data))
    end

    # Get current provider from site config
    def current_provider
      config = JekyllImgFlow::Config.new(@site)
      # Get first available provider from backend_priority
      config.backend_priority&.first || "unknown"
    end

    # Clean up manifest entries for deleted original images
    # @param current_originals [Array<String>] Array of current original image basenames
    def cleanup_deleted_originals(current_originals)
      current_set = current_originals.to_set

      @manifest.each_key do |original_name|
        # Extract basename without extension
        basename = File.basename(original_name, ".*")

        # If original no longer exists, remove from manifest
        unless current_set.include?(basename)
          @manifest.delete(original_name)
          Jekyll.logger.debug "🗑️  Removed manifest entry for deleted original: #{original_name}"
        end
      end
    end

    # Check if a specific image version exists and is up-to-date
    def version_exists?(original_name, operations, type = :specialized)
      return false unless @manifest[original_name]

      # Provider change is already handled in initialize, so just check operations
      versions = @manifest.dig(original_name, "versions", type.to_s) || []
      Jekyll.logger.debug "🔍 ManifestManager: Looking for operations: #{operations.inspect} in #{versions.length} #{type} versions"

      result = versions.any? { |v| v["operations"] == operations }
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

      # Get optimized directory path
      config = JekyllImgFlow::Config.new(@site)
      optimized_dir = File.join(@site.source, config.output)

      # Safety guard: prevent deletion of _site itself
      raise "Refusing to delete optimized directory: path resolves to site dest or is empty" if optimized_dir == @site.dest || optimized_dir.empty?

      # Delete all files in optimized directory
      if Dir.exist?(optimized_dir)
        deleted_count = 0
        Dir.glob(File.join(optimized_dir, "**", "*")).each do |file|
          if File.file?(file)
            File.delete(file)
            deleted_count += 1
          end
        end
        Jekyll.logger.warn "ImgFlow:",
                           "Deleted #{deleted_count} cached images from optimized directory"
      end

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
      version = versions.find { |v| v["operations"] == operations }
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
      version = versions.find { |v| v["operations"] == operations }
      provider = version&.dig("provider")
      Jekyll.logger.debug "🔍 update_page_usage: provider=#{provider}, current used_on=#{version&.dig('used_on')&.inspect}"

      # Call register_version to update page usage (output_path is already relative)
      register_version(original_name, output_path, operations, type, page_path, nil, provider)
      Jekyll.logger.debug "🔍 update_page_usage: completed register_version call"
    end

    # Register a new image version
    def register_version(original_name, output_path, operations, type, page_path,
                         file_digest = nil, provider = nil)
      @manifest[original_name] ||= {
        "versions" => { "default" => [], "specialized" => [] },
        "file_digest" => file_digest # Store SHA256 digest of original file
      }

      # Update file digest if provided
      @manifest[original_name]["file_digest"] = file_digest if file_digest

      versions = @manifest[original_name]["versions"][type.to_s] ||= []

      # Find or create version entry
      version = versions.find { |v| v["operations"] == operations }

      # Normalize page_path to array
      page_paths = if page_path.is_a?(Array)
                     page_path
                   else
                     (page_path ? [page_path] : [])
                   end

      if version
        # Add pages to used_on list if not already present
        version["used_on"] ||= []
        page_paths.each do |path|
          version["used_on"] << path if path && !version["used_on"].include?(path)
        end
        # Update provider if provided
        version["provider"] = provider if provider
      else
        # Create new version entry
        versions << {
          "output" => output_path,
          "operations" => operations,
          "type" => type.to_s,
          "used_on" => page_paths,
          "created_at" => Time.now.to_i,
          "provider" => provider
        }
      end
    end

    # Check if image version is default type
    def default_version?(original_name, operations)
      return false unless @manifest[original_name]

      versions = @manifest.dig(original_name, "versions", "default") || []
      versions.any? { |v| v["operations"] == operations }
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
        output_file = File.join(@site.source, orphan["output"])
        if File.exist?(output_file)
          File.delete(output_file)
          cleaned << orphan["output"]
          Jekyll.logger.info "🗑️  Cleaned orphaned image: #{orphan['output']}"
        end

        # Remove from manifest
        versions = @manifest.dig(orphan["original"], "versions", "specialized") || []
        versions.reject! { |v| v["operations"] == orphan["operations"] }
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
  end
end
