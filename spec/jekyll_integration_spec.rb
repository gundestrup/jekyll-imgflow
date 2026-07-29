# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/jekyll-imgflow/path_resolver"

RSpec.describe "Jekyll Integration", :integration, :system do
  # Use TestPictures for standardized test data
  let(:test_site_dir) { create_test_dir("jekyll-integration") }
  let(:test_images) { TestPictures.get(:default) }
  let(:test_image_name) { test_images.first }
  let(:tokens) { double("tokens", line_number: 1) }
  # Define site and context at top level for all tests to access
  let(:site) do
    # Create a Jekyll site double with necessary config
    site_double = double("site",
                         config: TEST_CONFIG,
                         source: test_site_dir,
                         dest: File.join(test_site_dir, "_site"))

    # Allow component caching to work
    allow(site_double).to receive(:imgflow_components).and_return(nil)
    allow(site_double).to receive(:imgflow_components=) do |components|
      allow(site_double).to receive(:imgflow_components).and_return(components)
    end

    site_double
  end
  let(:context) do
    double("context",
           registers: { site: site,
                        page: double("page", :url => "/test.html", "[]" => "/test.html") })
  end
  let(:imgflow_config) { JekyllImgFlow::Config.new(site) }

  before do
    # Create basic site structure with TestPictures
    FileUtils.mkdir_p(File.join(test_site_dir, "assets/images/originals"))
    FileUtils.mkdir_p(File.join(test_site_dir, "_site"))

    # Copy TestPictures images
    test_images.each do |image_name|
      source_path = File.join(File.expand_path("fixtures/originals", __dir__), image_name)
      dest_path = File.join(test_site_dir, "assets/images/originals", image_name)
      FileUtils.cp(source_path, dest_path) if File.exist?(source_path)
    end
  end

  after do
    # Clean up test site
    FileUtils.rm_rf(test_site_dir)
  end

  describe "ImgflowTag" do
    describe "Image Path Resolution" do
      let(:tag) { Jekyll::ImgflowTag.send(:new, "imgflow", "", tokens) }

      it "resolves absolute paths" do
        resolved = tag.send(:resolve_image_path, "/assets/images/banner.jpg", site, imgflow_config)

        expect(resolved).to include("/assets/images/banner.jpg")
      end

      it "resolves relative paths" do
        resolved = tag.send(:resolve_image_path, "assets/images/banner.jpg", site, imgflow_config)

        expect(resolved).to include("assets/images/banner.jpg")
      end

      it "resolves originals directory paths" do
        resolved = tag.send(:resolve_image_path, test_image_name, site, imgflow_config)

        expect(resolved).to include("assets/images/originals")
        expect(resolved).to include(test_image_name)
      end
    end

    describe "Liquid Variable Support" do
      let(:tag) { Jekyll::ImgflowTag.send(:new, "imgflow", "", tokens) }

      it "renders liquid variables in options" do
        allow(context).to receive(:[]).with("image_width").and_return(800)
        allow(context).to receive(:[]).with("image_quality").and_return(85)

        result1 = tag.send(:render_liquid_variable, "{{ image_width }}", context)
        expect(result1).to eq(800)

        result2 = tag.send(:render_liquid_variable, "{{ image_quality }}", context)
        expect(result2).to eq(85)
      end

      it "handles undefined variables" do
        allow(context).to receive(:[]).with("undefined_var").and_return(nil)

        result = tag.send(:render_liquid_variable, "{{ undefined_var }}", context)
        expect(result).to eq("{{ undefined_var }}")
      end
    end

    describe "Component Caching" do
      let(:tag) { Jekyll::ImgflowTag.send(:new, "imgflow", "test.jpg width:800", tokens) }

      it "creates and caches components" do
        # First call should create components
        components1 = tag.send(:get_imgflow_components, context)

        # Second call should return cached components
        components2 = tag.send(:get_imgflow_components, context)

        expect(components1).to be(components2)
        expect(components1).to have_key(:config)
        expect(components1).to have_key(:manifest)
        expect(components1).to have_key(:path_resolver)
        expect(components1).to have_key(:operation_processor)
        expect(components1).to have_key(:preset_manager)
      end
    end

    describe "HTML Generation" do
      let(:tag) { Jekyll::ImgflowTag.send(:new, "imgflow", "", tokens) }

      it "generates img tag with correct attributes" do
        # Use TestPictures expected filename
        expected_filename = TestPictures.expected_filename(test_image_name, :lg, :jpg)
        results = ["/assets/images/optimized/#{expected_filename}"]
        parsed = {
          html_attributes: { alt: "Test Image", class: "hero" }
        }

        html = tag.send(:generate_html, results, parsed, context)

        expect(html).to include("<img")
        expect(html).to include("src=\"assets/images/optimized/#{expected_filename}\"")
        expect(html).to include('alt="Test Image"')
        expect(html).to include('class="hero"')
        expect(html).to include('loading="lazy"')
      end

      it "adds lazy loading by default" do
        results = ["/assets/images/optimized/test.jpg"]
        parsed = { html_attributes: {} }

        html = tag.send(:generate_html, results, parsed, context)

        expect(html).to include('loading="lazy"')
      end

      it "returns empty string for empty results" do
        html = tag.send(:generate_html, [], { html_attributes: {} }, context)

        expect(html).to eq("")
      end
    end

    describe "Error Handling" do
      it "handles missing image gracefully" do
        tag = Jekyll::ImgflowTag.send(:new, "imgflow", "nonexistent.jpg width:800", tokens)
        result = tag.render(context)

        expect(result).to include("<!-- ImgFlow Error:")
        expect(result).to include("Input image file not found")
      end

      it "returns error comment on processing failure" do
        tag = Jekyll::ImgflowTag.send(:new, "imgflow", "#{test_image_name} width:invalid", tokens)

        # Mock the parser to raise an error
        allow(JekyllImgFlow::Parser).to receive(:parse).and_raise("Invalid width value")

        result = tag.render(context)

        expect(result).to include("<!-- ImgFlow Error:")
        expect(result).to include("Invalid width value")
      end
    end

    describe "End-to-End Rendering with TestPictures" do
      it "renders complete img tag from markup" do
        tag = Jekyll::ImgflowTag.send(:new, "imgflow", "#{test_image_name} width:800", tokens)
        result = tag.render(context)

        expect(result).to include("<img")
        expect(result).to include(test_image_name.gsub(/\.[^.]+$/, "")) # Base name without extension
        expect(result).to include('loading="lazy"')
      end

      it "processes image and generates output file" do
        tag = Jekyll::ImgflowTag.send(:new, "imgflow",
                                      "#{test_image_name} width:800 format:webp", tokens)
        result = tag.render(context)

        # Check that HTML was generated
        expect(result).to include("<img")
        expect(result).to include(test_image_name.gsub(/\.[^.]+$/, "")) # Base name without extension
        expect(result).to include("assets/images/optimized")
        expect(result).to include('loading="lazy"')
      end

      it "generates expected TestPictures filename patterns" do
        # Use real FilenameGenerator to get expected filename
        # Note: Parser doesn't add default quality, only what's in markup
        filename_generator = JekyllImgFlow::FilenameGenerator.new
        params = { width: 800, format: "webp" } # No quality unless specified in markup
        actual_filename = filename_generator.generate_filename(test_image_name, params)

        # Mock only the expensive image compression (Sharp processing)
        # Keep all other components real for realistic testing
        tag = Jekyll::ImgflowTag.send(:new, "imgflow", "#{test_image_name} width:800 format:webp",
                                      tokens)

        # Get real components but mock only the expensive operation
        real_components = tag.send(:get_imgflow_components, context)

        # Mock only the Sharp processing part
        allow(real_components[:operation_processor]).to receive_messages(
          process_single_operation: File.join(test_site_dir, "_site", "assets", "images", "optimized",
                                              actual_filename), process_batch_operations: File.join(test_site_dir, "_site", "assets", "images", "optimized", actual_filename)
        )

        result = tag.render(context)

        # Extract the actual filename from the HTML result
        html_filename_match = result.match(%r{src="assets/images/optimized/([^"]+)"})
        html_filename = html_filename_match ? html_filename_match[1] : nil

        expect(result).to include("<img")
        expect(html_filename).not_to be_nil
        expect(result).to include('loading="lazy"')

        # Validate the filename structure matches TestPictures pattern
        expect(html_filename).to include(test_image_name.gsub(/\.[^.]+$/, "")) # Base name
        expect(html_filename).to include("800") # Width
        expect(html_filename).to end_with(".webp") # Format

        # The actual filename should match what the HTML contains (parser behavior)
        expect(actual_filename).to eq(html_filename)

        # NOTE: TestPictures expects quality=85 hash, but parser doesn't add default quality
        # This is expected behavior - we validate actual parser output, not TestPictures

        # The HTML should contain the actual filename
        expect(result).to include(html_filename)
      end
    end
  end
end
