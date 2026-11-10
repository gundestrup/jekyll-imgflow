# frozen_string_literal: true

require_relative "lib/jekyll-imgflow/version"

Gem::Specification.new do |s|
  s.name        = "jekyll-imgflow"
  s.version     = JekyllImgFlow::VERSION
  s.summary     = "A modern, multi-provider, multi-format image optimization engine for Jekyll"
  # NOTE: rubygems.org renders the description through RDoc::Markup only
  # when it starts with an == heading at column 0 — keep the heredoc
  # content flush-left or the page renders as one plain <p>.
  s.description = <<~DESC
    == Jekyll image optimization

    ImgFlow provides automatic image optimization for Jekyll with multiple
    providers (Sharp, ImageMagick, LibVips, Imgproxy, Weserv, Flyimg) and
    formats (AVIF, WebP, PNG, JPG).

    * Responsive picture-tag output with automatic format fallbacks
    * Build-time pre-generation and on-demand specialized versions
    * Presets, crop, watermark and size parameters

    A companion VS Code extension (jekyll-imgflow-vscode) provides tag
    autocomplete: https://github.com/gundestrup/jekyll-imgflow-vscode
  DESC
  s.authors     = ["Svend Gundestrup"]
  s.email       = "svend@gundestrup.dk"
  s.files       = Dir["lib/**/*"].reject { |f| File.extname(f) == ".md" || File.basename(f) == ".DS_Store" } +
                  ["README.md", "CHANGELOG.md", "LICENSE", "interface.yml"]
  s.homepage    = "https://github.com/gundestrup/jekyll-imgflow"
  s.license     = "AGPL-3.0-or-later"
  # Floor derives from .ruby-version (major.minor + .0) so a Ruby bump
  # is a one-file change. If the consumer floor ever needs to lag the
  # dev pin, revert this to a literal.
  s.required_ruby_version = ">= #{File.read(File.expand_path('.ruby-version', __dir__))[/\d+\.\d+/]}.0"

  s.add_dependency "benchmark", "~> 0.5.0"
  s.add_dependency "fastimage", "~> 2.4.1"
  s.add_dependency "jekyll", ">= 4.0", "< 5.0"

  s.metadata["rubygems_mfa_required"] = "true"
  s.metadata["homepage_uri"] = s.homepage
  s.metadata["source_code_uri"] = s.homepage
  s.metadata["changelog_uri"] = "#{s.homepage}/blob/main/CHANGELOG.md"
  s.metadata["bug_tracker_uri"] = "#{s.homepage}/issues"
  s.metadata["icon_uri"] =
    "https://raw.githubusercontent.com/gundestrup/jekyll-imgflow/v0.1.11/" \
    "docs/assets/images/jekyll-imgflow-icon.png"
end
