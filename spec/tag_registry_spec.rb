# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::Tags::TagRegistry, :unit do
  before do
    # Reset registry for clean state
    described_class.reset!
  end

  describe ".discover_tags" do
    it "discovers all tags from filesystem" do
      described_class.discover_tags

      tags = described_class.available_tags
      expect(tags).to be_an(Array)
      expect(tags.size).to be >= 7

      # Check that all expected tags are discovered
      expect(tags).to include(:resize)
      expect(tags).to include(:crop)
      expect(tags).to include(:quality)
      expect(tags).to include(:format)
      expect(tags).to include(:optimize)
      expect(tags).to include(:watermark)
      expect(tags).to include(:opacity)
    end

    it "only discovers tags once" do
      described_class.discover_tags
      first_tags = described_class.available_tags.dup

      # Second call should not re-discover
      described_class.discover_tags
      second_tags = described_class.available_tags

      expect(first_tags).to eq(second_tags)
    end

    it "marks discovery as complete" do
      expect(described_class.tags_discovered?).to be false

      described_class.discover_tags
      expect(described_class.tags_discovered?).to be true
    end

    it "skips base_tag.rb file" do
      described_class.discover_tags

      tags = described_class.available_tags
      expect(tags).not_to include(:base)
      expect(tags).not_to include(:base_tag)
    end
  end

  describe ".register_tag_from_file" do
    it "registers a tag by name" do
      described_class.register_tag_from_file("resize")

      tag_class = described_class.get_tag(:resize)
      expect(tag_class).to eq(JekyllImgFlow::Tags::ResizeTag)
    end

    it "handles tag names with underscores" do
      # Test that multi-word tag names are handled correctly
      # Current tags are single word, but logic should handle underscores
      described_class.discover_tags

      tags = described_class.available_tags
      tags.each do |tag_name|
        tag_class = described_class.get_tag(tag_name)
        expected_class_name = "#{tag_name.to_s.split('_').map(&:capitalize).join}Tag"
        expect(tag_class.name).to end_with(expected_class_name)
      end
    end
  end

  describe ".register_tag" do
    it "registers a tag class" do
      described_class.register_tag(:test_tag, JekyllImgFlow::Tags::ResizeTag)

      expect(described_class.get_tag(:test_tag)).to eq(JekyllImgFlow::Tags::ResizeTag)
    end

    it "uses symbols as keys" do
      described_class.register_tag("string_key", JekyllImgFlow::Tags::CropTag)

      # Should convert string to symbol
      expect(described_class.get_tag(:string_key)).to eq(JekyllImgFlow::Tags::CropTag)
    end
  end

  describe ".get_tag" do
    it "returns tag class for registered tag" do
      described_class.discover_tags

      resize_tag = described_class.get_tag(:resize)
      expect(resize_tag).to eq(JekyllImgFlow::Tags::ResizeTag)
    end

    it "returns nil for unregistered tag" do
      described_class.discover_tags

      unknown_tag = described_class.get_tag(:unknown_tag)
      expect(unknown_tag).to be_nil
    end

    it "triggers discovery if not yet discovered" do
      # Don't call discover_tags manually
      expect(described_class.tags_discovered?).to be false

      # get_tag should trigger discovery
      tag_class = described_class.get_tag(:resize)
      expect(tag_class).to eq(JekyllImgFlow::Tags::ResizeTag)
      expect(described_class.tags_discovered?).to be true
    end
  end

  describe ".available_tags" do
    it "returns array of tag names" do
      described_class.discover_tags

      tags = described_class.available_tags
      expect(tags).to be_an(Array)
      expect(tags).not_to be_empty
    end

    it "returns symbol keys" do
      described_class.discover_tags

      tags = described_class.available_tags
      expect(tags).to all(be_a(Symbol))
    end

    it "triggers discovery if not yet discovered" do
      # Don't call discover_tags manually
      expect(described_class.tags_discovered?).to be false

      # available_tags should trigger discovery
      tags = described_class.available_tags
      expect(tags).not_to be_empty
      expect(described_class.tags_discovered?).to be true
    end

    it "includes all discovered tags" do
      described_class.discover_tags

      tags = described_class.available_tags
      expect(tags).to include(:resize, :crop, :quality, :format, :optimize, :watermark, :opacity)
    end
  end

  describe ".reset!" do
    it "clears registered tags" do
      described_class.discover_tags
      expect(described_class.available_tags).not_to be_empty

      described_class.reset!

      # After reset, tags should be empty until re-discovered
      tags_hash = described_class.instance_variable_get(:@tags)
      expect(tags_hash).to be_empty
    end

    it "resets discovery flag" do
      described_class.discover_tags
      expect(described_class.tags_discovered?).to be true

      described_class.reset!
      expect(described_class.tags_discovered?).to be false
    end

    it "allows re-discovery after reset" do
      described_class.discover_tags
      first_count = described_class.available_tags.size

      described_class.reset!
      described_class.discover_tags
      second_count = described_class.available_tags.size

      expect(first_count).to eq(second_count)
    end
  end

  describe "tag class validation" do
    it "all registered tags inherit from BaseTag" do
      described_class.discover_tags

      tags = described_class.available_tags
      tags.each do |tag_name|
        tag_class = described_class.get_tag(tag_name)
        expect(tag_class.ancestors).to include(JekyllImgFlow::Tags::BaseTag)
      end
    end

    it "all tag classes are instantiable" do
      described_class.discover_tags

      # Create a mock provider - need to discover providers first
      site = double("site", config: TEST_CONFIG)
      config = JekyllImgFlow::Config.new(site)
      registry = JekyllImgFlow::ProviderRegistry.new(config)
      provider = registry.providers.first

      tags = described_class.available_tags
      tags.each do |tag_name|
        tag_class = described_class.get_tag(tag_name)
        instance = tag_class.new(provider)
        expect(instance).to be_a(JekyllImgFlow::Tags::BaseTag)
        expect(instance).to respond_to(:process)
      end
    end

    it "all tag classes have process method" do
      described_class.discover_tags

      tags = described_class.available_tags
      tags.each do |tag_name|
        tag_class = described_class.get_tag(tag_name)
        expect(tag_class.instance_methods).to include(:process)
      end
    end
  end

  describe "integration" do
    it "works with provider interface" do
      described_class.discover_tags

      # Create a provider
      site = double("site", config: TEST_CONFIG)
      config = JekyllImgFlow::Config.new(site)
      registry = JekyllImgFlow::ProviderRegistry.new(config)
      provider = registry.providers.first

      # Test that tags can be instantiated with provider
      tags = described_class.available_tags
      tags.each do |tag_name|
        tag_class = described_class.get_tag(tag_name)
        tag_instance = tag_class.new(provider)

        expect(tag_instance).to be_a(JekyllImgFlow::Tags::BaseTag)
        expect(tag_instance.instance_variable_get(:@provider)).to eq(provider)
      end
    end

    it "tag operations map to provider methods" do
      described_class.discover_tags

      # Create a provider
      site = double("site", config: TEST_CONFIG)
      config = JekyllImgFlow::Config.new(site)
      registry = JekyllImgFlow::ProviderRegistry.new(config)
      provider = registry.providers.first

      # Each tag should correspond to a provider capability
      tag_to_operation = {
        resize: :resize,
        crop: :crop,
        quality: :quality=,
        format: :convert_format,
        watermark: :add_watermark,
        opacity: :alpha_opacity=
      }

      tag_to_operation.each do |tag_name, operation|
        expect(provider).to respond_to(operation) if described_class.available_tags.include?(tag_name)
      end
    end
  end
end
