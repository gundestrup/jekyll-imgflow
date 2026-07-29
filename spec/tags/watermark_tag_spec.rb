# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::Tags::WatermarkTag, :unit do
  let(:site) do
    double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                   dest: "/tmp/test_site/_site")
  end
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:provider) { JekyllImgFlow::ProviderRegistry.new(config).current_provider }
  let(:tag) { described_class.new(provider) }

  describe "#process" do
    let(:test_image_dir) { create_test_dir("watermark-tag-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.jpg") }
    let(:output_path) { File.join(test_image_dir, config.output, "test-watermark-a1b2c3d4e.jpg") }
    let(:original_image) do
      File.expand_path("../fixtures/originals/mars-crater-large.jpg", __dir__)
    end
    let(:watermark_path) { File.join(test_image_dir, config.originals, "watermark.png") }

    before do
      # Skip tests if provider doesn't support watermark operations
      skip "Provider #{provider.class} does not support watermark operations" unless provider.class.supports_operation?(:watermark)

      # Create test directories and copy test image
      FileUtils.mkdir_p(File.dirname(input_path))
      FileUtils.cp(original_image, input_path)
      FileUtils.mkdir_p(File.dirname(output_path))

      # Create watermark file
      File.write(watermark_path, "watermark content")
    end

    after do
      FileUtils.rm_rf(test_image_dir)
    end

    context "with valid parameters" do
      let(:options) { { watermark: watermark_path } }

      it "processes watermark successfully" do
        # Mock provider methods to avoid actual processing
        allow(provider).to receive(:add_watermark)
        allow(provider).to receive(:execute)

        result = tag.process(input_path, output_path, options)

        expect(result).to eq(output_path)
        expect(provider).to have_received(:add_watermark).with(
          watermark_path,
          hash_including(:position, :opacity)
        )
        expect(provider).to have_received(:execute).with(input_path, output_path)
      end

      it "uses default position when not specified" do
        allow(provider).to receive(:add_watermark)
        allow(provider).to receive(:execute)

        tag.process(input_path, output_path, options)

        expect(provider).to have_received(:add_watermark).with(
          watermark_path,
          position: "southeast", # bottom_right -> southeast
          opacity: 0.7
        )
      end

      it "uses default opacity when not specified" do
        allow(provider).to receive(:add_watermark)
        allow(provider).to receive(:execute)

        tag.process(input_path, output_path, options)

        expect(provider).to have_received(:add_watermark).with(
          watermark_path,
          hash_including(opacity: 0.7)
        )
      end
    end

    context "with custom position" do
      let(:options) { { watermark: watermark_path, position: :top_left } }

      it "translates position correctly" do
        allow(provider).to receive(:add_watermark)
        allow(provider).to receive(:execute)

        tag.process(input_path, output_path, options)

        expect(provider).to have_received(:add_watermark).with(
          watermark_path,
          position: "northwest", # top_left -> northwest
          opacity: 0.7
        )
      end
    end

    context "with custom opacity" do
      let(:options) { { watermark: watermark_path, opacity: 0.5 } }

      it "uses custom opacity" do
        allow(provider).to receive(:add_watermark)
        allow(provider).to receive(:execute)

        tag.process(input_path, output_path, options)

        expect(provider).to have_received(:add_watermark).with(
          watermark_path,
          hash_including(opacity: 0.5)
        )
      end
    end

    context "with string opacity" do
      let(:options) { { watermark: watermark_path, opacity: "0.8" } }

      it "converts string to float" do
        allow(provider).to receive(:add_watermark)
        allow(provider).to receive(:execute)

        tag.process(input_path, output_path, options)

        expect(provider).to have_received(:add_watermark).with(
          watermark_path,
          hash_including(opacity: 0.8)
        )
      end
    end
  end

  describe "position translation" do
    it "translates top_left to northwest" do
      result = tag.send(:translate_watermark_position, :top_left)
      expect(result).to eq("northwest")
    end

    it "translates top_right to northeast" do
      result = tag.send(:translate_watermark_position, :top_right)
      expect(result).to eq("northeast")
    end

    it "translates bottom_left to southwest" do
      result = tag.send(:translate_watermark_position, :bottom_left)
      expect(result).to eq("southwest")
    end

    it "translates bottom_right to southeast" do
      result = tag.send(:translate_watermark_position, :bottom_right)
      expect(result).to eq("southeast")
    end

    it "translates center to center" do
      result = tag.send(:translate_watermark_position, :center)
      expect(result).to eq("center")
    end

    it "passes through unknown positions as string" do
      result = tag.send(:translate_watermark_position, :custom)
      expect(result).to eq("custom")
    end
  end

  describe "opacity validation" do
    it "accepts valid opacity values" do
      expect(tag.send(:validate_opacity, 0.5)).to eq(0.5)
      expect(tag.send(:validate_opacity, 0.0)).to eq(0.0)
      expect(tag.send(:validate_opacity, 1.0)).to eq(1.0)
    end

    it "converts string to float" do
      expect(tag.send(:validate_opacity, "0.7")).to eq(0.7)
    end

    context "with invalid opacity" do
      it "raises error for opacity below 0.0" do
        expect { tag.send(:validate_opacity, -0.1) }.to raise_error(
          ArgumentError, "Invalid opacity: '-0.1'. Must be between 0.0 and 1.0."
        )
      end

      it "raises error for opacity above 1.0" do
        expect { tag.send(:validate_opacity, 1.1) }.to raise_error(
          ArgumentError, "Invalid opacity: '1.1'. Must be between 0.0 and 1.0."
        )
      end

      it "raises error for non-numeric opacity" do
        expect { tag.send(:validate_opacity, "invalid") }.to raise_error(
          ArgumentError, "Invalid opacity: 'invalid'. Must be between 0.0 and 1.0."
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
end
