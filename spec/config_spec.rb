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

    it "uses sensible defaults when config is empty" do
      empty_site = double("site", config: {})
      cfg = described_class.new(empty_site)

      expect(cfg.originals).to eq("assets/images/originals")
      expect(cfg.output).to eq("assets/images/optimized")
      expect(cfg.input_formats).to include("jpg", "png", "webp", "avif", "gif")
      expect(cfg.formats).to eq(%w[avif webp png jpg])
      expect(cfg.sizes).to eq({ "sm" => 400, "md" => 800, "lg" => 1200, "xl" => 2000 })
      expect(cfg.quality).to eq(85)
      expect(cfg.backend_priority).to eq(%w[sharp libvips imagemagick imgproxy weserv flyimg])
      expect(cfg.fallback_format).to eq("jpg")
    end

    it "allows minimal config with only originals and output" do
      minimal_site = double("site", config: {
                              "imgflow" => {
                                "originals" => "src/images",
                                "output" => "dist/images"
                              }
                            })
      cfg = described_class.new(minimal_site)

      expect(cfg.originals).to eq("src/images")
      expect(cfg.output).to eq("dist/images")
      # Everything else uses defaults
      expect(cfg.quality).to eq(85)
      expect(cfg.formats).to eq(%w[avif webp png jpg])
      expect(cfg.backend_priority.first).to eq("sharp")
      expect(cfg.fallback_format).to eq("jpg")
    end

    it "allows imgflow overrides to take precedence over shared_images_configs" do
      site_with_shared = double("site", config: {
                                  "shared_images_configs" => {
                                    "originals" => "shared/originals",
                                    "output" => "shared/output",
                                    "quality" => 70
                                  },
                                  "imgflow" => {
                                    "output" => "custom/output"
                                  }
                                })
      cfg = described_class.new(site_with_shared)

      expect(cfg.originals).to eq("shared/originals") # from shared
      expect(cfg.output).to eq("custom/output") # overridden by imgflow
    end
  end

  describe "default constants" do
    it "has default backend priority ordered by speed" do
      expect(described_class::DEFAULT_BACKEND_PRIORITY).to eq(
        %w[sharp libvips imagemagick imgproxy weserv flyimg]
      )
    end

    it "has default sizes" do
      expect(described_class::DEFAULT_SIZES).to eq(
        { "sm" => 400, "md" => 800, "lg" => 1200, "xl" => 2000 }
      )
    end

    it "has default formats" do
      expect(described_class::DEFAULT_FORMATS).to eq(%w[avif webp png jpg])
    end

    it "has default quality" do
      expect(described_class::DEFAULT_QUALITY).to eq(85)
    end

    it "has default fallback_format" do
      expect(described_class::DEFAULT_FALLBACK_FORMAT).to eq("jpg")
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

    it "has sharp as first priority (fastest provider)" do
      expect(config.backend_priority.first).to eq("sharp")
    end

    it "has libvips as second priority" do
      expect(config.backend_priority[1]).to eq("libvips")
    end

    it "has imagemagick as third priority" do
      expect(config.backend_priority[2]).to eq("imagemagick")
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
