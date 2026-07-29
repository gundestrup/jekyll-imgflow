# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::ProviderRegistry, :unit do
  let(:site) { double("site", config: TEST_CONFIG) }
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:registry) { described_class.new(config) }
  # Dynamic provider discovery from config
  let(:expected_provider_names) { config.backend_priority }
  let(:expected_provider_classes) do
    expected_provider_names.map do |provider_name|
      Kernel.const_get("JekyllImgFlow::Providers::#{provider_name.capitalize}")
    end
  end

  # Helper methods to reduce repetition and improve maintainability
  def create_config_with_priority(priority_list)
    config = Marshal.load(Marshal.dump(TEST_CONFIG))
    config["imgflow"]["backend_priority"] = priority_list
    config
  end

  def create_registry_with_priority(priority_list)
    config = create_config_with_priority(priority_list)
    site = double("site", config: config)
    config_obj = JekyllImgFlow::Config.new(site)
    described_class.new(config_obj)
  end

  def create_imgflow_config_with_priority(priority_list)
    base_config = Marshal.load(Marshal.dump(TEST_CONFIG))
    base_config["imgflow"]["backend_priority"] = priority_list
    base_config
  end

  def expect_providers_in_order(providers, expected_provider_names)
    expect(providers.length).to eq(expected_provider_names.length)

    providers.each_with_index do |provider, index|
      expected_class_name = "JekyllImgFlow::Providers::#{expected_provider_names[index].capitalize}"
      expected_class = Kernel.const_get(expected_class_name)
      expect(provider).to be_a(expected_class),
                          "Expected provider at index #{index} to be #{expected_class_name}, but got #{provider.class}"
    end
  end

  describe "#providers" do
    it "returns ordered list of all configured providers" do
      providers = registry.providers
      expect(providers).to be_an(Array)

      # Verify all providers are returned in the configured priority order (dynamic)
      expect(providers.length).to eq(expected_provider_names.length)
      expect_providers_in_order(providers, expected_provider_names)
    end

    it "respects backend priority configuration" do
      # Test with different priority order using helper method
      reversed_priority = %w[flyimg weserv libvips imagemagick sharp imgproxy]
      reversed_registry = create_registry_with_priority(reversed_priority)

      providers = reversed_registry.providers
      expect_providers_in_order(providers, reversed_priority)
    end

    it "handles empty backend priority gracefully" do
      empty_registry = create_registry_with_priority([])

      providers = empty_registry.providers
      expect(providers).to be_an(Array)
      expect(providers).to be_empty
    end

    it "handles subset of providers correctly" do
      subset_priority = %w[sharp libvips weserv]
      subset_registry = create_registry_with_priority(subset_priority)

      providers = subset_registry.providers
      expect_providers_in_order(providers, subset_priority)
    end
  end

  describe "#initialize" do
    it "accepts config parameter" do
      expect(registry).to be_a(described_class)
      expect(registry.instance_variable_get(:@config)).to eq(config)
    end
  end

  describe ".get_available_providers" do
    it "returns only available providers" do
      available_providers = described_class.get_available_providers(config)

      expect(available_providers).to be_an(Array)
      # Should only include providers that are available
      available_providers.each do |provider|
        expect(provider).to respond_to(:available?)
        expect(provider.available?).to be true
      end
    end

    it "returns empty array when no providers are available" do
      # Create a config with non-existent providers
      empty_config = create_config_with_priority(["nonexistent_provider"])
      described_class.new(empty_config)

      # Mock all providers as unavailable
      allow_any_instance_of(described_class).to receive(:providers).and_return([])

      available_providers = described_class.get_available_providers(empty_config)
      expect(available_providers).to eq([])
    end
  end

  describe ".get_all_providers_with_status" do
    it "returns all providers with availability status" do
      providers_with_status = described_class.get_all_providers_with_status(config)

      expect(providers_with_status).to be_an(Array)
      expect(providers_with_status.length).to eq(expected_provider_names.length)

      providers_with_status.each do |provider_info|
        expect(provider_info).to have_key(:name)
        expect(provider_info).to have_key(:class)
        expect(provider_info).to have_key(:instance)
        expect(provider_info).to have_key(:available)

        expect(provider_info[:name]).to be_a(String)
        expect(provider_info[:class]).to be_a(Class)
        expect(provider_info[:available]).to be(true).or(be(false))
        expect(provider_info[:available]).to eq(provider_info[:instance].available?)
      end
    end
  end

  describe "#current_provider" do
    it "returns the first available provider" do
      current_provider = registry.current_provider

      expect(current_provider.available?).to be true if current_provider
    end

    it "returns nil when no providers are available" do
      empty_registry = create_registry_with_priority([])

      expect(empty_registry.current_provider).to be_nil
    end
  end

  describe "#available_providers" do
    it "returns list of available provider names" do
      available_provider_names = registry.available_providers

      expect(available_provider_names).to be_an(Array)
      available_provider_names.each do |name|
        expect(name).to be_a(String)
        expect(expected_provider_names).to include(name.downcase)
      end
    end

    it "returns empty list when no providers are available" do
      empty_registry = create_registry_with_priority([])

      expect(empty_registry.available_providers).to eq([])
    end
  end

  describe "manual-only providers" do
    it "skips manual-only providers" do
      # Test with a manual-only provider in the list
      config_with_manual = create_imgflow_config_with_priority(%w[sharp nonexistent_manual])
      site_with_manual = double("site", config: config_with_manual)
      config_obj_with_manual = JekyllImgFlow::Config.new(site_with_manual)

      # Mock the MANUAL_ONLY_PROVIDERS constant
      stub_const("JekyllImgFlow::ProviderRegistry::MANUAL_ONLY_PROVIDERS", ["nonexistent_manual"])

      registry_with_manual = described_class.new(config_obj_with_manual)
      providers = registry_with_manual.providers

      # Should only include non-manual providers
      expect(providers.length).to eq(1)
      expect(providers.first).to be_a(JekyllImgFlow::Providers::Sharp)
    end
  end

  describe "edge cases" do
    it "handles unknown provider names gracefully" do
      config_with_unknown = create_imgflow_config_with_priority(%w[sharp unknown_provider
                                                                   libvips])
      site_with_unknown = double("site", config: config_with_unknown)
      config_obj_with_unknown = JekyllImgFlow::Config.new(site_with_unknown)
      registry_with_unknown = described_class.new(config_obj_with_unknown)

      providers = registry_with_unknown.providers

      # Should skip unknown provider and only include known ones
      expect(providers.length).to eq(2)
      expect(providers[0]).to be_a(JekyllImgFlow::Providers::Sharp)
      expect(providers[1]).to be_a(JekyllImgFlow::Providers::Libvips)
    end

    it "caches providers instance" do
      providers_first = registry.providers
      providers_second = registry.providers

      # Should return same instance (cached)
      expect(providers_first).to be(providers_second)
    end
  end

  describe "dynamic provider discovery" do
    it "discovers all providers from filesystem" do
      # Force re-discovery
      described_class.instance_variable_set(:@providers_discovered, false)
      described_class.instance_variable_set(:@provider_registry, {})

      described_class.discover_providers

      registry = described_class.provider_registry
      expect(registry).to be_a(Hash)
      expect(registry.size).to be >= 6

      # Check that all expected providers are registered
      expect(registry).to have_key(:sharp)
      expect(registry).to have_key(:imagemagick)
      expect(registry).to have_key(:libvips)
      expect(registry).to have_key(:imgproxy)
      expect(registry).to have_key(:weserv)
      expect(registry).to have_key(:flyimg)
    end

    it "registers provider classes correctly" do
      registry = described_class.provider_registry

      # Check that registered classes are actual provider classes
      registry.each_value do |provider_class|
        expect(provider_class).to be_a(Class)
        expect(provider_class.ancestors).to include(JekyllImgFlow::Providers::BaseProvider)
      end
    end

    it "only discovers providers once" do
      # First discovery
      described_class.instance_variable_set(:@providers_discovered, false)
      described_class.discover_providers
      first_registry = described_class.provider_registry.dup

      # Second call should not re-discover
      described_class.discover_providers
      second_registry = described_class.provider_registry

      expect(first_registry).to eq(second_registry)
    end

    it "marks discovery as complete" do
      described_class.instance_variable_set(:@providers_discovered, false)
      expect(described_class.providers_discovered?).to be false

      described_class.discover_providers
      expect(described_class.providers_discovered?).to be true
    end
  end

  describe ".provider_registry" do
    it "returns hash of registered providers" do
      registry = described_class.provider_registry

      expect(registry).to be_a(Hash)
      expect(registry).not_to be_empty
    end

    it "uses symbols as keys" do
      registry = described_class.provider_registry

      expect(registry.keys).to all(be_a(Symbol))
    end

    it "stores provider classes as values" do
      registry = described_class.provider_registry

      registry.each_value do |provider_class|
        expect(provider_class).to be_a(Class)
        expect(provider_class.ancestors).to include(JekyllImgFlow::Providers::BaseProvider)
      end
    end
  end

  describe ".register_provider" do
    it "registers a provider by name" do
      # Reset registry
      described_class.instance_variable_set(:@provider_registry, {})
      described_class.instance_variable_set(:@providers_discovered, false)

      described_class.register_provider("sharp")

      registry = described_class.provider_registry
      expect(registry).to have_key(:sharp)
      expect(registry[:sharp]).to eq(JekyllImgFlow::Providers::Sharp)

      # Re-discover for other tests
      described_class.instance_variable_set(:@providers_discovered, false)
      described_class.discover_providers
    end

    it "handles provider names with underscores" do
      # Test that multi-word provider names are handled correctly
      # (e.g., 'my_custom_provider' -> 'MyCustomProvider')
      registry = described_class.provider_registry

      # All current providers are single word, but the logic should handle underscores
      registry.each do |name, provider_class|
        expected_class_name = name.to_s.split("_").map(&:capitalize).join
        expect(provider_class.name).to end_with(expected_class_name)
      end
    end
  end

  describe "provider instantiation" do
    it "instantiates providers with config" do
      providers = registry.providers

      providers.each do |provider|
        expect(provider.config).to eq(config)
      end
    end

    it "creates new instances for each registry" do
      registry1 = described_class.new(config)
      registry2 = described_class.new(config)

      providers1 = registry1.providers
      providers2 = registry2.providers

      # Different registry instances should have different provider instances
      providers1.each_with_index do |provider1, index|
        provider2 = providers2[index]
        expect(provider1).not_to be(provider2)
      end
    end
  end

  describe "integration with config" do
    it "respects config backend_priority order" do
      custom_order = %w[flyimg sharp libvips]
      custom_registry = create_registry_with_priority(custom_order)

      providers = custom_registry.providers
      expect(providers[0]).to be_a(JekyllImgFlow::Providers::Flyimg)
      expect(providers[1]).to be_a(JekyllImgFlow::Providers::Sharp)
      expect(providers[2]).to be_a(JekyllImgFlow::Providers::Libvips)
    end

    it "filters providers based on config" do
      subset = %w[sharp imagemagick]
      subset_registry = create_registry_with_priority(subset)

      providers = subset_registry.providers
      expect(providers.length).to eq(2)
    end
  end
end
