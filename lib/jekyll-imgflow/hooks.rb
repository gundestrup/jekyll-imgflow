# frozen_string_literal: true

module JekyllImgFlow
  # Initialize ImgFlow components on site
  Jekyll::Hooks.register :site, :after_init do |site|
    Jekyll.logger.info "🔌 ImgFlow: Initializing components on site"

    # Add imgflow_components attribute to site if not already present
    unless site.respond_to?(:imgflow_components)
      site.define_singleton_method(:imgflow_components) { @imgflow_components }
      site.define_singleton_method(:imgflow_components=) { |value| @imgflow_components = value }
    end

    # Components will be initialized on first use (lazy loading)
    Jekyll.logger.info "✅ ImgFlow: Components ready for initialization"
  end

  # BuildTimeProcessor runs BEFORE template rendering - ideal architecture
  Jekyll::Hooks.register :site, :pre_render do |site|
    Jekyll.logger.info "🔌 ImgFlow pre_render hook - creating default versions"

    # Initialize and run BuildTimeProcessor
    build_time_processor = BuildTimeProcessor.new(site)
    build_time_processor.process_changed_images

    Jekyll.logger.info "✅ ImgFlow: Default versions created and manifest saved"
  end

  # Save final manifest after template rendering (single writer)
  Jekyll::Hooks.register :site, :post_write do |site|
    Jekyll.logger.info "🔌 ImgFlow post_write hook - saving final manifest with page usage"

    if site.imgflow_components && site.imgflow_components[:manifest]
      site.imgflow_components[:manifest].save
      Jekyll.logger.info "✅ ImgFlow: Final manifest saved with all page usage data"
    else
      Jekyll.logger.warn "⚠️  ImgFlow: No manifest found to save"
    end

    # Clean up orphaned specialized images in production
    cleanup_orphaned_images(site) if Jekyll.env != "development"
  end

  def self.cleanup_orphaned_images(site)
    Jekyll.logger.info "🧹 ImgFlow: Checking for orphaned specialized images..."

    # Use ManifestManager to find and cleanup orphans
    manifest = ManifestManager.new(site)
    cleaned = manifest.cleanup_orphans

    if cleaned.any?
      Jekyll.logger.info "✅ ImgFlow: Removed #{cleaned.length} orphaned specialized images"
    else
      Jekyll.logger.info "✅ ImgFlow: No orphaned images found"
    end
  end
end
