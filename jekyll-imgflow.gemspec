# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "jekyll-imgflow"
  s.version     = "0.1.5"
  s.summary     = "A modern, multi-provider, multi-format image optimization engine for Jekyll"
  s.description = "ImgFlow provides automatic image optimization for Jekyll with " \
                  "support for multiple providers (Sharp, Imgproxy, ImageMagick, " \
                  "LibVips), multiple formats (AVIF, WebP, PNG, JPG), " \
                  "and responsive image generation with modern picture tags."
  s.authors     = ["Svend Gundestrup"]
  s.email       = "svend@gundestrup.dk"
  s.files       = Dir["lib/**/*"].reject { |f| File.extname(f) == ".md" } + ["README.md", "LICENSE"]
  s.homepage    = "https://github.com/gundestrup/jekyll-imgflow"
  s.license     = "AGPL-3.0-or-later"
  s.required_ruby_version = ">= 3.3.0"

  s.add_dependency "fastimage", "~> 2.4"
  s.add_dependency "jekyll", ">= 4.0"

  s.add_development_dependency "bundler-audit", "~> 0.9"
  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "reek", "~> 6.0"
  s.add_development_dependency "rspec", "~> 3.13"
  s.add_development_dependency "rubocop", "~> 1.88"
  s.add_development_dependency "rubocop-markdown", "~> 0.2"
  s.add_development_dependency "rubocop-performance", "~> 1.26"
  s.add_development_dependency "rubocop-rake", "~> 0.7"
  s.add_development_dependency "rubocop-rspec", "~> 3.10"
  s.add_development_dependency "simplecov", "~> 1.0"
  s.add_development_dependency "yard", "~> 0.9"
  s.metadata["rubygems_mfa_required"] = "true"
end
