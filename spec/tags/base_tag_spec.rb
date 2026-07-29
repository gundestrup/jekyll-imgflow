# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::Tags::BaseTag, :unit do
  let(:site) do
    double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                   dest: "/tmp/test_site/_site")
  end
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:provider) { JekyllImgFlow::ProviderRegistry.new(config).current_provider }

  # Simple test tag class
  let(:test_tag_class) do
    Class.new(JekyllImgFlow::Tags::BaseTag) do
      def process(_input_path, output_path, _options = {})
        ensure_output_dir(output_path)
        File.write(output_path, "processed")
        output_path
      end
    end
  end

  let(:tag) { test_tag_class.new(provider) }

  describe "#initialize" do
    it "initializes with provider" do
      expect(tag.instance_variable_get(:@provider)).to eq(provider)
    end

    it "sets default quality from config" do
      # The config should have a quality value (from config fallback)
      quality = tag.instance_variable_get(:@default_quality)
      expect(quality).to eq(85)
    end
  end

  describe "#process" do
    let(:test_dir) { create_test_dir("base-tag-test") }
    let(:input_path) { File.join(test_dir, "input.jpg") }
    let(:output_path) { File.join(test_dir, "output.jpg") }

    before do
      FileUtils.mkdir_p(test_dir)
      File.write(input_path, "input")
    end

    after do
      FileUtils.rm_rf(test_dir)
    end

    it "raises NotImplementedError for base class" do
      base_tag = described_class.new(provider)
      expect { base_tag.process(input_path, output_path) }.to raise_error(
        NotImplementedError,
        "Provider must implement JekyllImgFlow::Tags::BaseTag#process"
      )
    end

    it "processes successfully with subclass" do
      result = tag.process(input_path, output_path)

      expect(result).to eq(output_path)
      expect(File.exist?(output_path)).to be true
      expect(File.read(output_path)).to eq("processed")
    end

    it "creates output directory" do
      nested_path = File.join(test_dir, "nested", "output.jpg")

      tag.process(input_path, nested_path)

      expect(File.exist?(nested_path)).to be true
    end
  end

  describe "inheritance" do
    it "allows subclassing" do
      expect(test_tag_class < described_class).to be true
    end

    it "provides provider access" do
      provider = tag.instance_variable_get(:@provider)
      # Verify provider methods actually work
      provider.reset_operations
      provider.resize(800, 600)
      expect(provider.operations.last[:type]).to eq(:resize)
      expect(provider.operations.last[:width]).to eq(800)
      provider.crop("16:9")
      expect(provider.operations.last[:type]).to eq(:crop)
      expect(provider.operations.last[:ratio]).to eq("16:9")
      provider.reset_operations
    end
  end
end
