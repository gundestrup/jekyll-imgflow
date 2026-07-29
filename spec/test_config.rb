# frozen_string_literal: true

require "spec_helper"
require "yaml"

# Load actual configuration from _config.yml
CONFIG_FILE = File.join(File.dirname(__dir__), "_config.yml")
REAL_CONFIG = YAML.load_file(CONFIG_FILE)

# When testing with an HTTP provider via Docker, use host.docker.internal
# so Docker containers can reach the host's Jekyll test server
TEST_SITE_URL = if ENV["IMGFLOW_TEST_PROVIDER"]
                  "http://host.docker.internal:4000"
                else
                  "http://localhost:4000"
                end

# Test configuration using actual config file with test-specific overrides
TEST_CONFIG = REAL_CONFIG.dup
TEST_CONFIG["url"] = TEST_SITE_URL
# Resolve interpolation from shared_images_configs and override URLs for testing
shared_config = REAL_CONFIG["shared_images_configs"]
TEST_CONFIG["imgflow"] = REAL_CONFIG["imgflow"].dup.merge({
                                                            "originals" => shared_config["originals"],
                                                            "output" => shared_config["output"],
                                                            "input_formats" => shared_config["input_formats"],
                                                            "sizes" => shared_config["sizes"],
                                                            "formats" => shared_config["formats"],
                                                            "quality" => REAL_CONFIG["imgflow"]["quality"],
                                                            "backend_priority" =>
                            if ENV["IMGFLOW_TEST_PROVIDER"]
                              [ENV["IMGFLOW_TEST_PROVIDER"]]
                            else
                              REAL_CONFIG["imgflow"]["backend_priority"]
                            end,
                                                            "imgproxy_url" => "http://localhost:33001",
                                                            "image_compressor_url" => "http://localhost:33006",
                                                            "weserv_url" => "http://localhost:33007",
                                                            "flyimg_url" => "http://localhost:33008"
                                                          }).freeze

RSpec.configure do |config|
  config.before(:suite) do
    # Create test fixtures directory if it doesn't exist
    fixtures_dir = File.expand_path("fixtures/originals", __dir__)
    FileUtils.mkdir_p(fixtures_dir)

    # Create sample test images if they don't exist
    create_sample_images(fixtures_dir)
  end
end

def create_sample_images(dir)
  # Real test images are downloaded via download-test-images.sh
  # This method is kept for compatibility but doesn't create placeholder files
  # since we now have real test images in spec/fixtures/originals/
end
