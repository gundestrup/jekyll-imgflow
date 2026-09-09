# frozen_string_literal: true

require_relative "providers/base_provider"

module JekyllImgFlow
  class ProviderRegistry
    # Providers that don't work programmatically (manual use only)
    MANUAL_ONLY_PROVIDERS = [].freeze

    def initialize(config)
      @config = config
      self.class.discover_providers unless self.class.providers_discovered?
    end

    # Files in providers/ that are not provider classes (modules, helpers)
    NON_PROVIDER_FILES = %w[base_provider.rb].freeze

    # Dynamic provider discovery
    def self.discover_providers
      return if @providers_discovered

      @provider_registry ||= {}
      providers_dir = File.join(File.dirname(__FILE__), "providers")

      Dir.glob(File.join(providers_dir, "*.rb")).each do |file|
        basename = File.basename(file)
        next if NON_PROVIDER_FILES.include?(basename)

        provider_name = File.basename(file, ".rb")
        register_provider(provider_name)
      end

      @providers_discovered = true
      Jekyll.logger.debug "ImgFlow:", "Discovered #{@provider_registry.size} providers"
    end

    def self.register_provider(name)
      class_name = name.split("_").map(&:capitalize).join

      begin
        require_relative "providers/#{name}"
        provider_class = JekyllImgFlow::Providers.const_get(class_name)
        @provider_registry[name.to_sym] = provider_class
        Jekyll.logger.debug "ImgFlow:", "Registered provider: #{class_name}"
      rescue NameError => e
        Jekyll.logger.warn "ImgFlow:", "Failed to load provider #{name}: #{e.message}"
      rescue LoadError => e
        Jekyll.logger.warn "ImgFlow:", "Failed to require provider #{name}: #{e.message}"
      end
    end

    def self.provider_registry
      @provider_registry ||= {}
    end

    def self.providers_discovered?
      @providers_discovered ||= false
    end

    # Get all providers that are currently available (running/installed)
    def self.get_available_providers(config)
      registry = new(config)
      registry.providers.select(&:available?)
    end

    # Get all providers with their availability status
    def self.get_all_providers_with_status(config)
      registry = new(config)
      registry.providers.map do |provider|
        {
          name: provider.class.name.split("::").last,
          class: provider.class,
          instance: provider,
          available: provider.available?
        }
      end
    end

    # Get current provider (first available from priority list).
    # If no provider is available, logs a warning and returns nil.
    # The caller should check for nil and handle gracefully.
    def current_provider
      provider = providers.find(&:available?)
      return provider if provider

      configured = @config.backend_priority.join(", ")
      Jekyll.logger.warn "ImgFlow:",
                         "No available image provider found. " \
                         "Configured backends: #{configured}. " \
                         "Install one of: sharp, libvips, imagemagick, " \
                         "or start the Docker HTTP providers."
      nil
    end

    # Get list of available provider names
    def available_providers
      available = providers.select(&:available?)
      available.map! { |p| p.class.name.split("::").last }
    end

    def providers
      @providers ||= @config.backend_priority.filter_map do |name|
        # Skip manual-only providers (they don't have programmatic APIs)
        if MANUAL_ONLY_PROVIDERS.include?(name)
          Jekyll.logger.debug "ImgFlow:",
                              "Skipping '#{name}' - manual use only (no programmatic API)"
          next
        end

        # Dynamic provider loading from registry
        provider_class = self.class.provider_registry[name.to_sym]
        if provider_class
          provider_class.new(@config)
        else
          Jekyll.logger.warn "ImgFlow:", "Unknown provider '#{name}' - not found in registry"
          nil
        end
      end
    end
  end
end
