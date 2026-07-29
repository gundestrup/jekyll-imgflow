# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Jekyll::ImgflowTag Unit", :unit do
  let(:site) do
    double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                   dest: "/tmp/test_site/_site")
  end
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:tag) do
    template = Liquid::Template.parse("{% imgflow test.jpg resize width:800 %}")
    template.root.nodelist.first
  end

  describe "#extract_element_attributes" do
    it "extracts basic img attributes" do
      parsed = { html_attributes: { alt: "Test image", class: "hero" } }
      result = tag.send(:extract_element_attributes, parsed)

      expect(result[:img][:alt]).to eq("Test image")
      expect(result[:img][:class]).to eq("hero")
    end

    it "separates picture-prefixed attributes" do
      parsed = { html_attributes: { "picture-class": "responsive",
                                    alt: "Test" } }
      result = tag.send(:extract_element_attributes, parsed)

      expect(result[:img][:alt]).to eq("Test")
      expect(result[:picture]).to eq("class" => "responsive")
    end

    it "separates source-prefixed attributes" do
      parsed = { html_attributes: { "source-media": "(min-width: 800px)",
                                    alt: "Test" } }
      result = tag.send(:extract_element_attributes, parsed)

      expect(result[:source]).to eq("media" => "(min-width: 800px)")
    end

    it "separates a-prefixed attributes" do
      parsed = { html_attributes: { "a-href": "/link",
                                    alt: "Test" } }
      result = tag.send(:extract_element_attributes, parsed)

      expect(result[:a]).to eq("href" => "/link")
    end

    it "separates parent-prefixed attributes" do
      parsed = { html_attributes: { "parent-class": "wrapper",
                                    alt: "Test" } }
      result = tag.send(:extract_element_attributes, parsed)

      expect(result[:parent]).to eq("class" => "wrapper")
    end

    it "extracts link attribute" do
      parsed = { html_attributes: { link: "true", alt: "Test" } }
      result = tag.send(:extract_element_attributes, parsed)

      expect(result[:link]).to eq("true")
    end

    it "handles empty html_attributes" do
      parsed = { html_attributes: {} }
      result = tag.send(:extract_element_attributes, parsed)

      expect(result[:img]).to eq({})
      expect(result[:picture]).to eq({})
    end

    it "handles nil html_attributes" do
      parsed = {}
      result = tag.send(:extract_element_attributes, parsed)

      expect(result[:img]).to eq({})
      expect(result[:alt]).to be_nil
    end
  end

  describe "#extract_prefixed_attrs" do
    it "extracts and strips prefix from keys" do
      attrs = { "picture-class": "foo", "picture-id": "bar",
                alt: "test" }
      result = tag.send(:extract_prefixed_attrs, attrs, "picture-")

      expect(result).to eq("class" => "foo", "id" => "bar")
    end

    it "returns empty hash when no matching prefixes" do
      attrs = { alt: "test", class: "img" }
      result = tag.send(:extract_prefixed_attrs, attrs, "picture-")

      expect(result).to eq({})
    end
  end

  describe "#render_liquid_variable" do
    it "renders a simple variable from context" do
      context = Liquid::Context.new({ "image" => "photo.jpg" }, {}, {})
      result = tag.send(:render_liquid_variable, "{{image}}", context)

      expect(result).to eq("photo.jpg")
    end

    it "returns the variable string when not found in context" do
      context = Liquid::Context.new({}, {}, {})
      result = tag.send(:render_liquid_variable, "{{unknown}}", context)

      expect(result).to eq("{{unknown}}")
    end
  end

  describe "#resolve_image_path" do
    it "joins absolute path with site source" do
      result = tag.send(:resolve_image_path, "/images/test.jpg", site, config)
      expect(result).to eq(File.join(site.source, "/images/test.jpg"))
    end

    it "joins relative path with subdirectory" do
      result = tag.send(:resolve_image_path, "assets/test.jpg", site, config)
      expect(result).to eq(File.join(site.source, "assets/test.jpg"))
    end

    it "uses PathResolver for bare filename" do
      result = tag.send(:resolve_image_path, "test.jpg", site, config)
      expect(result).to include("test.jpg")
      expect(result).to include(config.originals)
    end
  end

  describe "#determine_version_type" do
    it "delegates to config.determine_version_type" do
      params = { width: 800 }
      expect(config).to receive(:determine_version_type).with(params)
      tag.send(:determine_version_type, params, config)
    end
  end

  describe "#process_operations with no image_path" do
    let(:components) { create_imgflow_components(site) }
    let(:context) { double("context", registers: { site: site }) }

    it "returns empty string when parsed has no image_path" do
      allow(site).to receive(:imgflow_components).and_return(components)
      result = tag.send(:process_operations, components, { image_path: nil },
                        context)
      expect(result).to eq("")
    end
  end

  describe "#expand_preset_markup" do
    let(:preset_manager) { double("preset_manager") }

    it "expands preset markup with preset name and user options" do
      allow(preset_manager).to receive(:build_markup_from_preset)
        .with("hero", { quality: "90" })
        .and_return("width:800 height:600 quality:90")

      result = tag.send(:expand_preset_markup, "image.jpg preset:hero quality:90", preset_manager)

      expect(result).to eq("image.jpg width:800 height:600 quality:90")
    end

    it "extracts only preset name when no user options" do
      allow(preset_manager).to receive(:build_markup_from_preset)
        .with("hero", {})
        .and_return("width:800")

      result = tag.send(:expand_preset_markup, "image.jpg preset:hero", preset_manager)

      expect(result).to eq("image.jpg width:800")
    end
  end

  describe "#process_operations with nil page" do
    let(:config) { JekyllImgFlow::Config.new(site) }
    let(:manifest) { double("manifest") }
    let(:path_resolver) { JekyllImgFlow::PathResolver.new(config) }
    let(:filename_generator) { JekyllImgFlow::FilenameGenerator.new }
    let(:provider) { double("provider") }
    let(:operation_processor) { double("operation_processor") }
    let(:preset_manager) { double("preset_manager") }
    let(:registry) { double("registry") }

    let(:components) do
      {
        config: config, manifest: manifest, path_resolver: path_resolver,
        filename_generator: filename_generator, registry: registry,
        provider: provider, operation_processor: operation_processor,
        preset_manager: preset_manager
      }
    end

    let(:page) do
      double("page", :url => "/test.html", :path => "/test.html", "[]" => "/test.html")
    end
    let(:context) { Liquid::Context.new({}, {}, { site: site, page: page }) }

    before do
      allow(site).to receive(:imgflow_components).and_return(components)
      allow(Jekyll.logger).to receive(:debug)
      allow(Jekyll.logger).to receive(:error)
    end

    it "uses unknown page_path when page is nil" do
      context_no_page = Liquid::Context.new({}, {}, { site: site, page: nil })

      allow(manifest).to receive(:version_exists?).and_return(false)
      allow(manifest).to receive(:get_versions).and_return({})
      allow(operation_processor).to receive(:process_operation).and_return("/tmp/output.webp")
      allow(File).to receive(:file?).and_return(true)
      allow(tag).to receive(:resolve_image_path).and_return(fixture_image_path)

      result = tag.send(:process_operations, components,
                        { image_path: "test.jpg",
                          operations: [{ type: :resize, params: { width: 800 } }] },
                        context_no_page)
      expect(result).to be_a(String)
    end
  end

  describe "#process_operations with no operations" do
    let(:config) { JekyllImgFlow::Config.new(site) }
    let(:manifest) { double("manifest") }
    let(:path_resolver) { JekyllImgFlow::PathResolver.new(config) }
    let(:filename_generator) { JekyllImgFlow::FilenameGenerator.new }
    let(:provider) { double("provider") }
    let(:operation_processor) { double("operation_processor") }
    let(:preset_manager) { double("preset_manager") }
    let(:registry) { double("registry") }

    let(:components) do
      {
        config: config, manifest: manifest, path_resolver: path_resolver,
        filename_generator: filename_generator, registry: registry,
        provider: provider, operation_processor: operation_processor,
        preset_manager: preset_manager
      }
    end

    let(:page) do
      double("page", :url => "/test.html", :path => "/test.html", "[]" => "/test.html")
    end
    let(:context) { Liquid::Context.new({}, {}, { site: site, page: page }) }

    before do
      allow(site).to receive(:imgflow_components).and_return(components)
      allow(Jekyll.logger).to receive(:debug)
      allow(Jekyll.logger).to receive(:error)
    end

    it "uses original input path when operations are empty" do
      allow(tag).to receive(:resolve_image_path).and_return(fixture_image_path)
      allow(JekyllImgFlow::HtmlGenerator).to receive(:generate).and_return("<img>")

      result = tag.send(:process_operations, components,
                        { image_path: "test.jpg", operations: [],
                          html_attributes: {} },
                        context)
      expect(result).to eq("<img>")
    end
  end

  describe "#process_operations version exists in manifest" do
    let(:config) { JekyllImgFlow::Config.new(site) }
    let(:manifest) { double("manifest") }
    let(:path_resolver) { JekyllImgFlow::PathResolver.new(config) }
    let(:filename_generator) { JekyllImgFlow::FilenameGenerator.new }
    let(:provider) { double("provider") }
    let(:operation_processor) { double("operation_processor") }
    let(:preset_manager) { double("preset_manager") }
    let(:registry) { double("registry") }

    let(:components) do
      {
        config: config, manifest: manifest, path_resolver: path_resolver,
        filename_generator: filename_generator, registry: registry,
        provider: provider, operation_processor: operation_processor,
        preset_manager: preset_manager
      }
    end

    let(:page) do
      double("page", :url => "/test.html", :path => "/test.html", "[]" => "/test.html")
    end
    let(:context) { Liquid::Context.new({}, {}, { site: site, page: page }) }

    before do
      allow(site).to receive(:imgflow_components).and_return(components)
      allow(Jekyll.logger).to receive(:debug)
      allow(Jekyll.logger).to receive(:error)
    end

    it "updates page usage and returns output path when version exists" do
      allow(tag).to receive(:resolve_image_path).and_return(fixture_image_path)

      allow(config).to receive(:determine_version_type).and_return(:default)
      allow(config).to receive(:formats).and_return(["webp"])
      allow(config).to receive(:quality).and_return(85)

      allow(filename_generator).to receive(:generate_filename).and_return("test-800-hash.webp")
      allow(path_resolver).to receive(:resolve_output_path).and_return("/tmp/test_site/_site/assets/images/optimized/test-800-hash.webp")

      allow(manifest).to receive(:version_exists?).and_return(true)
      allow(manifest).to receive(:update_page_usage)

      allow(JekyllImgFlow::HtmlGenerator).to receive(:generate).and_return("<img>")

      result = tag.send(:process_operations, components,
                        { image_path: "test.jpg",
                          operations: [{ type: :resize, params: { width: 800 } }] },
                        context)
      expect(manifest).to have_received(:update_page_usage)
      expect(result).to eq("<img>")
    end
  end

  describe "#process_operations relative path conversion" do
    let(:config) { JekyllImgFlow::Config.new(site) }
    let(:manifest) { double("manifest") }
    let(:path_resolver) { JekyllImgFlow::PathResolver.new(config) }
    let(:filename_generator) { JekyllImgFlow::FilenameGenerator.new }
    let(:provider) { double("provider") }
    let(:operation_processor) { double("operation_processor") }
    let(:preset_manager) { double("preset_manager") }
    let(:registry) { double("registry") }

    let(:components) do
      {
        config: config, manifest: manifest, path_resolver: path_resolver,
        filename_generator: filename_generator, registry: registry,
        provider: provider, operation_processor: operation_processor,
        preset_manager: preset_manager
      }
    end

    let(:page) do
      double("page", :url => "/test.html", :path => "/test.html", "[]" => "/test.html")
    end
    let(:context) { Liquid::Context.new({}, {}, { site: site, page: page }) }

    before do
      allow(site).to receive(:imgflow_components).and_return(components)
      allow(Jekyll.logger).to receive(:debug)
      allow(Jekyll.logger).to receive(:error)
    end

    it "converts source path to relative" do
      allow(tag).to receive(:resolve_image_path).and_return("/tmp/test_site/assets/images/originals/test.jpg")
      allow(File).to receive(:file?).and_return(true)

      allow(config).to receive(:determine_version_type).and_return(:specialized)
      allow(filename_generator).to receive(:generate_filename).and_return("test-800-hash.webp")
      allow(path_resolver).to receive(:resolve_output_path).and_return("/tmp/test_site/_site/assets/images/optimized/test-800-hash.webp")

      allow(manifest).to receive(:version_exists?).and_return(false)
      allow(manifest).to receive(:get_versions).and_return({})
      allow(operation_processor).to receive(:process_operation).and_return("/tmp/test_site/assets/images/originals/test.jpg")

      allow(JekyllImgFlow::HtmlGenerator).to receive(:generate).and_return("<img>")

      result = tag.send(:process_operations, components,
                        { image_path: "test.jpg",
                          operations: [{ type: :resize, params: { width: 800 } }] },
                        context)
      expect(result).to eq("<img>")
    end

    it "strips leading slash from already-relative path" do
      allow(tag).to receive(:resolve_image_path).and_return(fixture_image_path)

      allow(config).to receive(:determine_version_type).and_return(:specialized)
      allow(filename_generator).to receive(:generate_filename).and_return("test-800-hash.webp")
      allow(path_resolver).to receive(:resolve_output_path).and_return("/tmp/test_site/_site/assets/images/optimized/test-800-hash.webp")

      allow(manifest).to receive(:version_exists?).and_return(false)
      allow(manifest).to receive(:get_versions).and_return({})
      allow(operation_processor).to receive(:process_operation).and_return("/some/other/path/test.webp")

      allow(JekyllImgFlow::HtmlGenerator).to receive(:generate).and_return("<img>")

      result = tag.send(:process_operations, components,
                        { image_path: "test.jpg",
                          operations: [{ type: :resize, params: { width: 800 } }] },
                        context)
      expect(result).to eq("<img>")
    end
  end
end
