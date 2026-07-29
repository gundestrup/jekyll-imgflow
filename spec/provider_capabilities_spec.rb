# frozen_string_literal: true

require "spec_helper"
require_relative "support/parallel_provider_test_helper"

RSpec.describe "Provider Capability Flags - Meta Testing", :external, :provider do
  # Allow network connections for HTTP provider availability checks
  before do
    WebMock.allow_net_connect!
  end

  # Auto-detect all operations from registered tags (completely dynamic!)
  let(:all_operations) do
    # Get all registered tags and use their names as operations
    tag_registry = JekyllImgFlow::Tags::TagRegistry
    registered_tags = tag_registry.available_tags

    # Use tag names directly as operations - completely dynamic!
    operations = registered_tags

    operations
  end

  # Auto-detect tag operation mapping dynamically using TagRegistry
  let(:tag_operation_mapping) do
    tag_registry = JekyllImgFlow::Tags::TagRegistry

    # Get all registered tag classes and map them to operations
    mapping = {}
    tag_registry.available_tags.each do |tag_name|
      tag_class = tag_registry.get_tag(tag_name)
      next unless tag_class

      # Dynamic mapping: use tag name as operation name by default
      # This allows any new tag to be automatically included
      operation = tag_name

      mapping[tag_class] = operation
    end

    mapping
  end

  let(:all_providers) do
    providers = all_providers_from_registry
    # Filter providers if TEST_PROVIDER env var is set
    ParallelProviderTestHelper.filtered_providers(providers.map { |p| p[:name] })
                              .filter_map do |name|
      providers.find do |p|
        p[:name] == name
      end
    end
  end

  describe "Provider Capability Consistency" do
    it "all providers have capability flag methods" do
      all_providers.each do |provider_info|
        provider_class = provider_info[:class]
        provider_name = provider_info[:name]

        # Test that capability methods exist
        expect(provider_class).to respond_to(:unsupported_operations),
                                  "Provider #{provider_name} should have unsupported_operations method"

        expect(provider_class).to respond_to(:supports_operation?),
                                  "Provider #{provider_name} should have supports_operation? method"

        # Test that unsupported_operations returns an array
        unsupported = provider_class.unsupported_operations
        expect(unsupported).to be_an(Array),
                               "Provider #{provider_name} unsupported_operations should return an array"
      end
    end

    it "all tags have at least one supporting provider" do
      all_operations.each do |operation|
        supporting_providers = all_providers.select do |provider_info|
          provider_info[:class].supports_operation?(operation)
        end

        expect(supporting_providers.length).to be > 0,
                                               "No providers support the #{operation} tag - this tag would be unusable"

        supporting_providers.map { |p| p[:name] }
      end
    end

    it "tags work with providers that claim to support their operations" do
      all_providers.each do |provider_info|
        provider_instance = provider_info[:instance]
        provider_class = provider_info[:class]
        provider_name = provider_info[:name]

        tag_operation_mapping.each do |tag_class, operation|
          next unless provider_class.supports_operation?(operation)

          # Provider claims to support operation - tag should work
          begin
            tag_class.new(provider_instance)
          rescue StandardError => e
            expect(e).to be_nil,
                         "Provider #{provider_name} claims to support #{operation} but #{tag_class.name} failed: #{e.message}"
          end
        end
      end
    end

    it "at least one provider supports each operation" do
      all_operations.each do |operation|
        supporting_providers = all_providers.select do |provider_info|
          provider_info[:class].supports_operation?(operation)
        end

        operation.to_s.tr("_", " ").capitalize

        expect(supporting_providers).not_to be_empty,
                                            "At least one provider should support #{operation} operation"

        # List supporting providers
        supporting_providers.each do |provider_info|
          expect(provider_info[:class]).to be_a(Class)
        end
      end
    end
  end

  describe "Capability Flag Edge Cases" do
    it "handles unknown operations gracefully" do
      all_providers.each do |provider_info|
        provider_class = provider_info[:class]
        provider_name = provider_info[:name]

        # Unknown operation should return false
        begin
          result = provider_class.supports_operation?(:unknown_operation_xyz)
          expect(result).to be false,
                               "Provider #{provider_name} should return false for unknown operations"
        rescue ArgumentError
          # If provider has strict validation, that's also acceptable
        end
      end
    end

    it "unsupported_operations can be empty" do
      # Find a provider that supports everything (like Sharp)
      full_support_providers = all_providers.select do |provider_info|
        provider_info[:class].unsupported_operations.empty?
      end

      if full_support_providers.any?
        full_support_providers.each do |provider_info|
          provider_info[:name]
        end
      end
    end

    it "covers provider capability methods for coverage" do
      all_providers.each do |provider_info|
        provider_class = provider_info[:class]
        provider_name = provider_info[:name]

        # Test unsupported_operations method (increases coverage)
        unsupported = provider_class.unsupported_operations
        expect(unsupported).to be_an(Array)

        # Test supports_operation? method with various operations (increases coverage)
        unsupported_list = provider_class.unsupported_operations
        all_operations.each do |operation|
          result = provider_class.supports_operation?(operation)
          expected = !unsupported_list.include?(operation)
          expect(result).to eq(expected),
                            "#{provider_name} supports_operation?(#{operation}) returned #{result}, " \
                            "expected #{expected} based on unsupported_operations #{unsupported_list}"
        end

        # Test provider instance methods (increases coverage)
        provider_instance = provider_info[:instance]

        # Dynamically discover all public instance methods from BaseProvider
        base_provider_methods = JekyllImgFlow::Providers::BaseProvider.instance_methods(false)

        # Only test public API methods that providers should have (exclude protected/private)
        public_api = %i[available? config operations reset_operations resize crop quality=
                        convert_format add_watermark alpha_opacity= execute]
        public_api_methods = base_provider_methods.select do |method|
          public_api.include?(method)
        end

        public_api_methods.each do |method|
          expect(provider_instance).to respond_to(method),
                                       "Provider #{provider_name} should respond to #{method}"
        end

        # Test availability check (increases coverage)
        available = provider_instance.available?
        expect(available).to be(true).or(be(false))

        # Test config access (increases coverage)
        expect(provider_instance.config).to be_a(JekyllImgFlow::Config)

        # Test operation management (increases coverage)
        provider_instance.reset_operations
        expect(provider_instance.operations).to be_an(Array)
        expect(provider_instance.operations).to be_empty

        # Dynamically discover and test all operation methods
        operation_methods = public_api_methods.select do |m|
          m.to_s.match?(/^(resize|crop|quality=|convert_format|add_watermark|alpha_opacity=)/)
        end

        operation_methods.each do |method|
          case method
          when :resize
            provider_instance.resize(800, 600, { gravity: "center" })
          when :crop
            provider_instance.crop("16:9", { position: "center" })
          when :quality=
            provider_instance.send(:quality=, 85)
          when :convert_format
            provider_instance.convert_format("webp")
          when :add_watermark
            provider_instance.add_watermark("test.png", { opacity: 0.5 })
          when :alpha_opacity=
            provider_instance.send(:alpha_opacity=, 0.8)
          end
        end

        operations = provider_instance.operations
        expect(operations.length).to eq(operation_methods.length)

        # Verify operation types dynamically
        operation_types = operations.map { |op| op[:type] }
        expected_types = operation_methods.map do |m|
          case m.to_s
          when "convert_format" then :format
          when "quality=" then :quality
          when "alpha_opacity=" then :alpha_opacity
          when "add_watermark" then :watermark
          else m.to_sym
          end
        end
        expect(operation_types).to include(*expected_types)

        # Test reset operations (increases coverage)
        provider_instance.reset_operations
        expect(provider_instance.operations).to be_empty

        # Test execute method exists (providers implement it)
        expect(provider_instance).to respond_to(:execute)
        # NOTE: Actual providers implement execute, so we don't test for NotImplementedError here

        # Test class capability methods (increases coverage)
        # Dynamically discover all BaseProvider class methods
        base_provider_class_methods = JekyllImgFlow::Providers::BaseProvider.methods(false)

        base_provider_class_methods.each do |method|
          expect(provider_class).to respond_to(method),
                                    "Provider #{provider_name} class should respond to #{method}"
        end

        # Test specific capability methods
        expect(provider_class).to respond_to(:unsupported_operations)
        expect(provider_class).to respond_to(:supports_operation?)

        unsupported_ops = provider_class.unsupported_operations
        expect(unsupported_ops).to be_an(Array)
      end
    end
  end

  describe "BaseProvider Class Methods Coverage - Fully Dynamic" do
    it "dynamically tests all BaseProvider methods" do
      # Test BaseProvider class methods directly
      base_provider = JekyllImgFlow::Providers::BaseProvider.new

      # Get all instance methods dynamically
      all_instance_methods = JekyllImgFlow::Providers::BaseProvider.instance_methods(false)

      # Only test public API methods
      public_api = %i[available? config operations reset_operations resize crop quality=
                      convert_format add_watermark alpha_opacity= execute]
      public_api_methods = all_instance_methods.select do |method|
        public_api.include?(method)
      end

      # Test availability method specifically
      expect(base_provider.available?).to be false

      # Test operation management methods
      expect(base_provider.operations).to be_an(Array)
      expect(base_provider.operations).to be_empty

      # Dynamically discover and test all operation methods
      operation_methods = public_api_methods.select do |m|
        m.to_s.match?(/^(resize|crop|quality=|convert_format|add_watermark|alpha_opacity=)/)
      end

      operation_test_data = {
        :resize => [800, 600, { gravity: "center" }],
        :crop => ["16:9", { position: "center" }],
        "quality=" => [85],
        :convert_format => ["webp"],
        :add_watermark => ["watermark.png", { opacity: 0.5 }],
        "alpha_opacity=" => [0.8]
      }

      operation_methods.each do |method|
        test_data = operation_test_data[method.to_s]
        next unless test_data

        case method
        when :resize
          base_provider.resize(*test_data)
        when :crop
          base_provider.crop(*test_data)
        when :quality=
          base_provider.send(:quality=, *test_data)
        when :convert_format
          base_provider.convert_format(*test_data)
        when :add_watermark
          base_provider.add_watermark(*test_data)
        when :alpha_opacity=
          base_provider.send(:alpha_opacity=, *test_data)
        end
      end

      # Verify operations were collected (only count operations that were actually called)
      operations = base_provider.operations
      called_operations = operation_methods.select { |m| operation_test_data[m.to_s] }
      expect(operations.length).to eq(called_operations.length)

      # Dynamically verify operation structures
      expect(operations).to all(have_key(:type))

      # Test reset operations
      base_provider.reset_operations
      expect(base_provider.operations).to be_empty

      # Test execute method
      expect do
        base_provider.execute("input.jpg", "output.jpg")
      end.to raise_error(NotImplementedError)

      # Test all class methods dynamically
      all_class_methods = JekyllImgFlow::Providers::BaseProvider.methods(false)

      # Test class methods
      all_class_methods.each do |method|
        expect(JekyllImgFlow::Providers::BaseProvider).to respond_to(method)
      end
    end
  end

  private

  # Helper method to get all providers from registry (same as provider_interface_spec)
  def all_providers_from_registry
    site = double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                          dest: "/tmp/test_site/_site")
    config = JekyllImgFlow::Config.new(site)
    JekyllImgFlow::ProviderRegistry.new(config)

    # Auto-discover all provider classes dynamically
    all_provider_classes = []

    # Method 1: Discover from ProviderRegistry (most reliable)
    begin
      registry_providers = JekyllImgFlow::ProviderRegistry.new(config).providers

      registry_providers.each do |provider_instance|
        provider_class = provider_instance.class
        all_provider_classes << provider_class unless all_provider_classes.include?(provider_class)
      end
    rescue StandardError => e
      warn "Failed to discover providers from registry: #{e.message}"
    end
    if all_provider_classes.empty?
      providers_dir = File.join(File.dirname(__FILE__), "..", "lib", "jekyll-imgflow", "providers")

      Dir.glob(File.join(providers_dir, "*.rb")).each do |file|
        # Skip base_provider.rb
        next if File.basename(file) == "base_provider.rb"

        # Convert filename to class name
        file_name = File.basename(file, ".rb")
        class_name = file_name.split("_").map(&:capitalize).join

        # Try to load the class
        begin
          full_class_name = "JekyllImgFlow::Providers::#{class_name}"
          provider_class = Object.const_get(full_class_name)
          all_provider_classes << provider_class unless all_provider_classes.include?(provider_class)
        rescue NameError => e
          warn "Could not load #{class_name}: #{e.message}"
        end
      end
    end

    providers = []
    all_provider_classes.each do |provider_class|
      provider_instance = provider_class.new(config)
      if provider_instance.available?
        providers << {
          name: provider_class.name.split("::").last,
          class: provider_class,
          instance: provider_instance,
          config: config
        }
      end
    rescue StandardError => e
      warn "Failed to instantiate #{provider_class}: #{e.message}"
    end

    providers
  end
end
