# frozen_string_literal: true

require "spec_helper"
require_relative "support/parallel_provider_test_helper"

RSpec.describe "Provider Comprehensive Meta-Testing", :external, :provider do
  # Allow network connections for HTTP provider availability checks
  before do
    WebMock.allow_net_connect!
  end

  let(:site) { double("site", config: TEST_CONFIG, source: "/tmp/test_site") }
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:registry) { JekyllImgFlow::ProviderRegistry.new(config) }
  let(:test_image) { TestPictures.get(:default).first }

  # Get all available providers from registry
  let(:available_providers) do
    registry.providers.select(&:available?)
  end

  let(:provider_instances) do
    available_providers
  end

  describe "Provider Discovery and Registration" do
    it "discovers all expected providers" do
      expected_providers = %i[sharp imagemagick libvips imgproxy weserv flyimg]
      discovered_providers = JekyllImgFlow::ProviderRegistry.provider_registry.keys

      expect(discovered_providers).to match_array(expected_providers)
    end

    it "creates provider instances correctly" do
      available_providers.each do |provider|
        expect(provider).to be_a(JekyllImgFlow::Providers::BaseProvider)
        expect(provider).to respond_to(:config)
        expect(provider).to respond_to(:available?)
      end
    end
  end

  describe "Provider Capability Matrix" do
    let(:all_operations) { %i[crop format opacity optimize quality resize watermark] }

    it "generates comprehensive capability matrix" do
      printf("%-12s", "Provider")
      all_operations.each { |op| printf("%-10s", op.to_s.capitalize) }

      capability_matrix = {}

      available_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        capabilities = []

        all_operations.each do |operation|
          supports = provider.supports_operation?(operation)
          capabilities << supports
          printf("%-10s", supports ? "✅" : "❌")
        end

        printf("%-10s\n", provider.available? ? "✅" : "❌")
        capability_matrix[provider_name] = capabilities
      end

      # Validate that each operation has at least one provider
      all_operations.each_with_index do |operation, index|
        providers_supporting = capability_matrix.select { |_name, caps| caps[index] }
        expect(providers_supporting).not_to be_empty,
                                            "No providers support operation: #{operation}"
      end
    end
  end

  describe "Provider Method Coverage" do
    let(:base_provider_methods) do
      JekyllImgFlow::Providers::BaseProvider.instance_methods(false)
    end

    it "ensures all providers implement required methods" do
      required_methods = %i[crop format opacity optimize quality resize watermark
                            execute available? config operations reset_operations]

      provider_instances.each do |provider|
        provider_name = provider.class.name.split("::").last

        required_methods.each do |method|
          expect(provider).to respond_to(method),
                              "#{provider_name} does not implement #{method}"
        end
      end
    end

    it "tests provider-specific method signatures" do
      provider_instances.each do |provider|
        provider_name = provider.class.name.split("::").last

        # Test method arity and basic behavior
        test_methods = {
          available?: 0,
          config: 0,
          operations: 0,
          reset_operations: 0
        }

        test_methods.each do |method, expected_arity|
          actual_arity = provider.method(method).arity
          expect(actual_arity).to eq(expected_arity),
                                  "#{provider_name}##{method} should have arity #{expected_arity}, got #{actual_arity}"
        end
      end
    end
  end

  describe "Provider Configuration Handling" do
    it "handles configuration correctly" do
      provider_instances.each do |provider|
        provider.class.name.split("::").last

        # Test config access
        expect(provider.config).to be_a(JekyllImgFlow::Config)

        # Test config changes affect provider
        new_config = config

        expect { provider.config = new_config }.not_to raise_error
        expect(provider.config).to eq(new_config)
      end
    end
  end

  describe "Provider Operation Execution Testing" do
    let(:test_output_dir) { create_test_dir("provider-execution-test") }
    let(:test_input_path) { File.join("spec/fixtures/originals", test_image) }

    after do
      FileUtils.rm_rf(test_output_dir) if test_output_dir && Dir.exist?(test_output_dir)
    end

    it "tests operation method existence and collects operations correctly" do
      provider_instances.each do |provider|
        provider.class.name.split("::").last
        next unless provider.available?

        provider.reset_operations

        # Test each operation method with real parameters and verify collection
        provider.resize(800, 600)
        expect(provider.operations.last[:type]).to eq(:resize)
        expect(provider.operations.last[:width]).to eq(800)
        expect(provider.operations.last[:height]).to eq(600)

        provider.crop("16:9")
        expect(provider.operations.last[:type]).to eq(:crop)
        expect(provider.operations.last[:ratio]).to eq("16:9")

        provider.send(:quality=, 85)
        expect(provider.operations.last[:type]).to eq(:quality)
        expect(provider.operations.last[:quality]).to eq(85)

        provider.convert_format("webp")
        expect(provider.operations.last[:type]).to eq(:format)
        expect(provider.operations.last[:format]).to eq("webp")

        provider.add_watermark("watermark.png", { opacity: 0.5 })
        expect(provider.operations.last[:type]).to eq(:watermark)

        provider.send(:alpha_opacity=, 0.8)
        expect(provider.operations.last[:type]).to eq(:alpha_opacity)
        expect(provider.operations.last[:opacity]).to eq(0.8)

        # Verify total operations collected
        expect(provider.operations.length).to eq(6)

        provider.reset_operations
      end
    end

    it "tests operation chaining and reset" do
      provider_instances.each do |provider|
        provider.class.name.split("::").last
        next unless provider.available?

        # Test operation chaining
        provider.resize(800, 600)
        provider.quality(80)
        provider.format(:webp)

        expect(provider.operations.length).to eq(3)
        expect(provider.operations.map do |op|
                 op[:type]
               end).to contain_exactly(:resize, :quality, :format)

        # Test reset operations
        provider.reset_operations
        expect(provider.operations).to be_empty
      end
    end
  end

  describe "Provider Error Handling" do
    it "handles invalid parameters by collecting them without raising" do
      provider_instances.each do |provider|
        provider.class.name.split("::").last
        next unless provider.available?

        provider.reset_operations

        # Invalid dimensions - provider collects without validation (validation is in tags)
        provider.resize(-1, -1)
        expect(provider.operations.last[:type]).to eq(:resize)
        expect(provider.operations.last[:width]).to eq(-1)

        # Invalid quality - provider collects without validation
        provider.send(:quality=, 150)
        expect(provider.operations.last[:type]).to eq(:quality)
        expect(provider.operations.last[:quality]).to eq(150)

        # Invalid format - provider collects without validation
        provider.convert_format(:invalid_format)
        expect(provider.operations.last[:type]).to eq(:format)

        provider.reset_operations
      end
    end
  end

  describe "Provider Performance Characteristics" do
    it "measures provider method performance" do
      provider_instances.each do |provider|
        provider_name = provider.class.name.split("::").last
        next unless provider.available?

        # Measure operation setup performance
        start_time = Time.now

        100.times do
          provider.resize(800, 600)
          provider.quality(80)
          provider.reset_operations
        end

        elapsed = Time.now - start_time
        (300 / elapsed).round(2)

        # Performance should be reasonable (not too slow)
        expect(elapsed).to be < 5.0, "#{provider_name} is too slow for basic operations"
      end
    end
  end

  describe "Provider Network and External Dependencies" do
    it "tests HTTP provider connectivity" do
      http_providers = provider_instances.select do |provider|
        provider.class.name.include?("Imgproxy") ||
          provider.class.name.include?("Weserv") ||
          provider.class.name.include?("Flyimg")
      end

      http_providers.each do |provider|
        provider_name = provider.class.name.split("::").last

        # Test availability check (may involve network)
        start_time = Time.now
        provider.available?
        elapsed = Time.now - start_time

        # Availability check should be reasonably fast
        expect(elapsed).to be < 10.0, "#{provider_name} availability check too slow"
      end
    end
  end

  describe "Provider Coverage Summary" do
    it "generates comprehensive coverage report" do
      skip "Single provider mode" if ENV["IMGFLOW_TEST_PROVIDER"]
      total_providers = JekyllImgFlow::ProviderRegistry.provider_registry.length
      available_count = available_providers.length
      coverage_percentage = (available_count.to_f / total_providers * 100).round(1)

      available_providers.each do |provider|
        provider.class.name.split("::").last

        provider.operations.select do |operation|
          provider.supports_operation?(operation[:type])
        end
      end

      # Ensure we have good coverage
      expect(coverage_percentage).to be >= 50, "Provider availability coverage too low"
    end
  end
end
