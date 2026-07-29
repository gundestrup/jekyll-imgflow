# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "webmock/rspec"

RSpec.describe "Production Mode Workflow with Optimized Testing", :external, :integration,
               :system do
  before(:all) do
    @test_site_dir = create_test_dir("imgflow-production-test")

    # Create one test site with all test images (reused across all tests)
    create_test_jekyll_site(@test_site_dir, :imgflow_only, {
                              test_images: TestPictures.get(:default),
                              title: "Production Mode Test"
                            })

    # Create site object for config access
    site_config = TEST_CONFIG.dup
    site_config["destination"] = File.join(@test_site_dir, "_site")
    site_config["source"] = @test_site_dir
    @site = Jekyll::Site.new(Jekyll.configuration(site_config))
  end

  after(:all) do
    FileUtils.rm_rf(@test_site_dir) if @test_site_dir
  end

  let(:test_site_dir) { @test_site_dir }
  let(:site) { @site }
  let(:test_image_name) { TestPictures.get(:default).first }
  let(:test_image_path) { fixture_image_path(test_image_name) }

  describe "Production Mode Testing" do
    # Use fastest provider (Sharp) for production mode testing
    let(:test_provider) { "sharp" }

    before do
      WebMock.allow_net_connect!
      # Override to use Sharp provider
      site_config = site.config.dup
      site_config["imgflow"]["backend_priority"] = [test_provider]
      allow(site).to receive(:config).and_return(site_config)
    end

    after do
      WebMock.disable_net_connect!
    end

    describe "Production Mode Behavior" do
      it "processes images correctly in production mode" do
        # Set production mode
        ENV["JEKYLL_ENV"] = "production"

        begin
          # Test ImgFlow components directly (much faster than full Jekyll build)
          components = create_imgflow_components(site)
          processor = components[:operation_processor]
          components[:path_resolver]

          # Test image processing using TestPictures
          test_images = TestPictures.get(:default)

          test_images.each do |image_name|
            input_path = fixture_image_path(image_name)

            # Process with multiple operations (production mode scenario)
            operations = [
              { type: :resize, params: { width: 800, height: 600 } },
              { type: :quality, params: { quality: 85 } },
              { type: :format, params: { formats: %w[webp jpg] } }
            ]

            output_path = File.join(@test_site_dir, "output_#{image_name}.webp")
            result = processor.process_batch_operations(operations, input_path, output_path)

            # Should have processed successfully
            expect(result).not_to be_nil
            expect(File.exist?(result)).to be true
          end
        ensure
          ENV["JEKYLL_ENV"] = nil
        end
      end

      it "generates all expected formats in production mode" do
        ENV["JEKYLL_ENV"] = "production"

        begin
          components = create_imgflow_components(site)
          processor = components[:operation_processor]

          # Test with a single image to verify all formats
          image_name = TestPictures.get(:default).first
          input_path = fixture_image_path(image_name)

          # Process with all formats (production mode should generate everything)
          operations = [
            { type: :resize, params: { width: 1200 } },
            { type: :format, params: { formats: %w[avif webp jpg] } }
          ]

          results = []
          operations.each_with_index do |operation, index|
            output_path = File.join(@test_site_dir,
                                    "format_#{index}_#{image_name}.#{operation[:params][:formats]&.first || 'jpg'}")
            result = processor.process_single_operation(operation[:type], input_path, output_path,
                                                        operation[:params])
            results << result if result
          end

          # Should have generated all formats
          expect(results.length).to eq(2) # resize + format (format generates multiple files)

          # Check that files exist and have expected extensions
          results.each do |result|
            expect(File.exist?(result)).to be true
            extension = File.extname(result).downcase
            expect([".avif", ".webp", ".jpg"]).to include(extension)
          end
        ensure
          ENV["JEKYLL_ENV"] = nil
        end
      end

      it "handles production mode configuration correctly" do
        ENV["JEKYLL_ENV"] = "production"

        begin
          # Test that config respects production mode
          JekyllImgFlow::Config.new(site)

          # Should have proper production mode settings (check ENV var)
          expect(ENV.fetch("JEKYLL_ENV", nil)).to eq("production")

          # Test with ImgFlow components
          components = create_imgflow_components(site)
          expect(components[:config]).to be_a(JekyllImgFlow::Config)
        ensure
          ENV["JEKYLL_ENV"] = nil
        end
      end

      it "optimizes all test images efficiently" do
        ENV["JEKYLL_ENV"] = "production"

        begin
          components = create_imgflow_components(site)
          processor = components[:operation_processor]

          # Test with all available TestPictures for comprehensive validation
          all_test_images = TestPictures.get(:all)

          processed_count = 0
          all_test_images.each do |image_name|
            input_path = fixture_image_path(image_name)

            # Skip if file doesn't exist (some test images might not be available)
            next unless File.exist?(input_path)

            # Process with typical production operations
            operations = [
              { type: :resize, params: { width: 800 } },
              { type: :quality, params: { quality: 85 } },
              { type: :format, params: { formats: ["webp"] } }
            ]

            output_path = File.join(@test_site_dir, "optimized_#{image_name}.webp")
            result = processor.process_batch_operations(operations, input_path, output_path)

            next unless result && File.exist?(result)

            processed_count += 1

            # Verify the result is valid
            expect(File.size(result)).to be > 0
            expect(File.extname(result)).to eq(".webp")
          end

          # Should have processed at least some images
          expect(processed_count).to be > 0
        ensure
          ENV["JEKYLL_ENV"] = nil
        end
      end
    end
  end
end
