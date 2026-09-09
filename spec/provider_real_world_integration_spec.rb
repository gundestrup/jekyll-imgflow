# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "webmock/rspec"
require "json"
require "yaml"

# Opt-in test for real-world provider validation with actual image processing
# Tests all providers (Sharp, Imagemagick, LibVips, Imgproxy, Weserv, Flyimg) with real images
# Validates expected outputs using TestPictures catalog and JPT hash patterns
#
# Run all slow tests:  bundle exec rspec --tag slow
# Run single provider: IMGFLOW_TEST_PROVIDER=imagemagick bundle exec rspec --tag slow
# Run providers in parallel: rake parallel:slow
# Full SVG test for IM: FULL_SVG_TEST=true IMGFLOW_TEST_PROVIDER=imagemagick bundle exec rspec --tag slow
#
# Skip with: bundle exec rspec --tag ~integration

RSpec.describe "Provider Real-World Integration with TestPictures Validation", :external,
               :integration, :provider, :slow do
  before(:all) do
    WebMock.allow_net_connect!
  end

  after(:all) do
    WebMock.disable_net_connect!
  end

  # ------------------------------------------------------------------
  # Provider Switching — one shared build per provider context
  # ------------------------------------------------------------------
  describe "Provider Switching", :provider_single do
    TestEnvironment.providers_for_test(TEST_CONFIG).each do |provider|
      context "when using #{provider} provider" do
        # Run one build per provider, shared across all tests in this context.
        # This gives ~4x speedup vs rebuilding for each test.
        before(:all) do
          @provider = provider
          @site_dir = create_test_dir("provider-real-world-#{provider}")
          @images = test_images_for_provider(provider)

          skip "#{provider} provider is not available" unless provider_available_for_test?(provider)

          scaffold_provider_test_site(@site_dir, @provider, @images)
          build_provider_test_site(@site_dir, @provider)
        end

        after(:all) do
          FileUtils.rm_rf(@site_dir) if @site_dir
        end

        it "generates expected TestPictures filenames with #{provider}" do
          files = optimized_files_for(@site_dir)
          expect(files.length).to be > 0

          @images.each do |image|
            image_name = image
            expected_filenames = expected_filenames_for(image_name)

            expected_filenames.each do |expected_filename|
              full_path = File.join(@site_dir, "_site", "assets", "images", "optimized",
                                    expected_filename)
              expect(File.exist?(full_path)).to be true,
                                                   "Expected file not found: #{expected_filename} for provider #{provider}"
            end
          end
        end

        it "creates manifest entries for processed images" do
          images = manifest_data_for(@site_dir).fetch("images", {})
          expect(images).not_to be_empty
        end

        it "validates JPT hash patterns with #{provider}" do
          files = optimized_files_for(@site_dir)
          validate_jpt_hash_patterns(files)
        end

        it "generates multiple formats per image" do
          files_by_image = optimized_files_for(@site_dir).group_by do |file|
            File.basename(file).split("-").first
          end

          files_by_image.each_value do |variants|
            formats = variants.map { |f| File.extname(f)[1..] }
            formats.uniq!
            expect(formats.length).to be >= 2
          end
        end

        it "handles different image types from TestPictures" do
          image_types = @images.map { |img| File.extname(img)[1..] }.uniq

          image_types.each do |type|
            optimized_files_for(@site_dir).select { |f| File.extname(f) == ".#{type}" }
          end

          expect(optimized_files_for(@site_dir).length).to be > 0
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # Cache Management — shares initial build, then tests cache behavior
  # ------------------------------------------------------------------
  describe "Cache Management", :provider_single do
    TestEnvironment.providers_for_test(TEST_CONFIG).each do |provider|
      context "when using #{provider} provider" do
        # Run one initial build per provider, shared across all cache tests.
        # Each test may run additional builds to verify cache behavior.
        before(:all) do
          @provider = provider
          skip "#{provider} provider is not available (start Docker services)" unless provider_available_for_test?(@provider)
          @site_dir = create_test_dir("provider-cache-#{@provider}")
          @images = test_images_for_provider(@provider)
          scaffold_provider_test_site(@site_dir, @provider, @images)
          # Initial build — shared by all tests in this context
          build_provider_test_site(@site_dir, @provider)
        end

        after(:all) do
          FileUtils.rm_rf(@site_dir) if @site_dir
        end

        it "updates cache when images change" do
          initial_cache = manifest_data_for(@site_dir).fetch("images", {})
          initial_count = initial_cache.keys.length

          sleep 1

          first_image = @images.first
          site_config = TEST_CONFIG.dup
          site_config["destination"] = File.join(@site_dir, "_site")
          site_config["source"] = @site_dir
          mock_site = MockSite.new(site_config)
          config = JekyllImgFlow::Config.new(mock_site)

          image_path = File.join(@site_dir, config.originals, first_image)
          FileUtils.touch(image_path)

          build_provider_test_site(@site_dir, @provider)
          updated_cache = manifest_data_for(@site_dir).fetch("images", {})
          updated_count = updated_cache.keys.length

          expect(updated_count).to eq(initial_count)
        end

        it "preserves cache for unchanged images" do
          initial_cache = manifest_data_for(@site_dir).fetch("images", {})

          build_provider_test_site(@site_dir, @provider)
          final_cache = manifest_data_for(@site_dir).fetch("images", {})

          expect(final_cache.keys.sort).to eq(initial_cache.keys.sort)
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # Manifest Provider Changes — isolated site with two providers
  # ------------------------------------------------------------------
  describe "Manifest Provider Changes", :provider_change do
    before do
      @change_providers = TestEnvironment::CLI_PROVIDERS.select do |provider|
        provider_available_for_test?(provider)
      end
      skip "At least two CLI providers are required" if @change_providers.length < 2

      @first_provider, @second_provider = @change_providers.first(2)
      @site_dir = create_test_dir("manifest-provider-change")
      scaffold_provider_test_site(
        @site_dir,
        @first_provider,
        TestPictures.get(:default),
        sizes: { "sm" => 400 },
        formats: %w[webp]
      )
      build_provider_test_site(@site_dir, @first_provider)
    end

    after do
      FileUtils.rm_rf(@site_dir) if @site_dir
    end

    it "invalidates and regenerates the manifest when the provider changes" do
      initial_manifest = manifest_data_for(@site_dir)
      expect(initial_manifest["provider"]).to eq(@first_provider)

      config_path = File.join(@site_dir, "_config.yml")
      site_config = YAML.load_file(config_path)
      site_config["imgflow"]["backend_priority"] = [@second_provider]
      site_config["url"] = TestEnvironment.site_url(provider: @second_provider)
      File.write(config_path, site_config.to_yaml)

      build_provider_test_site(@site_dir, @second_provider)
      updated_manifest = manifest_data_for(@site_dir)

      expect(updated_manifest["provider"]).to eq(@second_provider)
      expect(updated_manifest.fetch("images")).not_to be_empty
      updated_manifest.fetch("images").each_value do |image_data|
        image_data.fetch("versions").fetch("default").each do |version|
          expect(version["provider"]).to eq(@second_provider)
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # Error Handling — provider-independent
  # ------------------------------------------------------------------
  describe "Error Handling", :provider_error do
    let(:test_site_dir) { create_test_dir("provider-error-test") }

    before do
      # Use a small subset of images (no SVG) to keep error tests fast.
      # Error handling tests don't need real image processing — they test
      # failure paths. Using all images (including SVG) with ImageMagick
      # would make these tests extremely slow (17+ minutes).
      test_images = TestPictures.get(:all).reject { |img| File.extname(img) == ".svg" }.first(3)
      create_test_jekyll_site(test_site_dir, :imgflow_only, {
                                test_images: test_images,
                                title: "Error Handling Test"
                              })
    end

    after do
      FileUtils.rm_rf(test_site_dir)
    end

    it "handles missing images gracefully" do
      page_content = <<~MARKDOWN
        ---
        layout: default
        ---

        # Test with Missing Image

        {% imgflow nonexistent-image.jpg width=800 %}
      MARKDOWN

      File.write(File.join(test_site_dir, "missing-image.md"), page_content)

      provider = TestEnvironment.providers_for_test(TEST_CONFIG).first
      expect { build_provider_test_site(test_site_dir, provider, allow_failure: true) }
        .not_to raise_error
      expect(File.exist?(File.join(test_site_dir, "_site"))).to be true
    end

    it "handles provider failures gracefully" do
      scaffold_provider_test_site(test_site_dir, "nonexistent_provider", TestPictures.get(:all))
      expect do
        build_provider_test_site(test_site_dir, "nonexistent_provider", allow_failure: true)
      end.not_to raise_error
    end
  end

  # ------------------------------------------------------------------
  # Provider Output Comparison — needs all providers in one process.
  # Skipped when IMGFLOW_TEST_PROVIDER is set (single-provider mode),
  # since comparing requires multiple providers. Run separately without
  # the env var to exercise this: rake parallel:slow runs it in process 7.
  # ------------------------------------------------------------------
  describe "Provider Output Comparison", :provider_cross do
    before(:all) do
      skip "Cross-provider comparison skipped in single-provider mode" if ENV["IMGFLOW_TEST_PROVIDER"]

      @provider_outputs = {}
      TestEnvironment.providers_for_test(TEST_CONFIG).each do |provider|
        next unless provider_available_for_test?(provider)

        site_dir = create_test_dir("provider-compare-#{provider}")
        images = test_images_for_provider(provider, set: :default)
        scaffold_provider_test_site(site_dir, provider, images,
                                    sizes: { "sm" => 400 }, formats: %w[webp jpg])
        build_provider_test_site(site_dir, provider)

        files = optimized_files_for(site_dir)
        @provider_outputs[provider] = {
          files: files.map { |file| File.basename(file) },
          count: files.length,
          site_dir: site_dir
        }
      end
    end

    let(:provider_outputs) { @provider_outputs || {} }

    after(:all) do
      (@provider_outputs || {}).each_value { |data| FileUtils.rm_rf(data[:site_dir]) }
    end

    it "produces consistent filename patterns across providers" do
      reference_provider, reference_data = provider_outputs.first
      skip "No providers available for comparison" unless reference_data

      reference_filenames = reference_data[:files]

      provider_outputs.each do |provider, data|
        next if provider == reference_provider

        expect(data[:count]).to eq(reference_filenames.length),
                                "Provider #{provider} produced #{data[:count]} files, expected #{reference_filenames.length}"

        reference_bases = reference_filenames.map { |f| f.gsub(/-[a-f0-9]{9}/, "-HASH") }
        provider_bases = data[:files].map { |f| f.gsub(/-[a-f0-9]{9}/, "-HASH") }

        expect(provider_bases.sort).to eq(reference_bases.sort),
                                       "Provider #{provider} produced different base filename patterns"
      end
    end

    it "generates valid JPT hashes for all providers" do
      skip "No providers available" if provider_outputs.empty?

      provider_outputs.each_value do |data|
        validate_jpt_hash_patterns(data[:files])
      end
    end
  end

  # ------------------------------------------------------------------
  # Performance — one build per provider, measured
  # ------------------------------------------------------------------
  describe "Performance", :provider_performance do
    TestEnvironment.providers_for_test(TEST_CONFIG).each do |provider|
      it "processes images efficiently with #{provider}" do
        skip "#{provider} provider is not available (start Docker services)" unless provider_available_for_test?(provider)

        site_dir = create_test_dir("provider-perf-#{provider}")
        images = test_images_for_provider(provider, set: :default)
        scaffold_provider_test_site(site_dir, provider, images)

        start_time = Time.now
        build_provider_test_site(site_dir, provider)
        end_time = Time.now

        processing_time = end_time - start_time
        files = optimized_files_for(site_dir)

        FileUtils.rm_rf(site_dir)

        expect(processing_time).to be < 60 # 60 seconds max
        expect(files.length).to be > 0
      end
    end
  end
end
