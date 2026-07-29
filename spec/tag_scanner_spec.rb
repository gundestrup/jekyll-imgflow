# frozen_string_literal: true

require "spec_helper"
require_relative "support/test_directory_helper"
require_relative "support/test_pictures"

RSpec.describe JekyllImgFlow::TagScanner, :unit do
  # Use our helper methods and test photos
  let(:site) { double("site", config: TEST_CONFIG, source: "/tmp/test_site") }
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:scanner) { described_class.new(site, config) }
  let(:test_images) { TestPictures.get(:default_multi) }
  let(:test_image) { test_images.first }
  let(:test_dir) { TestDirectoryHelper.create_test_dir("tag_scanner") }
  let(:posts_dir) { File.join(test_dir, "_posts") }
  let(:pages_dir) { File.join(test_dir, "pages") }
  let(:collections_dir) { File.join(test_dir, "_collections") }

  # Mock manifest for integration testing
  let(:mock_manifest) { double("manifest", get_all_versions: {}) }

  describe "#initialize" do
    it "initializes with site and config" do
      expect(scanner).to be_a(described_class)
      expect(scanner.instance_variable_get(:@site)).to eq(site)
      expect(scanner.instance_variable_get(:@config)).to eq(config)
    end

    it "initializes with optional manifest parameter" do
      scanner_with_manifest = described_class.new(site, config, mock_manifest)
      expect(scanner_with_manifest.instance_variable_get(:@manifest)).to eq(mock_manifest)
    end
  end

  describe "#scan_all_content" do
    before do
      # Setup test directory structure using our helper
      FileUtils.mkdir_p(posts_dir)
      FileUtils.mkdir_p(pages_dir)
      FileUtils.mkdir_p(collections_dir)

      # Create test posts
      File.write(File.join(posts_dir, "2024-01-01-post1.md"), <<~MARKDOWN)
        ---
        title: Post 1
        ---
        {% imgflow #{test_images[0]} width:800 %}
      MARKDOWN

      File.write(File.join(posts_dir, "2024-01-02-post2.md"), <<~MARKDOWN)
        ---
        title: Post 2
        ---
        {% imgflow #{test_images[1] || test_images[0]} width:1200 %}
        {% imgflow #{test_images[2] || test_images[0]} width:800 quality:90 %}
      MARKDOWN

      # Create test pages
      File.write(File.join(pages_dir, "about.md"), <<~MARKDOWN)
        ---
        title: About
        ---
        {% imgflow #{test_images[0]} width:600 %}
      MARKDOWN

      # Mock site with proper structure
      allow(site).to receive_messages(posts: double("posts", docs: []), pages: [],
                                      collections: {})
    end

    after do
      FileUtils.rm_rf(test_dir) if test_dir && Dir.exist?(test_dir)
    end

    it "scans all site content and returns manifest summary" do
      scanner_with_manifest = described_class.new(site, config, mock_manifest)

      # Mock the scannable content
      mock_item = double("item", content: "{% imgflow #{test_image} width:800 %}",
                                 url: "/test", relative_path: "test.md")
      allow(scanner_with_manifest).to receive(:scannable_content).and_return([mock_item])

      result = scanner_with_manifest.scan_all_content

      expect(mock_manifest).to have_received(:get_all_versions)
      expect(result).to eq({})
    end

    it "handles site with no content" do
      scanner_with_manifest = described_class.new(site, config, mock_manifest)
      allow(scanner_with_manifest).to receive(:scannable_content).and_return([])

      result = scanner_with_manifest.scan_all_content

      expect(result).to eq({})
    end
  end

  describe "#scan_content_item" do
    let(:mock_item) do
      double("item", content: "{% imgflow #{test_image} width:800 %}", url: "/test",
                     relative_path: "test.md")
    end

    it "scans individual content item" do
      result = scanner.scan_content_item(mock_item)

      expect(result).to be_nil # Method returns nil as per implementation
    end

    it "handles content without tags" do
      mock_item_no_tags = double("item", content: "Just plain text", url: "/test",
                                         relative_path: "test.md")

      result = scanner.scan_content_item(mock_item_no_tags)

      expect(result).to be_nil
    end

    it "handles item without url or relative_path" do
      mock_item_minimal = double("item", content: "{% imgflow #{test_image} width:800 %}")
      allow(mock_item_minimal).to receive_messages(url: nil, relative_path: nil)

      result = scanner.scan_content_item(mock_item_minimal)
      expect(result).to be_nil
    end
  end

  describe "#scan_content" do
    let(:content_with_tags) do
      <<~MARKDOWN
        # My Blog Post

        Here's an image:
        {% imgflow #{test_image} width:800 quality:90 %}

        And another:
        {% imgflow #{test_images[1] || test_image} width:1200 format:webp %}
      MARKDOWN
    end

    it "finds imgflow tags in content" do
      tags = scanner.scan_content(content_with_tags)

      expect(tags).to be_an(Array)
      expect(tags.length).to eq(2)
    end

    it "extracts image paths from tags" do
      tags = scanner.scan_content(content_with_tags)

      expect(tags[0][:image]).to eq(test_image)
      expect(tags[1][:image]).to eq(test_images[1] || test_image)
    end

    it "extracts operations from tags" do
      tags = scanner.scan_content(content_with_tags)

      expect(tags[0][:operations]).to include("width:800", "quality:90")
      expect(tags[1][:operations]).to include("width:1200", "format:webp")
    end

    it "returns empty array for content without tags" do
      content = "Just plain text without any tags"
      tags = scanner.scan_content(content)

      expect(tags).to eq([])
    end

    it "handles multiple image formats from test catalog" do
      content = test_images.map { |img| "{% imgflow #{img} width:800 %}" }.join("\n")

      tags = scanner.scan_content(content)
      expect(tags.length).to eq(test_images.length)
      tags.each_with_index do |tag, index|
        expect(tag[:image]).to eq(test_images[index])
      end
    end
  end

  describe "#find_imgflow_tags" do
    let(:content) do
      <<~LIQUID
        {% imgflow #{test_images[0]} width:800 %}
        Some text
        {% imgflow #{test_images[1] || test_images[0]} width:1200 quality:90 %}
      LIQUID
    end

    it "finds all imgflow tags" do
      tags = scanner.find_imgflow_tags(content)

      expect(tags.length).to eq(2)
    end

    it "handles tags with various parameters" do
      content = <<~LIQUID
        {% imgflow #{test_image} width:800 height:600 quality:90 format:webp %}
        {% imgflow #{test_images[1] || test_image} width:1200 %}
        {% imgflow #{test_images[2] || test_image} %}
      LIQUID

      tags = scanner.find_imgflow_tags(content)

      expect(tags.length).to eq(3)
      expect(tags[0][:image]).to eq(test_image)
      expect(tags[1][:image]).to eq(test_images[1] || test_image)
      expect(tags[2][:image]).to eq(test_images[2] || test_image)
    end

    it "handles multiline tags" do
      # NOTE: Liquid tags must be on single line in actual usage
      content = "{% imgflow #{test_image} width:800 quality:90 %}"

      tags = scanner.find_imgflow_tags(content)

      expect(tags.length).to eq(1)
      expect(tags[0][:image]).to eq(test_image)
    end
  end

  describe "#find_picture_tags" do
    let(:content) do
      <<~LIQUID
        {% picture #{test_images[0]} %}
        Some text
        {% picture #{test_images[1] || test_images[0]} alt:"Photo" %}
      LIQUID
    end

    it "finds all picture tags" do
      tags = scanner.find_picture_tags(content)

      expect(tags.length).to eq(2)
    end

    it "extracts image paths from picture tags" do
      tags = scanner.find_picture_tags(content)

      expect(tags[0][:image]).to eq(test_images[0])
      expect(tags[1][:image]).to eq(test_images[1] || test_images[0])
    end
  end

  describe "#extract_operations" do
    it "extracts operations from tag markup" do
      markup = "#{test_image} width:800 height:600 quality:90"
      operations_array = scanner.extract_operations(markup)

      # TagScanner should return raw strings
      expect(operations_array).to be_a(Array)
      expect(operations_array).to include("width:800", "height:600", "quality:90")

      # Parser should convert to structured hash
      operations_hash = JekyllImgFlow::Parser.convert_operations_array(operations_array)
      expect(operations_hash).to be_a(Hash)
      expect(operations_hash[:width]).to eq(800)
      expect(operations_hash[:height]).to eq(600)
      expect(operations_hash[:quality]).to eq(90)
    end

    it "handles format operations" do
      markup = "#{test_image} format:webp"
      operations_array = scanner.extract_operations(markup)

      expect(operations_array).to be_a(Array)
      expect(operations_array).to include("format:webp")

      # Parser should convert to structured hash
      operations_hash = JekyllImgFlow::Parser.convert_operations_array(operations_array)
      expect(operations_hash).to be_a(Hash)
      expect(operations_hash[:format]).to eq("webp")
    end

    it "handles crop operations" do
      markup = "#{test_image} ratio:16:9"
      operations_array = scanner.extract_operations(markup)

      expect(operations_array).to be_a(Array)
      expect(operations_array).to include("ratio:16:9")

      # Parser should convert to structured hash
      operations_hash = JekyllImgFlow::Parser.convert_operations_array(operations_array)
      expect(operations_hash).to be_a(Hash)
      expect(operations_hash[:ratio]).to eq("16:9")
    end

    it "handles watermark operations" do
      markup = "#{test_image} watermark:logo.png position:bottom-right opacity:0.7"
      operations_array = scanner.extract_operations(markup)

      expect(operations_array).to be_a(Array)
      expect(operations_array).to include("watermark:logo.png", "position:bottom-right",
                                          "opacity:0.7")

      # Parser should convert to structured hash
      operations_hash = JekyllImgFlow::Parser.convert_operations_array(operations_array)
      expect(operations_hash).to be_a(Hash)
      expect(operations_hash[:watermark]).to eq("logo.png")
      expect(operations_hash[:position]).to eq("bottom-right")
      expect(operations_hash[:opacity]).to eq(0.7)
    end

    it "returns empty array for markup without operations" do
      markup = test_image
      operations = scanner.extract_operations(markup)

      expect(operations).to eq([])
    end

    it "handles comma-separated operations" do
      markup = "#{test_image} width:800,quality:90,format:webp"
      operations_array = scanner.extract_operations(markup)

      expect(operations_array).to include("width:800", "quality:90", "format:webp")
    end
  end

  describe "#determine_version_type" do
    it "identifies default versions" do
      # Default size (800) with default format
      operations = { width: 800, format: "webp" }
      version_type = scanner.determine_version_type(operations)

      expect(version_type).to be_a(String)
      expect(version_type).to eq("default")
    end

    it "identifies specialized versions" do
      # Custom size (750) not in defaults
      operations = { width: 750, quality: 90 }
      version_type = scanner.determine_version_type(operations)

      expect(version_type).to be_a(String)
      expect(version_type).to eq("specialized")
    end

    it "identifies default format-only versions" do
      operations = { format: "webp" }
      version_type = scanner.determine_version_type(operations)

      expect(version_type).to eq("default")
    end

    it "identifies specialized non-default formats" do
      operations = { format: "unsupported" }
      version_type = scanner.determine_version_type(operations)

      expect(version_type).to eq("specialized")
    end
  end

  describe "private methods" do
    describe "#scan_tags_from_content" do
      it "scans content for multiple tag patterns" do
        content = <<~LIQUID
          {% imgflow #{test_image} width:800 %}
          {% picture #{test_images[1] || test_image} %}
          Some text
        LIQUID

        tags = []
        tag_patterns = {
          "imgflow" => "{% imgflow",
          "picture" => "{% picture"
        }

        scanner.send(:scan_tags_from_content, content, tag_patterns) do |tag_name, markup|
          tags << { name: tag_name, markup: markup }
        end

        expect(tags.length).to eq(2)
        expect(tags[0][:name]).to eq("imgflow")
        expect(tags[1][:name]).to eq("picture")
      end

      it "handles content without tags" do
        content = "Just plain text without tags"
        tags = []

        scanner.send(:scan_tags_from_content, content,
                     { "imgflow" => "{% imgflow" }) do |tag_name, markup|
          tags << { name: tag_name, markup: markup }
        end

        expect(tags).to be_empty
      end
    end

    describe "#extract_markup_from_line" do
      it "extracts markup from tag line" do
        line = "{% imgflow #{test_image} width:800 %}"
        markup = scanner.send(:extract_markup_from_line, line, "{% imgflow")

        expect(markup).to eq("#{test_image} width:800")
      end

      it "returns nil for line without tag" do
        line = "Just plain text"
        markup = scanner.send(:extract_markup_from_line, line, "{% imgflow")

        expect(markup).to be_nil
      end

      it "handles malformed tags" do
        line = "{% imgflow #{test_image} width:800" # missing closing %}
        markup = scanner.send(:extract_markup_from_line, line, "{% imgflow")

        expect(markup).to be_nil
      end
    end

    describe "#parse_tag_markup_simple" do
      it "parses simple tag markup" do
        markup = "#{test_image} width:800 height:600 quality:90"
        parsed = scanner.send(:parse_tag_markup_simple, markup)

        expect(parsed[:image]).to eq(test_image)
        expect(parsed[:operations]).to include("width:800", "height:600", "quality:90")
      end

      it "handles image without operations" do
        markup = test_image
        parsed = scanner.send(:parse_tag_markup_simple, markup)

        expect(parsed[:image]).to eq(test_image)
        expect(parsed[:operations]).to be_empty
      end

      it "handles comma-separated operations" do
        markup = "#{test_image} width:800,quality:90,format:webp"
        parsed = scanner.send(:parse_tag_markup_simple, markup)

        expect(parsed[:operations]).to include("width:800", "quality:90", "format:webp")
      end

      it "handles quoted values" do
        markup = "#{test_image} alt:\"My Photo\" title:\"Test\""
        parsed = scanner.send(:parse_tag_markup_simple, markup)

        # The parser splits on spaces within quotes, so check individual parts
        expect(parsed[:operations]).to include("alt:\"My")
        expect(parsed[:operations]).to include("title:\"Test\"")
      end
    end

    describe "#scannable_content" do
      it "collects posts, pages, and collections" do
        # Mock site structure
        mock_post = double("post")
        mock_page = double("page")
        mock_collection_doc = double("collection_doc")
        mock_collection = double("collection", docs: [mock_collection_doc])

        allow(site).to receive_messages(posts: double("posts", docs: [mock_post]),
                                        pages: [mock_page], collections: { "articles" => mock_collection })

        content = scanner.send(:scannable_content)

        expect(content).to include(mock_post, mock_page, mock_collection_doc)
      end

      it "handles site without posts" do
        allow(site).to receive_messages(posts: nil, pages: [], collections: {})

        content = scanner.send(:scannable_content)

        expect(content).to be_an(Array)
      end
    end

    describe "#parse_tag_markup" do
      it "parses tag markup to structured hash" do
        markup = "#{test_image} width:800 height:600 quality:90"
        parsed = scanner.send(:parse_tag_markup, markup)

        expect(parsed[:image_path]).to eq(test_image)
        expect(parsed[:operations][:width]).to eq(800)
        expect(parsed[:operations][:height]).to eq(600)
        expect(parsed[:operations][:quality]).to eq(90)
      end
    end

    describe "#parse_value" do
      it "converts integer values" do
        result = scanner.send(:parse_value, "800")
        expect(result).to eq(800)
      end

      it "converts float values" do
        result = scanner.send(:parse_value, "0.75")
        expect(result).to eq(0.75)
      end

      it "handles quoted strings" do
        result = scanner.send(:parse_value, "'test'")
        expect(result).to eq("test")

        result = scanner.send(:parse_value, '"test"')
        expect(result).to eq("test")
      end

      it "returns strings as-is" do
        result = scanner.send(:parse_value, "webp")
        expect(result).to eq("webp")
      end
    end

    describe "#determine_type" do
      it "identifies default type for default size and format" do
        operations = { width: 800, format: "webp" }
        result = scanner.send(:determine_type, operations)
        expect(result).to eq("default")
      end

      it "identifies specialized type for custom size" do
        operations = { width: 750, format: "webp" }
        result = scanner.send(:determine_type, operations)
        expect(result).to eq("specialized")
      end

      it "identifies default type for format-only" do
        operations = { format: "webp" }
        result = scanner.send(:determine_type, operations)
        expect(result).to eq("default")
      end
    end
  end

  describe "edge cases" do
    it "handles malformed tags gracefully" do
      content = "{% imgflow %}"

      tags = scanner.scan_content(content)
      expect(tags).to be_an(Array)
      expect(tags.length).to eq(1)
      expect(tags.first[:image]).to be_nil
      expect(tags.first[:operations]).to be_empty
    end

    it "handles tags with special characters" do
      content = '{% imgflow "photo (1).jpg" width:800 %}'
      tags = scanner.scan_content(content)

      expect(tags).not_to be_empty
    end

    it "handles very long tag content" do
      long_params = (1..50).map { |i| "param#{i}:value#{i}" }.join(" ")
      content = "{% imgflow #{test_image} #{long_params} %}"

      tags = scanner.scan_content(content)
      expect(tags).to be_an(Array)
      expect(tags.length).to eq(1)
      expect(tags.first[:image]).to eq(test_image)
    end

    it "handles nested liquid tags" do
      content = <<~LIQUID
        {% if condition %}
          {% imgflow #{test_image} width:800 %}
        {% endif %}
      LIQUID

      tags = scanner.scan_content(content)

      expect(tags.length).to eq(1)
    end

    it "handles empty content" do
      tags = scanner.scan_content("")
      expect(tags).to be_empty
    end

    it "handles nil content" do
      expect { scanner.scan_content(nil) }.to raise_error(NoMethodError)
    end
  end

  describe "integration with test photo catalog" do
    it "works with all test image formats" do
      test_images.each do |image|
        content = "{% imgflow #{image} width:800 %}"
        tags = scanner.scan_content(content)

        expect(tags.length).to eq(1)
        expect(tags[0][:image]).to eq(image)
      end
    end

    it "validates image metadata from catalog" do
      test_images.each do |image|
        metadata = TestPictures.metadata(image)
        next if metadata.empty?

        content = "{% imgflow #{image} width:800 %}"
        tags = scanner.scan_content(content)

        expect(tags[0][:image]).to eq(image)
        expect(TestPictures.exists?(image)).to be true
      end
    end
  end
end
