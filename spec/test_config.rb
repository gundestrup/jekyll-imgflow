# frozen_string_literal: true

require "yaml"
require_relative "support/test_environment"

CONFIG_FILE = File.join(File.dirname(__dir__), "_config.yml")
REAL_CONFIG = YAML.load_file(CONFIG_FILE)

TEST_SITE_URL = TestEnvironment.site_url(provider: ENV.fetch("IMGFLOW_TEST_PROVIDER", nil))

TEST_CONFIG = REAL_CONFIG.dup
TEST_CONFIG["url"] = TEST_SITE_URL
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
                                                            "imgproxy_url" => TestEnvironment.docker_url("imgproxy"),
                                                            "weserv_url" => TestEnvironment.docker_url("weserv"),
                                                            "flyimg_url" => TestEnvironment.docker_url("flyimg")
                                                          }).freeze

RSpec.configure do |config|
  config.before(:suite) do
    fixtures_dir = File.expand_path("fixtures/originals", __dir__)
    FileUtils.mkdir_p(fixtures_dir)
    create_sample_images(fixtures_dir)
  end
end

def create_sample_images(_dir)
  # Real test images are downloaded via download-test-images.sh
  # This method is kept for compatibility but doesn't create placeholder files
  # since we now have real test images in spec/fixtures/originals/
end
