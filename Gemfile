# frozen_string_literal: true

source "https://rubygems.org"

# Pull runtime dependencies from the gemspec automatically.
# Development dependencies are declared below in the :development group,
# not in the gemspec, to avoid drift between the two files.
# See: https://github.com/rubygems/guides/blob/main/gemfile-and-gemspec.md
gemspec

# Pin Jekyll to the 4.4.x line for development/testing.
# The gemspec declares ">= 4.0" (wide for users); the Gemfile pins tighter
# for reproducible dev environments. Gemfile.lock records the exact version.
gem "jekyll", "~> 4.4.1"

group :jekyll_plugins do
  gem "jekyll_picture_tag", "~> 2.1.3"
end

group :development do
  gem "bundler-audit", "~> 0.9.3"
  gem "debug", "~> 1.11.1", require: false
  gem "ostruct", "~> 0.6.1"
  gem "parallel", "~> 2.2.0"
  gem "parallel_tests", "~> 5.7.0"
  gem "rake", "~> 13.4.2"
  gem "rspec", "~> 3.13.2"
  gem "rubocop", "~> 1.90.0"
  gem "rubocop-markdown", "~> 0.2.0"
  gem "rubocop-performance", "~> 1.27.0"
  gem "rubocop-rake", "~> 0.7.1"
  gem "rubocop-rspec", "~> 3.10.2"
  gem "ruby-lsp-rspec", "~> 0.1.29", require: false
  gem "simplecov", "~> 1.2.0"
  gem "webmock", "~> 3.26.2"
  gem "yard", "~> 0.9.45"
end
