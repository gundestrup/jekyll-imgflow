# frozen_string_literal: true

require "spec_helper"
require_relative "support/parallel_provider_test_helper"

RSpec.describe "Provider Interface Compliance - Clean & DRY", :external, :provider do
  # Allow network connections for HTTP provider availability checks
  before do
    WebMock.allow_net_connect!
  end

  # Define test data once - this is the key to avoiding duplication
  let(:required_methods) do
    %i[resize crop quality= convert_format execute add_watermark alpha_opacity=
       reset_operations operations available?]
  end
  let(:tag_classes) do
    # Dynamic discovery from TagRegistry - automatically includes all registered tags
    tag_registry = JekyllImgFlow::Tags::TagRegistry
    registered_tags = tag_registry.available_tags

    tag_classes = registered_tags.filter_map do |tag_name|
      tag_class = tag_registry.get_tag(tag_name)
      tag_class if tag_class && tag_class < JekyllImgFlow::Tags::BaseTag
    end

    tag_classes
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

  # Helper methods - defined once, used everywhere
  def test_provider_signatures(provider_instance, provider_name)
    # Test signature patterns for different method types
    no_signature_methods = %i[operations available? reset_operations]
    signature_test_methods = required_methods.reject do |m|
      m == :execute || m.to_s.end_with?("=") || no_signature_methods.include?(m)
    end

    signature_test_methods.each do |method|
      method_params = provider_instance.method(method).parameters

      case method
      when :convert_format
        # convert_format has required format parameter
        expect(method_params).to include(%i[req format]),
                                 "Provider #{provider_name} #{method} should " \
                                 "require format parameter"
      when :crop
        # crop takes ratio_or_width plus optional height_val/x_val/y_val
        expect(method_params).to include(%i[req ratio_or_width]),
                                 "Provider #{provider_name} #{method} should " \
                                 "require ratio_or_width parameter"
        expect(method_params).to include(%i[opt height_val]),
                                 "Provider #{provider_name} #{method} should " \
                                 "accept optional height_val parameter"
      when :add_watermark
        # add_watermark has required watermark_path parameter
        expect(method_params).to include(%i[req watermark_path]),
                                 "Provider #{provider_name} #{method} should " \
                                 "require watermark_path parameter"
        expect(method_params).to include(%i[opt options]),
                                 "Provider #{provider_name} #{method} should " \
                                 "accept options hash"
      else
        # Other methods should accept options hash
        expect(method_params).to include(%i[opt options]),
                                 "Provider #{provider_name} #{method} should " \
                                 "accept options hash"
      end
    end
  end

  def test_operation_management(provider_instance, _provider_name)
    # Test operation collection methods
    provider_instance.reset_operations

    # Test that operations start empty
    expect(provider_instance.operations).to be_an(Array)
    expect(provider_instance.operations).to be_empty

    # Test adding operations
    provider_instance.resize(800, 600)
    provider_instance.crop("16:9")
    provider_instance.send(:quality=, 85)
    provider_instance.convert_format("webp")
    provider_instance.add_watermark("watermark.png", { opacity: 0.5 })
    provider_instance.send(:alpha_opacity=, 0.8)

    # Check operations were collected
    operations = provider_instance.operations
    expect(operations.length).to eq(6)

    # Verify operation structure
    expect(operations[0]).to have_key(:type)
    expect(operations[0]).to have_key(:width)
    expect(operations[0]).to have_key(:height)
    expect(operations[0][:type]).to eq(:resize)

    # Test reset operations
    provider_instance.reset_operations
    expect(provider_instance.operations).to be_empty
  end

  def test_availability_check(provider_instance, _provider_name)
    # Test availability method exists and returns boolean
    availability = provider_instance.available?
    expect(availability).to be(true).or(be(false))
  end

  def test_helper_methods(provider_instance, _provider_name)
    # Test that provider has access to config
    expect(provider_instance.config).to be_a(JekyllImgFlow::Config)
  end

  def test_tag_integration(provider_instance, provider_name)
    tag_classes.each do |tag_class|
      instance = tag_class.new(provider_instance)
      expect(instance).to be_a(JekyllImgFlow::Tags::BaseTag),
                          "Provider #{provider_name} should work with #{tag_class.name}"
    end
  end

  def test_provider_instantiation(provider_class, config, provider_name)
    instance = provider_class.new(config)
    expect(instance).to be_a(JekyllImgFlow::Providers::BaseProvider),
                        "Provider #{provider_name} should be a BaseProvider"
  end

  describe "All Available Providers" do
    it "has at least one provider available" do
      expect(all_providers).not_to be_empty, "Should have at least one provider"
    end

    # The key insight: ONE test that loops through ALL providers
    # This avoids duplication - test logic is defined once in helper methods above
    it "tests all providers with the same test suite (DRY approach)" do
      all_providers.each do |provider_info|
        provider_instance = provider_info[:instance]
        provider_name = provider_info[:name]
        provider_class = provider_info[:class]
        config = provider_info[:config]

        # Run the same tests on every provider - NO DUPLICATION!
        test_provider_signatures(provider_instance, provider_name)

        test_operation_management(provider_instance, provider_name)

        test_availability_check(provider_instance, provider_name)

        test_helper_methods(provider_instance, provider_name)

        test_tag_integration(provider_instance, provider_name)

        test_provider_instantiation(provider_class, config, provider_name)
      end
    end
  end

  describe "Tag Interface Compliance" do
    it "all tag classes define standard interface" do
      tag_classes.each do |tag_class|
        expect(tag_class.instance_methods).to include(:process),
                                              "Tag #{tag_class.name} should include process method"
      end
    end

    it "tag registry maintains consistent registration" do
      registered_tags = JekyllImgFlow::Tags::TagRegistry.available_tags

      expect(registered_tags).to include(:resize, :crop, :quality, :format, :optimize, :watermark)

      registered_tags.each do |tag_name|
        tag_class = JekyllImgFlow::Tags::TagRegistry.get_tag(tag_name)
        expect(tag_class).not_to be_nil, "Tag #{tag_name} should be registered"
        expect(tag_class).to be < JekyllImgFlow::Tags::BaseTag,
                             "Tag #{tag_name} should inherit from BaseTag"
      end
    end
  end
end
