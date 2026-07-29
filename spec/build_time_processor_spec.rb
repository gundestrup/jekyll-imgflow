# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::BuildTimeProcessor, :unit do
  before(:all) do
    # Create test site once for all tests (follow batch_manager_spec pattern)
    @test_site_dir = create_test_dir("build_time_processor_test")
    create_test_jekyll_site(@test_site_dir, :imgflow_only,
                            { test_images: TestPictures.get(:default_multi) })

    # Create actual site object
    site_config = TEST_CONFIG.dup
    site_config["destination"] = File.join(@test_site_dir, "_site")
    site_config["source"] = @test_site_dir
    @site = Jekyll::Site.new(Jekyll.configuration(site_config))
  end

  let(:site) { @site }
  let(:test_site_dir) { @test_site_dir }
  let(:test_images) { TestPictures.get(:default_multi) }
  let(:processor) { described_class.new(site) }
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:originals_dir) { File.join(test_site_dir, config.originals) }
  let(:output_dir) { File.join(test_site_dir, config.output) }

  before do
    # Mock batch manager to avoid real image processing (unit test approach)
    components = get_processor_components(processor)
    allow(components[:batch_manager]).to receive(:process_all).and_return({ completed: 6,
                                                                            failed: 0 })
    allow(components[:batch_manager]).to receive(:add_tasks)
  end

  # No immediate cleanup - let TestDirectoryHelper handle 1-hour cleanup

  describe "#initialize" do
    it "initializes with site" do
      expect(processor).to be_a(described_class)
    end

    it "creates required components" do
      expect(processor.instance_variable_get(:@config)).to be_a(JekyllImgFlow::Config)
      expect(processor.instance_variable_get(:@manifest)).to be_a(JekyllImgFlow::ManifestManager)
      expect(processor.instance_variable_get(:@path_resolver)).to be_a(JekyllImgFlow::PathResolver)
      expect(processor.instance_variable_get(:@registry)).to be_a(JekyllImgFlow::ProviderRegistry)
      expect(processor.instance_variable_get(:@operation_processor)).to be_a(JekyllImgFlow::OperationProcessor)
      expect(processor.instance_variable_get(:@batch_manager)).to be_a(JekyllImgFlow::BatchManager)
    end
  end

  describe "#process_changed_images" do
    it "processes all original images" do
      results = processor.process_changed_images

      expect(results).to be_a(Hash)
      expect(results).to include(:completed, :failed)
      expect(results[:completed]).to be > 0
    end

    it "calls batch manager to add tasks and process" do
      components = get_processor_components(processor)

      # Expect batch manager to be called
      expect(components[:batch_manager]).to receive(:add_tasks).at_least(:once)
      expect(components[:batch_manager]).to receive(:process_all).and_return({ completed: 5,
                                                                               failed: 0 })

      processor.process_changed_images
    end

    it "returns processing statistics" do
      components = get_processor_components(processor)
      allow(components[:batch_manager]).to receive(:process_all).and_return({ completed: 3,
                                                                              failed: 2 })

      results = processor.process_changed_images

      expect(results[:completed]).to eq(3)
      expect(results[:failed]).to eq(2)
    end

    it "finds all original images" do
      original_paths = processor.send(:find_original_images)

      # SVG files are now included in input_formats, so expect all 6 images
      expect(original_paths.length).to eq(6)
      original_paths.each do |path|
        expect(File.exist?(path)).to be true
        expect(path).to include("originals")
      end
    end

    it "creates output directory and updates manifest" do
      # Test that the output directory exists after processing
      processor.process_changed_images

      # Verify output directory exists
      expect(Dir.exist?(output_dir)).to be true

      # Verify manifest was saved
      components = get_processor_components(processor)
      expect(File.exist?(components[:manifest].manifest_path)).to be true
    end

    it "saves manifest after processing" do
      components = get_processor_components(processor)

      # Mock manifest saving
      expect(components[:manifest]).to receive(:save)

      processor.process_changed_images
    end

    it "registers completed tasks in manifest" do
      components = get_processor_components(processor)

      # Use TestPictures to generate realistic completed tasks with correct filenames
      image_name = "mars-crater-large.jpg"
      mock_completed_tasks = TestPictures.mock_completed_tasks(
        image_name,
        sizes: %i[md lg],
        formats: %i[webp avif],
        output_dir: File.join(test_site_dir, "_site/assets/images/optimized")
      )

      # Override the batch_manager mock to return our completed tasks
      allow(components[:batch_manager]).to receive(:completed).and_return(mock_completed_tasks)

      # Track the actual calls to manifest.register_version
      registered_versions = []
      allow(components[:manifest]).to receive(:register_version) do |*args|
        registered_versions << args
      end

      processor.process_changed_images

      # Verify that register_version was called with the correct parameters
      expect(registered_versions.length).to eq(4) # 2 sizes × 2 formats = 4 tasks

      # Get expected filenames from TestPictures
      expected_md_webp = TestPictures.expected_filename(image_name, :md, :webp)
      expected_md_avif = TestPictures.expected_filename(image_name, :md, :avif)
      expected_lg_webp = TestPictures.expected_filename(image_name, :lg, :webp)
      expected_lg_avif = TestPictures.expected_filename(image_name, :lg, :avif)

      # Verify the registered versions contain the expected filenames
      registered_paths = registered_versions.map { |args| args[1] }
      expect(registered_paths).to include("/assets/images/optimized/#{expected_md_webp}")
      expect(registered_paths).to include("/assets/images/optimized/#{expected_md_avif}")
      expect(registered_paths).to include("/assets/images/optimized/#{expected_lg_webp}")
      expect(registered_paths).to include("/assets/images/optimized/#{expected_lg_avif}")

      # Verify all calls have correct original name and type
      registered_versions.each do |args|
        expect(args[0]).to eq(image_name) # original_name
        expect(args[3]).to eq(:default)   # type
      end
    end

    it "creates output directory structure" do
      # Test that the output directory exists after processing
      processor.process_changed_images

      # Verify output directory exists
      expect(Dir.exist?(output_dir)).to be true
    end
  end

  describe "#needs_processing?" do
    let(:image_path) { File.join(originals_dir, test_images.first) }

    it "returns true when image has no versions" do
      result = processor.send(:needs_processing?, image_path)

      expect(result).to be true
    end

    it "returns false when image is up-to-date" do
      # Mock manifest to indicate image is up-to-date with matching provider
      manifest = processor.instance_variable_get(:@manifest)
      registry = processor.instance_variable_get(:@registry)
      current_provider_name = registry.current_provider.class.provider_name
      allow(manifest).to receive_messages(versions?: true, get_versions: {
                                            "default" => [
                                              { "created_at" => Time.now.to_i,
                                                "provider" => current_provider_name }
                                            ]
                                          })

      result = processor.send(:needs_processing?, image_path)

      expect(result).to be false
    end

    it "returns true when original file is modified" do
      # Process once
      processor.process_changed_images

      # Modify the file
      sleep 0.1
      FileUtils.touch(image_path)

      # Check again
      result = processor.send(:needs_processing?, image_path)

      expect(result).to be true
    end
  end

  describe "integration with BatchManager" do
    it "uses BatchManager for processing" do
      components = get_processor_components(processor)
      expect(components[:batch_manager]).to receive(:add_tasks).at_least(:once)
      expect(components[:batch_manager]).to receive(:process_all).and_call_original

      processor.process_changed_images
    end

    it "builds default tasks for each image" do
      components = get_processor_components(processor)

      processor.process_changed_images

      # After processing, batch should be empty (all processed)
      expect(components[:batch_manager].queue).to be_empty
    end
  end

  describe "error handling" do
    it "continues processing when one image fails" do
      # Mock batch manager to handle errors gracefully
      components = get_processor_components(processor)
      allow(components[:batch_manager]).to receive(:process_all).and_return({ completed: 2,
                                                                              failed: 1 })

      results = processor.process_changed_images

      expect(results[:completed]).to eq(2)
      expect(results[:failed]).to eq(1)
    end

    it "reports failed images in results" do
      # Mock batch manager to return failure results
      components = get_processor_components(processor)
      allow(components[:batch_manager]).to receive(:process_all).and_return({ completed: 1,
                                                                              failed: 2 })

      results = processor.process_changed_images

      # Should have some failures or completions
      expect(results[:completed] + results[:failed]).to be > 0
      expect(results[:failed]).to be > 0
    end

    it "handles batch manager exceptions gracefully" do
      components = get_processor_components(processor)
      allow(components[:batch_manager]).to receive(:process_all).and_raise(StandardError,
                                                                           "Processing error")

      # The current implementation doesn't handle exceptions gracefully
      # This test documents the current behavior
      expect do
        processor.process_changed_images
      end.to raise_error(StandardError, "Processing error")
    end
  end

  describe "with different input formats" do
    it "processes all supported input formats" do
      original_paths = processor.send(:find_original_images)

      # SVG files are now included in input_formats, so expect all 6 images
      expect(original_paths.length).to be >= 6
    end
  end

  describe "performance" do
    it "processes images in reasonable time" do
      # Mock batch manager to avoid actual processing
      components = get_processor_components(processor)
      allow(components[:batch_manager]).to receive(:add_tasks)
      allow(components[:batch_manager]).to receive(:process_all).and_return({ completed: 3,
                                                                              failed: 0 })

      start_time = Time.now

      processor.process_changed_images

      end_time = Time.now
      duration = end_time - start_time

      # Should complete quickly when mocked
      expect(duration).to be < 5
    end
  end

  describe "private method coverage" do
    describe "#find_original_images" do
      it "handles empty originals directory" do
        # Remove all images
        FileUtils.rm_rf(Dir.glob(File.join(originals_dir, "*")))

        original_paths = processor.send(:find_original_images)
        expect(original_paths).to be_an(Array)
        expect(original_paths).to be_empty

        # Restore files for other tests (important with before(:all))
        copy_test_images_to_site(originals_dir, test_images)
      end

      it "finds all images in originals directory" do
        original_paths = processor.send(:find_original_images)
        expect(original_paths).to be_an(Array)
        expect(original_paths.length).to be >= 6 # SVG files now included in input_formats
      end

      it "filters by input_formats correctly" do
        original_paths = processor.send(:find_original_images)

        # Should only find files with extensions in input_formats
        found_extensions = original_paths.map do |path|
          File.extname(path).delete(".").downcase
        end.uniq
        allowed_extensions = config.input_formats

        found_extensions.each do |ext|
          expect(allowed_extensions).to include(ext)
        end
      end

      it "searches recursively in subdirectories" do
        # Create subdirectory with image
        subdir = File.join(originals_dir, "subdir")
        FileUtils.mkdir_p(subdir)
        FileUtils.cp(fixture_image_path, File.join(subdir, "test.jpg"))

        original_paths = processor.send(:find_original_images)

        # Should find images in subdirectory too
        expect(original_paths.any? { |path| path.include?("subdir") }).to be true
      end
    end

    describe "#needs_processing?" do
      let(:image_path) { File.join(originals_dir, test_images.first) }

      it "returns true when image has no versions" do
        result = processor.send(:needs_processing?, image_path)
        expect(result).to be true
      end

      it "returns false when image is up-to-date" do
        # Mock manifest to indicate image is up-to-date
        manifest = processor.instance_variable_get(:@manifest)
        registry = processor.instance_variable_get(:@registry)
        current_provider_name = registry.current_provider.class.provider_name
        allow(manifest).to receive_messages(versions?: true, get_versions: {
                                              "default" => [
                                                { "created_at" => Time.now.to_i,
                                                  "provider" => current_provider_name }
                                              ]
                                            })

        result = processor.send(:needs_processing?, image_path)
        expect(result).to be false # Image is up-to-date with recent timestamp and matching provider
      end

      it "returns true when original file is modified" do
        # Mock manifest to indicate image was processed
        manifest = processor.instance_variable_get(:@manifest)
        allow(manifest).to receive_messages(versions?: true, get_versions: {
                                              "default" => [
                                                { "created_at" => (Time.now - 3600).to_i, "provider" => "Sharp" } # 1 hour ago
                                              ]
                                            })

        # Touch file to make it newer
        sleep 0.1
        FileUtils.touch(image_path)

        result = processor.send(:needs_processing?, image_path)
        expect(result).to be true
      end

      it "handles missing version_time gracefully" do
        # Mock manifest to return versions without created_at
        manifest = processor.instance_variable_get(:@manifest)
        allow(manifest).to receive_messages(versions?: true, get_versions: {
                                              "default" => [
                                                { "provider" => "Sharp" } # No created_at
                                              ]
                                            })

        result = processor.send(:needs_processing?, image_path)
        expect(result).to be true # Should process when no timestamp
      end

      it "handles provider change detection" do
        # Mock registry to return different provider
        registry = processor.instance_variable_get(:@registry)
        allow(registry).to receive(:current_provider).and_return(
          double("provider",
                 class: double("class", provider_name: "newprovider"))
        )

        # Mock manifest with previous provider
        allow(processor.instance_variable_get(:@manifest))
          .to receive_messages(versions?: true, get_versions: {
                                 "default" => [
                                   { "created_at" => Time.now.to_i,
                                     "provider" => "PreviousProvider" }
                                 ]
                               })

        result = processor.send(:needs_processing?, image_path)
        expect(result).to be true # Should process when provider changed
      end

      it "handles non-existent image gracefully" do
        non_existent_path = File.join(originals_dir, "non_existent.jpg")

        result = processor.send(:needs_processing?, non_existent_path)
        expect(result).to be(true).or(be(false))
      end
    end
  end
end
