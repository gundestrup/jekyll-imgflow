# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe JekyllImgFlow::Config, :unit do
  let(:config_file) { File.join(File.dirname(__dir__), "_config.yml") }
  let(:real_config) { YAML.load_file(config_file) }
  let(:site) { double("site", config: TEST_CONFIG) }
  let(:config) { described_class.new(site) }

  describe "#initialize" do
    it "loads configuration from test config" do
      # Use values from TEST_CONFIG (which has actual values, not interpolation)
      expect(config.output).to eq(TEST_CONFIG["imgflow"]["output"])
      expect(config.sizes).to eq(TEST_CONFIG["imgflow"]["sizes"])
      expect(config.formats).to eq(TEST_CONFIG["imgflow"]["formats"])
      expect(config.backend_priority).to eq(TEST_CONFIG["imgflow"]["backend_priority"])
    end

    it "raises error when required config is missing" do
      empty_site = double("site", config: {})

      expect do
        described_class.new(empty_site)
      end.to raise_error(ArgumentError, /No originals configured/)
    end
  end

  describe "#sizes" do
    it "returns configured sizes" do
      expect(config.sizes["sm"]).to eq(400)
      expect(config.sizes["md"]).to eq(800)
      expect(config.sizes["lg"]).to eq(1200)
    end
  end

  describe "#formats" do
    it "returns configured formats" do
      expect(config.formats).to include("avif", "webp", "jpg")
    end
  end

  describe "#backend_priority" do
    it "returns configured backend priority" do
      expect(config.backend_priority).to eq(TEST_CONFIG["imgflow"]["backend_priority"])
    end
  end

  describe "#cache_dir" do
    it "returns configured cache directory" do
      expect(config.cache_dir).to eq(".cache/imgflow")
    end
  end

  describe "#docker_config" do
    it "returns Docker configuration" do
      expect(config.docker_enabled).to be true
      expect(config.sharp_url).to eq(TEST_CONFIG["imgflow"]["sharp_url"])
      expect(config.imgproxy_url).to eq("http://localhost:33001")
    end
  end
end
