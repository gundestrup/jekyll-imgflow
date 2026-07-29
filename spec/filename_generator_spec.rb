# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::FilenameGenerator, :unit do
  let(:generator) { described_class.new }
  let(:test_image) { File.join(TestPictures::FIXTURES_DIR, "mars-crater-large.jpg") }
  let(:test_image_name) { "mars-crater-large.jpg" }

  # Enhanced helpers using TestPictures
  let(:expected_md_webp) { TestPictures.expected_filename(test_image_name, :md, :webp) }
  let(:expected_lg_avif) { TestPictures.expected_filename(test_image_name, :lg, :avif) }
  let(:expected_xl_jpg) { TestPictures.expected_filename(test_image_name, :xl, :jpg) }
  let(:expected_sm_png) { TestPictures.expected_filename(test_image_name, :sm, :png) }

  describe "#generate_filename" do
    it "outputs correct filename for basic image" do
      operations = { width: 800, format: "webp", quality: 85 }
      filename = generator.generate_filename(test_image, operations)

      # Validate against exact expected filename from TestPictures
      expect(filename).to eq(expected_md_webp)
    end

    it "outputs correct filename with different size" do
      operations = { width: 1200, format: "jpg", quality: 85 }
      filename = generator.generate_filename(test_image, operations)

      # Generate expected filename for lg size
      expected_lg_jpg = TestPictures.expected_filename(test_image_name, :lg, :jpg)
      expect(filename).to eq(expected_lg_jpg)
    end

    it "outputs correct filename with different format" do
      operations = { width: 800, format: "avif", quality: 85 }
      filename = generator.generate_filename(test_image, operations)

      # Validate against exact expected filename from TestPictures
      expect(filename).to eq(expected_md_webp.gsub(".webp", ".avif"))
    end

    it "outputs correct filename with quality option" do
      operations = { width: 800, quality: 90, format: "webp" }
      filename = generator.generate_filename(test_image, operations)

      # Quality should not appear in filename (JPT compatibility)
      expect(filename).to include("mars-crater-large-800-")
      expect(filename).not_to include("q90")
      expect(filename).not_to include("quality")
    end

    it "outputs same filename for same image and options" do
      operations = { width: 800, format: "webp", quality: 85 }

      filename1 = generator.generate_filename(test_image, operations)
      filename2 = generator.generate_filename(test_image, operations)

      expect(filename1).to eq(filename2)
    end

    it "outputs different filenames for different options" do
      operations1 = { width: 800, quality: 90, format: "webp" }
      operations2 = { width: 800, quality: 85, format: "webp" }

      filename1 = generator.generate_filename(test_image, operations1)
      filename2 = generator.generate_filename(test_image, operations2)

      expect(filename1).not_to eq(filename2)
    end

    it "outputs different filenames for different sizes" do
      operations1 = { width: 800, format: "webp", quality: 85 }
      operations2 = { width: 1200, format: "webp", quality: 85 }

      filename1 = generator.generate_filename(test_image, operations1)
      filename2 = generator.generate_filename(test_image, operations2)

      expect(filename1).not_to eq(filename2)
    end

    it "uses original format when format not specified" do
      operations = { width: 800, quality: 85 }
      filename = generator.generate_filename(test_image, operations)

      expect(filename).to include("mars-crater-large-800-")
      expect(filename).to end_with(".jpg")
    end

    it "generates correct filenames for different test images" do
      # Test with different images from TestPictures
      test_images = [
        { name: "file_example-large.png", format: :png },
        { name: "ayousef-espanioly.avif", format: :avif },
        { name: "file_example-medium.svg", format: :svg }
      ]

      test_images.each do |image_info|
        operations = { width: 800, format: "webp", quality: 85 }

        # Get the actual test image path
        image_path = File.join(TestPictures::FIXTURES_DIR, image_info[:name])

        # Skip if file doesn't exist
        next unless File.exist?(image_path)

        filename = generator.generate_filename(image_path, operations)
        expected = TestPictures.expected_filename(image_info[:name], :md, :webp)

        if expected
          expect(filename).to eq(expected), "Failed for #{image_info[:name]}"
        else
          # Fallback for images not in TestPictures catalog
          expect(filename).to include(File.basename(image_info[:name], ".*"))
          expect(filename).to include("800-")
          expect(filename).to end_with(".webp")
        end
      end
    end

    it "validates hash consistency across different operations" do
      # Test that the hash is consistent for the same image
      operations1 = { width: 800, format: "webp", quality: 85 }
      operations2 = { width: 800, format: "avif", quality: 85 }
      operations3 = { width: 1200, format: "webp", quality: 85 }

      filename1 = generator.generate_filename(test_image, operations1)
      filename2 = generator.generate_filename(test_image, operations2)
      filename3 = generator.generate_filename(test_image, operations3)

      # Validate against TestPictures expected filenames
      expected_md_webp = TestPictures.expected_filename(test_image_name, :md, :webp)
      expected_md_avif = TestPictures.expected_filename(test_image_name, :md, :avif)
      expected_lg_webp = TestPictures.expected_filename(test_image_name, :lg, :webp)

      expect(filename1).to eq(expected_md_webp)
      expect(filename2).to eq(expected_md_avif)
      expect(filename3).to eq(expected_lg_webp)

      # Extract hash from one filename to verify consistency
      hash = filename1.match(/mars-crater-large-\d+-([a-f0-9]{9})\.webp$/)[1]
      expected_hash = TestPictures.hash(test_image_name)
      expect(hash).to eq(expected_hash)
    end

    it "generates different hashes with different keep parameters" do
      # Test that keep parameter affects hash (JPT compatibility)
      operations1 = { width: 800, format: "webp", quality: 85, keep: "attention" }
      operations2 = { width: 800, format: "webp", quality: 85, keep: "entropy" }
      operations3 = { width: 800, format: "webp", quality: 85, keep: "center" }

      filename1 = generator.generate_filename(test_image, operations1)
      filename2 = generator.generate_filename(test_image, operations2)
      filename3 = generator.generate_filename(test_image, operations3)

      # Extract hashes to test differences (keep parameter affects hash)
      hash1 = filename1.match(/mars-crater-large-\d+-([a-f0-9]{9})\.webp$/)[1]
      hash2 = filename2.match(/mars-crater-large-\d+-([a-f0-9]{9})\.webp$/)[1]
      hash3 = filename3.match(/mars-crater-large-\d+-([a-f0-9]{9})\.webp$/)[1]

      # Different keep values should produce different hashes
      expect(hash1).not_to eq(hash2)
      expect(hash1).not_to eq(hash3)
      expect(hash2).not_to eq(hash3)

      # Verify they're different from default hash
      default_hash = TestPictures.hash(test_image_name)
      expect(hash1).not_to eq(default_hash) # keep parameter changes hash
    end

    it "generates same hash when keep parameter is nil" do
      # Test that nil keep parameter produces consistent hash
      operations1 = { width: 800, format: "webp", quality: 85 }
      operations2 = { width: 800, format: "webp", quality: 85, keep: nil }

      filename1 = generator.generate_filename(test_image, operations1)
      filename2 = generator.generate_filename(test_image, operations2)

      # Should produce same hash
      expect(filename1).to eq(filename2)
    end
  end

  describe "#parse_filename" do
    it "parses filename back to components" do
      filename = "test-800-123456789.webp"
      parsed = generator.parse_filename(filename)

      expect(parsed[:base_name]).to eq("test")
      expect(parsed[:width]).to eq(800)
      expect(parsed[:hash]).to eq("123456789")
      expect(parsed[:format]).to eq("webp")
    end

    it "parses real expected filenames correctly" do
      # Test parsing real filenames from TestPictures
      real_filenames = [
        expected_md_webp,
        expected_lg_avif,
        expected_xl_jpg
      ].compact

      real_filenames.each do |filename|
        parsed = generator.parse_filename(filename)

        expect(parsed[:base_name]).to eq("mars-crater-large")
        expect(%w[webp avif jpg]).to include(parsed[:format])
        expect([800, 1200, 2000]).to include(parsed[:width])
        expect(parsed[:hash]).to match(/^[a-f0-9]{9}$/)

        # Verify hash matches TestPictures
        expect(parsed[:hash]).to eq(TestPictures.hash(test_image_name))
      end
    end
  end

  describe "#file_digest" do
    it "generates SHA256 digest for image file" do
      digest = generator.file_digest(test_image)

      expect(digest).to be_a(String)
      expect(digest.length).to eq(64) # SHA256
    end
  end
end
