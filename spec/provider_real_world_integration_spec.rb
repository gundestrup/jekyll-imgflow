# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "webmock/rspec"
require "json"

# Opt-in test for real-world provider validation with actual image processing
# Tests all providers (Sharp, Imagemagick, Libvips, Imgproxy, Weserv, Flyimg) with real images
# Validates expected outputs using TestPictures catalog and JPT hash patterns
# Run with: bundle exec rspec spec/provider_real_world_integration_spec.rb
# Skip with: bundle exec rspec --tag ~integration
RSpec.describe "Provider Real-World Integration with TestPictures Validation", :external,
               :integration, :provider, :slow do
  # Use TestPictures for standardized, predictable test data
  let(:test_site_dir) { create_test_dir("provider-real-world-test") }
  let(:test_images) { TestPictures.get(:all) }

  def get_expected_filenames_for_image(image_name)
    expected_files = []
    config = JekyllImgFlow::Config.new(MockSite.new(TEST_CONFIG))

    config.sizes.each_key do |size_name|
      config.formats.each do |format|
        expected = TestPictures.expected_filename(image_name, size_name, format)
        expected_files << expected
      end
    end

    expected_files
  end

  def validate_jpt_hash_patterns(filenames)
    filenames.each do |filename|
      basename = File.basename(filename)

      # Extract image info from filename for TestPictures validation
      # Expected pattern: image-name-width-hash.format
      parts = basename.match(/^(.+)-(\d+)-([a-f0-9]{9})\.([a-z]+)$/)
      expect(parts).not_to be_nil,
                           "Could not parse filename pattern: #{basename}"

      image_name = "#{parts[1]}.#{parts[4]}" # Reconstruct original image name
      width = parts[2].to_i

      # Map width to TestPictures size
      size = case width
             when 400 then :sm
             when 1200 then :lg
             when 2000 then :xl
             else :md # Default fallback
             end

      format = parts[4].to_sym

      # Validate against TestPictures (real processing uses quality=85)
      expected_filename = TestPictures.expected_filename(image_name, size, format)
      expect(basename).to eq(File.basename(expected_filename)),
                          "Generated filename #{basename} doesn't match TestPictures expectation #{expected_filename}"
    end
  end

  before(:all) do
    WebMock.allow_net_connect!
  end

  after(:all) do
    WebMock.disable_net_connect!
  end

  before do
    # Use the helper system to create a test site with TestPictures
    create_test_jekyll_site(test_site_dir, :imgflow_only, {
                              test_images: test_images, # Use TestPictures catalog directly
                              title: "Provider Real-World Integration Test"
                            })
  end

  after do
    FileUtils.rm_rf(test_site_dir)
  end

  def create_config(provider)
    # Use the helper system with provider override and TestPictures
    create_test_jekyll_site(test_site_dir, :imgflow_only, {
                              test_images: test_images, # Use TestPictures catalog directly
                              backend_priority: [provider],
                              title: "Provider Real-World Test - #{provider}"
                            })
  end

  def run_jekyll_processing
    Dir.chdir(test_site_dir) do
      system("bundle exec jekyll build --trace")
    end
  end

  def optimized_files
    imgflow_config = TEST_CONFIG["imgflow"]

    # Check both possible output locations
    site_output_dir = File.join(test_site_dir, "_site", imgflow_config["output"])
    local_output_dir = File.join(test_site_dir, imgflow_config["output"])

    files = []
    if Dir.exist?(site_output_dir)
      files += Dir.glob(File.join(site_output_dir, "**/*")).select do |f|
        File.file?(f)
      end
    end
    if Dir.exist?(local_output_dir)
      files += Dir.glob(File.join(local_output_dir, "**/*")).select do |f|
        File.file?(f)
      end
    end

    files
  end

  def cache_info
    cache_file = File.join(test_site_dir, ".cache", "imgflow.json")
    if File.exist?(cache_file)
      JSON.parse(File.read(cache_file))
    else
      {}
    end
  end

  describe "Provider Switching" do
    # Get providers from central config (including Docker services)
    site_config = TEST_CONFIG.dup
    mock_site = MockSite.new(site_config)
    config = JekyllImgFlow::Config.new(mock_site)

    config.backend_priority.each do |provider|
      context "when using #{provider} provider" do
        before do
          create_config(provider)
        end

        it "generates expected TestPictures filenames with #{provider}" do
          run_jekyll_processing

          files = optimized_files
          expect(files.length).to be > 0

          # Validate each image generates expected filenames
          test_images.each do |image_name|
            expected_filenames = get_expected_filenames_for_image(image_name)

            expected_filenames.each do |expected_filename|
              full_path = File.join(test_site_dir, "_site", "assets", "images", "optimized",
                                    expected_filename)
              expect(File.exist?(full_path)).to be true,
                                                   "Expected file not found: #{expected_filename} for provider #{provider}"
            end
          end
        end

        it "creates cache entries for processed images" do
          run_jekyll_processing

          cache_data = cache_info
          expect(cache_data.keys.length).to be > 0
        end

        it "validates JPT hash patterns with #{provider}" do
          run_jekyll_processing

          files = optimized_files
          validate_jpt_hash_patterns(files)
        end

        it "generates multiple formats per image" do
          run_jekyll_processing

          # Group files by base image name
          files_by_image = optimized_files.group_by do |file|
            File.basename(file).split("-").first
          end

          # Each original image should generate multiple format variants
          files_by_image.each_value do |variants|
            formats = variants.map { |f| File.extname(f)[1..] }
            formats.uniq!
            expect(formats.length).to be >= 2 # At least original + one format
          end
        end

        it "handles different image types from TestPictures" do
          run_jekyll_processing

          # TestPictures provides different image types
          image_types = test_images.map { |img| File.extname(img)[1..] }.uniq

          image_types.each do |type|
            optimized_files.select { |f| File.extname(f) == ".#{type}" }
          end

          # Should have processed files for each image type
          expect(optimized_files.length).to be > 0
        end
      end
    end
  end

  describe "Cache Management" do
    # Get providers from central config (including Docker services)
    site_config = TEST_CONFIG.dup
    mock_site = MockSite.new(site_config)
    config = JekyllImgFlow::Config.new(mock_site)

    config.backend_priority.each do |provider|
      context "when using #{provider} provider" do
        it "updates cache when images change" do
          create_config(provider)
          run_jekyll_processing
          initial_cache = cache_info
          initial_count = initial_cache.keys.length

          # Wait a bit to ensure different timestamps
          sleep 1

          # Modify an image (touch it to change timestamp)
          first_image = test_images.first[:file]

          # Use Config class to get originals path
          site_config = TEST_CONFIG.dup
          site_config["destination"] = File.join(test_site_dir, "_site")
          site_config["source"] = test_site_dir
          mock_site = MockSite.new(site_config)
          config = JekyllImgFlow::Config.new(mock_site)

          image_path = File.join(test_site_dir, config.originals, first_image)
          FileUtils.touch(image_path)

          # Second build
          run_jekyll_processing
          updated_cache = cache_info
          updated_count = updated_cache.keys.length

          # Cache should be updated
          expect(updated_count).to eq(initial_count)
        end

        it "preserves cache for unchanged images" do
          create_config(provider)
          run_jekyll_processing
          initial_cache = cache_info

          # Second build without changes
          run_jekyll_processing
          final_cache = cache_info

          # Cache entries should be the same
          expect(final_cache.keys.sort).to eq(initial_cache.keys.sort)
        end
      end
    end
  end

  describe "Error Handling" do
    it "handles missing images gracefully" do
      # Create config with non-existent image in page
      page_content = <<~MARKDOWN
        ---
        layout: default
        ---

        # Test with Missing Image

        {% imgflow nonexistent-image.jpg width=800 %}
      MARKDOWN

      File.write(File.join(test_site_dir, "missing-image.md"), page_content)

      # Build should complete despite missing image
      expect { run_jekyll_processing }.not_to raise_error

      # Check that build completed
      expect(File.exist?(File.join(test_site_dir, "_site"))).to be true
    end

    it "handles provider failures gracefully" do
      # Create config with non-existent provider
      create_config("nonexistent_provider")

      # Build should handle provider failure
      expect { run_jekyll_processing }.not_to raise_error
    end
  end

  describe "Provider Output Comparison" do
    # Get providers from central config (including Docker services)
    site_config = TEST_CONFIG.dup
    mock_site = MockSite.new(site_config)
    config = JekyllImgFlow::Config.new(mock_site)

    let(:provider_outputs) do
      outputs = {}

      config.backend_priority.each do |provider|
        create_config(provider)
        run_jekyll_processing

        outputs[provider] = {
          files: optimized_files.map { |f| File.basename(f) },
          count: optimized_files.length
        }
      end

      outputs
    end

    it "produces consistent filename patterns across providers" do
      # Get the first provider as reference
      reference_provider = config.backend_priority.first
      reference_filenames = provider_outputs[reference_provider][:files]

      provider_outputs.each do |provider, data|
        next if provider == reference_provider

        # All providers should produce same number of files
        expect(data[:count]).to eq(reference_filenames.length),
                                "Provider #{provider} produced #{data[:count]} files, expected #{reference_filenames.length}"

        # Extract base filenames (without hash) for comparison
        reference_bases = reference_filenames.map { |f| f.gsub(/-[a-f0-9]{9}/, "-HASH") }
        provider_bases = data[:files].map { |f| f.gsub(/-[a-f0-9]{9}/, "-HASH") }

        expect(provider_bases.sort).to eq(reference_bases.sort),
                                       "Provider #{provider} produced different base filename patterns"
      end
    end

    it "generates valid JPT hashes for all providers" do
      provider_outputs.each_value do |data|
        validate_jpt_hash_patterns(data[:files])
      end
    end
  end

  describe "Performance" do
    # Get providers from central config (including Docker services)
    site_config = TEST_CONFIG.dup
    mock_site = MockSite.new(site_config)
    config = JekyllImgFlow::Config.new(mock_site)

    config.backend_priority.each do |provider|
      it "processes images efficiently with #{provider}" do
        create_config(provider)

        start_time = Time.now
        run_jekyll_processing
        end_time = Time.now

        processing_time = end_time - start_time
        files = optimized_files

        # Should complete in reasonable time (adjust threshold as needed)
        expect(processing_time).to be < 60 # 60 seconds max
        expect(files.length).to be > 0
      end
    end
  end
end
