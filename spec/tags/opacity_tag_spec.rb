# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::Tags::OpacityTag, :unit do
  let(:site) do
    double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                   dest: "/tmp/test_site/_site")
  end
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:provider) { JekyllImgFlow::ProviderRegistry.new(config).current_provider }
  let(:tag) { described_class.new(provider) }

  describe "#process" do
    let(:test_image_dir) { create_test_dir("opacity-tag-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.png") }
    let(:output_path) { File.join(test_image_dir, config.output, "test-opacity-a1b2c3d4e.png") }
    let(:original_image) do
      File.expand_path("../fixtures/originals/mars-crater-large.jpg", __dir__)
    end

    before do
      # Skip tests if provider doesn't support alpha_opacity operations
      skip "Provider #{provider.class} does not support alpha opacity operations" unless provider.class.supports_operation?(:alpha_opacity)

      # Create test directories and copy test image
      FileUtils.mkdir_p(File.dirname(input_path))
      FileUtils.cp(original_image, input_path)
      FileUtils.mkdir_p(File.dirname(output_path))
    end

    after do
      FileUtils.rm_rf(test_image_dir)
    end

    context "with valid opacity" do
      let(:options) { { opacity: 0.5 } }

      it "processes alpha channel successfully" do
        # Mock provider methods to avoid actual processing
        allow(provider).to receive(:alpha_opacity=)
        allow(provider).to receive(:execute)

        result = tag.process(input_path, output_path, options)

        expect(result).to eq(output_path)
        expect(provider).to have_received(:alpha_opacity=).with(0.5)
        expect(provider).to have_received(:execute).with(input_path, output_path)
      end
    end

    context "without opacity" do
      let(:options) { {} }

      it "raises error when opacity not provided" do
        expect { tag.process(input_path, output_path, options) }.to raise_error(
          ArgumentError, "Opacity parameter is required"
        )
      end
    end

    context "with string opacity" do
      let(:options) { { opacity: "0.8" } }

      it "converts string to float" do
        allow(provider).to receive(:alpha_opacity=)
        allow(provider).to receive(:execute)

        tag.process(input_path, output_path, options)

        expect(provider).to have_received(:alpha_opacity=).with(0.8)
      end
    end

    context "with extreme opacity values" do
      it "handles nearly transparent (0.01)" do
        allow(provider).to receive(:alpha_opacity=)
        allow(provider).to receive(:execute)

        tag.process(input_path, output_path, { opacity: 0.01 })

        expect(provider).to have_received(:alpha_opacity=).with(0.01)
      end

      it "handles nearly opaque (0.99)" do
        allow(provider).to receive(:alpha_opacity=)
        allow(provider).to receive(:execute)

        tag.process(input_path, output_path, { opacity: 0.99 })

        expect(provider).to have_received(:alpha_opacity=).with(0.99)
      end
    end
  end

  describe "opacity validation" do
    it "accepts valid opacity values" do
      expect(tag.send(:validate_opacity, 0.5)).to eq(0.5)
      expect(tag.send(:validate_opacity, 0.01)).to eq(0.01)
      expect(tag.send(:validate_opacity, 0.99)).to eq(0.99)
    end

    it "converts string to float" do
      expect(tag.send(:validate_opacity, "0.7")).to eq(0.7)
    end

    context "with invalid opacity" do
      it "raises error for opacity below 0.01" do
        expect { tag.send(:validate_opacity, 0.0) }.to raise_error(
          ArgumentError, "Invalid opacity: '0.0'. Must be between 0.01 and 0.99."
        )
      end

      it "raises error for opacity above 0.99" do
        expect { tag.send(:validate_opacity, 1.0) }.to raise_error(
          ArgumentError, "Invalid opacity: '1.0'. Must be between 0.01 and 0.99."
        )
      end

      it "raises error for non-numeric opacity" do
        expect { tag.send(:validate_opacity, "invalid") }.to raise_error(
          ArgumentError, "Invalid opacity: 'invalid'. Must be between 0.01 and 0.99."
        )
      end
    end
  end

  describe "inheritance" do
    it "inherits from BaseTag" do
      expect(described_class < JekyllImgFlow::Tags::BaseTag).to be true
    end

    it "has access to provider" do
      expect(tag.instance_variable_get(:@provider)).to eq(provider)
    end

    it "has access to default quality" do
      expect(tag.instance_variable_get(:@default_quality)).to eq(85)
    end
  end

  describe "use cases" do
    let(:test_image_dir) { create_test_dir("opacity-use-cases-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.png") }
    let(:output_path) { File.join(test_image_dir, config.output, "test-opacity-a1b2c3d4e.png") }
    let(:original_image) do
      File.expand_path("../fixtures/originals/mars-crater-large.jpg", __dir__)
    end

    before do
      FileUtils.mkdir_p(File.dirname(input_path))
      FileUtils.cp(original_image, input_path)
      FileUtils.mkdir_p(File.dirname(output_path))
    end

    after do
      FileUtils.rm_rf(test_image_dir)
    end

    it "can create semi-transparent images" do
      allow(provider).to receive(:alpha_opacity=)
      allow(provider).to receive(:execute)

      tag.process(input_path, output_path, { opacity: 0.3 })

      expect(provider).to have_received(:alpha_opacity=).with(0.3)
    end

    it "can create ghost effects" do
      allow(provider).to receive(:alpha_opacity=)
      allow(provider).to receive(:execute)

      tag.process(input_path, output_path, { opacity: 0.1 })

      expect(provider).to have_received(:alpha_opacity=).with(0.1)
    end
  end
end
