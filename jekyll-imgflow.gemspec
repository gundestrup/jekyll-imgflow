# frozen_string_literal: true

require_relative "lib/jekyll-imgflow/version"

Gem::Specification.new do |s|
  s.name        = "jekyll-imgflow"
  s.version     = JekyllImgFlow::VERSION
  s.summary     = "A modern, multi-provider, multi-format image optimization engine for Jekyll"
  s.description = "ImgFlow provides automatic image optimization for Jekyll with " \
                  "support for multiple providers (Sharp, ImageMagick, LibVips, " \
                  "Imgproxy, Weserv, Flyimg), multiple formats (AVIF, WebP, PNG, JPG), " \
                  "and responsive image generation with modern picture tags."
  s.authors     = ["Svend Gundestrup"]
  s.email       = "svend@gundestrup.dk"
  s.files       = Dir["lib/**/*"].reject { |f| File.extname(f) == ".md" || File.basename(f) == ".DS_Store" } + ["README.md", "LICENSE"]
  s.homepage    = "https://github.com/gundestrup/jekyll-imgflow"
  s.license     = "AGPL-3.0-or-later"
  s.required_ruby_version = ">= 3.4.0"

  s.add_dependency "benchmark", "~> 0.5.0"
  s.add_dependency "fastimage", "~> 2.4.1"
  s.add_dependency "jekyll", ">= 4.0"

  s.metadata["rubygems_mfa_required"] = "true"
  s.metadata["icon_uri"] =
    "https://raw.githubusercontent.com/gundestrup/jekyll-imgflow/v0.1.11/" \
    "docs/assets/images/jekyll-imgflow-icon.png"
end
