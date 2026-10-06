# frozen_string_literal: true

require "yaml"

RSpec.describe "interface manifest" do
  root = File.expand_path("..", __dir__)
  interface = JekyllImgFlow::Interface.to_h

  it "matches the committed interface.yml" do
    manifest = YAML.load_file(File.join(root, "interface.yml"))
    expect(manifest).to eq(interface)
  end

  it "declares every Liquid tag registered by this gem" do
    owned = Liquid::Template.tags.select do |_name, klass|
      klass.to_s.start_with?("Jekyll::Imgflow")
    end.map(&:first)
    expect(owned.sort).to eq(interface["tags"].keys.sort)
  end

  it "declares exactly the params the parser and attributes constants define" do
    expected = (JekyllImgFlow::Parser::OPERATION_PARAMS +
                JekyllImgFlow::Parser::HTML_ATTRIBUTES + %i[markup]).map(&:to_s).sort
    expect(interface.dig("tags", "imgflow", "params")).to eq(expected)
  end

  it "declares exactly the config keys Config reads" do
    source = File.read(File.join(root, "lib/jekyll-imgflow/config.rb"))
    key_pattern = /(?:cfg|merged_config)(?:\[\s*"(\w+)"\s*\]|\.key\?\(\s*"(\w+)"\s*\)|\.fetch\(\s*"(\w+)")/
    read = []
    pos = 0
    while (match = key_pattern.match(source, pos))
      read << match.captures.compact.first
      pos = match.end(0)
    end
    read.uniq!
    read -= %w[imgflow shared_images_configs] # section names, not keys
    expected = (JekyllImgFlow::Config::CORE_CONFIG_DEFAULTS.keys + read).uniq.sort
    expect(interface.dig("config", "imgflow")).to eq(expected)
  end

  it "routes every declared markup format through HtmlGenerator" do
    results = %w[assets/images/optimized/x-800-deadbeef.jpg]
    interface["enums"]["markup"].each do |format|
      html = JekyllImgFlow::HtmlGenerator.generate(results, {}, format, nil)
      expect(html).not_to be_empty
    end
    expect(JekyllImgFlow::Parser.parse("x.jpg width:100 markup:direct_url")[:markup_format])
      .to eq("direct_url")
  end

  it "documents every tag, param, config key, and enum value" do
    docs = (Dir[File.join(root, "*.md")] +
            Dir[File.join(root, "docs/**/*.md")])
           .map { |f| File.read(f) }.join("\n")

    missing = []
    interface["tags"].each do |tag, spec|
      missing << "tag `#{tag}`" unless docs.match?(/\b#{tag}\b/)
      spec["params"].each do |param|
        missing << "#{tag} param `#{param}:`" unless docs.match?(/\b#{param}\s*:/)
      end
    end
    interface["config"].each do |section, keys|
      keys.each do |key|
        missing << "#{section} config `#{key}`" unless docs.match?(/\b#{key}\b/)
      end
    end
    interface["enums"].each do |setting, values|
      values.each do |value|
        missing << "#{setting} value `#{value}`" unless docs.match?(/\b#{Regexp.escape(value)}\b/)
      end
    end

    expect(missing).to be_empty,
                       "interface items missing from docs:\n  #{missing.join("\n  ")}"
  end
end
