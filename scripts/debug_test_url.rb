#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "spec/spec_helper"
require_relative "lib/jekyll-imgflow"

# Create test site
test_site_dir = File.join(Dir.tmpdir, "debug_test_site")
FileUtils.mkdir_p(test_site_dir)

# Create test site with proper config
create_test_jekyll_site(test_site_dir, :imgflow_only)
FileUtils.cp(test_image_path, File.join(test_site_dir, "assets/images/originals"))

# Create site config with proper URL
site_config = TEST_CONFIG.merge({
                                  "url" => "http://localhost:4000",
                                  "source" => test_site_dir
                                })

site = double("site", config: site_config, source: test_site_dir)
config = JekyllImgFlow::Config.new(site)

puts "=== Debug Test URL Construction ==="
puts "Site config url: #{site.config['url']}"
puts "Site source: #{site.source}"
puts "Test image path: #{test_image_path}"

# Create an Imgproxy provider to test URL construction
provider = JekyllImgFlow::Providers::Imgproxy.new(config)

# Test with the actual test image path
constructed_url = provider.encode_file_url(test_image_path)

puts "Test image path: #{test_image_path}"
puts "Constructed URL: #{constructed_url}"
puts "Expected: http://localhost:4000/assets/images/originals/test_image.jpg"

# Cleanup
FileUtils.rm_rf(test_site_dir)
