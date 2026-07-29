# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::PathResolver, :unit do
  let(:test_site_dir) { create_test_dir("path_resolver_test") }
  let(:site) { create_mock_site(source: test_site_dir) }
  let(:components) { create_imgflow_components(site) }
  let(:path_resolver) { components[:path_resolver] }
  let(:test_image_name) { TestPictures.get(:default).first }

  before do
    # Create test directory structure
    originals_dir = File.join(test_site_dir, components[:config].originals)
    FileUtils.mkdir_p(originals_dir)
  end

  describe "#resolve_original_path - NEW VALIDATION RESPONSIBILITY" do
    context "when image exists and is valid" do
      it "resolves path and validates file exists" do
        # Copy a real test image for validation
        test_image_path = fixture_image_path(test_image_name)
        target_path = File.join(test_site_dir, components[:config].originals, test_image_name)
        FileUtils.cp(test_image_path, target_path)

        result = path_resolver.resolve_original_path(test_image_name)
        expect(result).to eq(target_path)
        expect(File.exist?(result)).to be true
        expect(File.file?(result)).to be true
        expect(File.readable?(result)).to be true
      end

      it "validates file format against config" do
        # Test with a supported format (jpg)
        jpg_image = TestPictures.get(:default).find { |img| img.end_with?(".jpg") }
        test_image_path = fixture_image_path(jpg_image)
        target_path = File.join(test_site_dir, components[:config].originals, jpg_image)
        FileUtils.cp(test_image_path, target_path)

        result = path_resolver.resolve_original_path(jpg_image)
        expect(result).to eq(target_path)
      end
    end

    context "when validation fails" do
      it "raises error when file does not exist" do
        expect { path_resolver.resolve_original_path("nonexistent.jpg") }.to raise_error(
          ArgumentError, /Cannot resolve image path.*not found/
        )
      end

      it "raises error when path is not a file" do
        # Create a directory instead of a file
        dir_path = File.join(test_site_dir, components[:config].originals, "not_a_file")
        FileUtils.mkdir_p(dir_path)

        expect { path_resolver.resolve_original_path("not_a_file") }.to raise_error(
          ArgumentError, /Image path is not a file/
        )
      end

      it "raises error when file is not readable" do
        # Create a file and make it unreadable
        unreadable_file = File.join(test_site_dir, components[:config].originals, "unreadable.jpg")
        FileUtils.touch(unreadable_file)
        File.chmod(0o000, unreadable_file)

        expect { path_resolver.resolve_original_path("unreadable.jpg") }.to raise_error(
          ArgumentError, /Image path not readable/
        )
      end

      it "raises error when file format is not supported" do
        # Create a file with unsupported extension
        unsupported_file = File.join(test_site_dir, components[:config].originals, "test.xyz")
        FileUtils.touch(unsupported_file)

        expect { path_resolver.resolve_original_path("test.xyz") }.to raise_error(
          ArgumentError, /Invalid input format.*Must be one of/
        )
      end
    end

    context "with TestPictures integration" do
      it "handles complex image names from TestPictures" do
        complex_image = TestPictures.get(:default).find { |img| img.include?("mars-crater") }
        test_image_path = fixture_image_path(complex_image)
        target_path = File.join(test_site_dir, components[:config].originals, complex_image)
        FileUtils.cp(test_image_path, target_path)

        result = path_resolver.resolve_original_path(complex_image)
        expect(result).to eq(target_path)
        expect(File.exist?(result)).to be true
      end

      it "validates all supported formats from TestPictures" do
        # Get all formats available in TestPictures catalog
        available_formats = TestPictures.get(:default).map do |img|
          File.extname(img).delete(".")
        end.uniq

        available_formats.each do |format|
          image = TestPictures.by_format(format.to_sym).first
          next unless image

          test_image_path = fixture_image_path(image)
          target_path = File.join(test_site_dir, components[:config].originals, image)
          FileUtils.cp(test_image_path, target_path)

          result = path_resolver.resolve_original_path(image)
          expect(result).to eq(target_path)
        end
      end
    end
  end

  describe "#resolve_output_path - PATH RESOLUTION RESPONSIBILITY" do
    it "resolves output path for TestPictures filename" do
      # Use TestPictures expected filename
      expected_filename = TestPictures.expected_filename(test_image_name, :md, :webp)
      result = path_resolver.resolve_output_path(expected_filename)
      expected_path = File.join(test_site_dir, "_site", components[:config].output,
                                expected_filename)
      expect(result).to eq(expected_path)
    end

    it "handles complex generated filenames from TestPictures" do
      # Test with a complex filename from TestPictures
      complex_image = TestPictures.get(:default).find { |img| img.include?("mars-crater") }
      expected_filename = TestPictures.expected_filename(complex_image, :lg, :avif)
      result = path_resolver.resolve_output_path(expected_filename)
      expected_path = File.join(test_site_dir, "_site", components[:config].output,
                                expected_filename)
      expect(result).to eq(expected_path)
    end
  end

  describe "#temp_output_path" do
    it "creates temporary output path" do
      result = path_resolver.temp_output_path("jpg")

      expect(result).to include(Dir.tmpdir)
      expect(result).to include("imgflow-out")
      expect(result).to end_with(".jpg")
    end

    it "generates unique temp paths" do
      path1 = path_resolver.temp_output_path("jpg")
      path2 = path_resolver.temp_output_path("jpg")

      expect(path1).not_to eq(path2)
    end
  end

  describe "#temp_input_path" do
    it "creates temporary input path" do
      result = path_resolver.temp_input_path("jpg")

      expect(result).to include(Dir.tmpdir)
      expect(result).to include("imgflow-in")
      expect(result).to end_with(".jpg")
    end

    it "uses default extension" do
      result = path_resolver.temp_input_path

      expect(result).to include(Dir.tmpdir)
      expect(result).to include("imgflow-in")
      expect(result).to end_with(".tmp")
    end
  end

  describe "#build_url - URL GENERATION" do
    let(:site_with_url) { create_mock_site(config: TEST_CONFIG.merge("url" => "https://example.com", "baseurl" => "/blog")) }

    it "builds absolute URL for TestPictures optimized image" do
      # Use TestPictures expected filename
      expected_filename = TestPictures.expected_filename(test_image_name, :md, :webp)
      relative_path = File.join(components[:config].output, expected_filename)

      result = path_resolver.build_url(relative_path, site_with_url)
      expect(result).to eq("https://example.com/blog/#{relative_path}")
    end

    it "uses default URL when not configured" do
      site_no_url = create_mock_site(config: TEST_CONFIG.except("url"))
      expected_filename = TestPictures.expected_filename(test_image_name, :md, :webp)
      relative_path = File.join(components[:config].output, expected_filename)

      result = path_resolver.build_url(relative_path, site_no_url)
      expect(result).to eq("http://localhost:4000/#{relative_path}")
    end
  end

  describe "#relative_from_dest - PATH MANIPULATION" do
    it "creates relative path from destination for TestPictures" do
      expected_filename = TestPictures.expected_filename(test_image_name, :md, :webp)
      full_path = File.join(test_site_dir, "_site", components[:config].output, expected_filename)

      result = path_resolver.relative_from_dest(full_path, site)
      expected_relative = File.join(components[:config].output, expected_filename)
      expect(result).to eq(expected_relative)
    end

    it "handles paths outside destination" do
      result = path_resolver.relative_from_dest("/other/path/test.jpg", site)
      expect(result).to eq("/other/path/test.jpg")
    end
  end

  describe "#http_path" do
    it "returns relative path for URL" do
      result = path_resolver.http_path("test.jpg")
      expect(result).to include("test.jpg")
      expect(result).to include(components[:config].originals)
    end
  end

  describe "#resolve_source_output_path" do
    it "returns path in source directory" do
      result = path_resolver.resolve_source_output_path("output.webp")
      expect(result).to include("output.webp")
      expect(result).to include(components[:config].output)
      expect(result).to include(site.source)
    end
  end

  describe "#resolve_relative_output_path" do
    it "returns relative path without site root" do
      result = path_resolver.resolve_relative_output_path("output.webp")
      expect(result).to include("output.webp")
      expect(result).to include(components[:config].output)
      expect(result).not_to include(site.source)
      expect(result).not_to include(site.dest)
    end
  end
end
