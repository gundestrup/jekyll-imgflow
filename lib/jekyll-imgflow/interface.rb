# frozen_string_literal: true

module JekyllImgFlow
  # Machine-readable description of the plugin's public interface:
  # Liquid tags + their params, config keys, and enum values.
  # `rake interface` writes this as interface.yml (shipped in the gem) so
  # tooling like editor extensions can consume it without parsing Ruby.
  module Interface
    TAGS = {
      "imgflow" => (Parser::OPERATION_PARAMS + Parser::HTML_ATTRIBUTES + %i[markup])
                   .map(&:to_s).sort.freeze
    }.freeze

    # Config keys read outside CORE_CONFIG_DEFAULTS in config.rb
    EXTRA_CONFIG_KEYS = %w[
      cache_dir image_modal imgproxy_url weserv_url flyimg_url sharp_url
      optimize_qualities
    ].freeze

    def self.to_h
      {
        "gem" => "jekyll-imgflow",
        "version" => VERSION,
        "tags" => TAGS.transform_values { |params| { "params" => params } },
        "filters" => [],
        "config" => {
          "imgflow" => (Config::CORE_CONFIG_DEFAULTS.keys + EXTRA_CONFIG_KEYS).sort
        },
        "enums" => {
          "markup" => HtmlGenerator::MARKUP_FORMATS.sort,
          "level" => %w[default high low maximum medium]
        }
      }
    end
  end
end
