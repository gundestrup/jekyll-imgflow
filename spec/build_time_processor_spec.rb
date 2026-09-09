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

  def current_default_versions(processor, image_path)
    config = processor.instance_variable_get(:@config)
    registry = processor.instance_variable_get(:@registry)
    resolver = processor.instance_variable_get(:@path_resolver)
    generator = JekyllImgFlow::FilenameGenerator.new
    provider = registry.current_provider.class.provider_name
    file_digest = generator.file_digest(image_path)

    config.sizes.each_value.flat_map do |width|
      config.formats.map do |format|
        operations = { width: width, format: format, quality: config.quality }
        filename = generator.generate_filename(image_path, operations)
        output_path = resolver.resolve_source_output_path(filename)
        FileUtils.mkdir_p(File.dirname(output_path))
        FileUtils.touch(output_path, mtime: File.mtime(image_path) + 1)
        {
          "operations" => operations,
          "output" => output_path.delete_prefix(site.source),
          "file_digest" => file_digest,
          "provider" => provider
        }
      end
    end
  end

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

    it "exposes ProcessingStats via site.imgflow_components" do
      components = site.imgflow_components
      expect(components).to have_key(:stats)
      expect(components[:stats]).to be_a(JekyllImgFlow::ProcessingStats)
    end

    it "exposes the same stats instance as the operation processor" do
      op = processor.instance_variable_get(:@operation_processor)
      expect(site.imgflow_components[:stats]).to eq(op.stats)
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

    it "saves manifest after processing and cleans up deleted originals" do
      components = get_processor_components(processor)

      # OperationProcessor#process_operation registers versions internally.
      # BuildTimeProcessor's responsibility is to save the manifest after
      # processing is complete.
      allow(components[:manifest]).to receive(:save)
      allow(components[:manifest]).to receive(:cleanup_deleted_originals)
      allow(components[:manifest]).to receive(:cleanup_obsolete_defaults)
      allow(components[:manifest]).to receive(:reset_page_usage)

      processor.process_changed_images

      expect(components[:manifest]).to have_received(:save)
      expect(components[:manifest]).to have_received(:cleanup_deleted_originals)
      expect(components[:manifest]).to have_received(:cleanup_obsolete_defaults)
      expect(components[:manifest]).to have_received(:reset_page_usage)
    end

    it "records skipped existing outputs as cache hits" do
      components = get_processor_components(processor)
      task = JekyllImgFlow::BatchManager.build_default_tasks(
        test_images.first, File.join(originals_dir, test_images.first), config, site
      ).first
      allow(components[:manifest]).to receive(:register_version)
      components[:operation_processor].stats.reset

      processor.send(:register_skipped_tasks, [{ status: :skipped, task: task }])

      expect(components[:operation_processor].stats.cache_hits).to eq(1)
    end

    it "registers skipped existing outputs in the manifest" do
      components = get_processor_components(processor)
      task = JekyllImgFlow::BatchManager.build_default_tasks(
        test_images.first, File.join(originals_dir, test_images.first), config, site
      ).first
      completed = [{ status: :skipped, task: task }]
      allow(components[:batch_manager]).to receive(:completed).and_return(completed)
      allow(components[:manifest]).to receive(:register_version)

      processor.process_changed_images

      expect(components[:manifest]).to have_received(:register_version).with(
        task[:original_name], task[:output_path].sub(site.source, ""), task[:params],
        :default, nil, nil, kind_of(String)
      )
    end

    it "keeps animated GIF manifest entries during deleted-original cleanup" do
      animated_name = "ang-head-animation.gif"
      animated_path = File.join(originals_dir, animated_name)
      FileUtils.cp(File.expand_path("fixtures/originals/#{animated_name}", __dir__), animated_path)
      manifest = processor.instance_variable_get(:@manifest)
      manifest.register_version(animated_name, "/animated.gif", { width: 400 }, :specialized, nil)

      processor.process_changed_images

      expect(manifest.versions?(animated_name)).to be true
    ensure
      FileUtils.rm_f(animated_path)
    end

    it "creates output directory structure" do
      # Test that the output directory exists after processing
      processor.process_changed_images

      # Verify output directory exists
      expect(Dir.exist?(output_dir)).to be true
    end

    it "records all current default versions as cache hits" do
      components = get_processor_components(processor)
      image_path = File.join(originals_dir, test_images.first)
      allow(processor).to receive_messages(
        find_original_images: [image_path], needs_processing?: false
      )
      components[:operation_processor].stats.reset

      processor.process_changed_images

      expected = config.sizes.length * config.formats.length
      expect(components[:operation_processor].stats.cache_hits).to eq(expected)
      expect(components[:operation_processor].stats.cache_misses).to eq(0)
    end
  end

  describe "#needs_processing?" do
    let(:image_path) { File.join(originals_dir, test_images.first) }

    it "returns true when image has no versions" do
      result = processor.send(:needs_processing?, image_path)

      expect(result).to be true
    end

    it "returns false when every configured output is up-to-date" do
      manifest = processor.instance_variable_get(:@manifest)
      versions = current_default_versions(processor, image_path)
      allow(manifest).to receive(:get_versions).and_return({ "default" => versions })

      result = processor.send(:needs_processing?, image_path)

      expect(result).to be false
    end

    it "returns true when a configured output is missing" do
      manifest = processor.instance_variable_get(:@manifest)
      versions = current_default_versions(processor, image_path)
      FileUtils.rm_f(File.join(site.source, versions.first["output"]))
      allow(manifest).to receive(:get_versions).and_return({ "default" => versions })

      expect(processor.send(:needs_processing?, image_path)).to be true
    end

    it "returns true when a format is added to config (missing format needs generation)" do
      manifest = processor.instance_variable_get(:@manifest)
      # Simulate manifest with only 2 of 4 formats (avif, webp) — png and jpg missing
      versions = current_default_versions(processor, image_path)
      removed_formats = %w[png jpg]
      reduced_versions = versions.reject { |v| removed_formats.include?(v["operations"][:format]) }
      allow(manifest).to receive(:get_versions).and_return({ "default" => reduced_versions })

      expect(processor.send(:needs_processing?, image_path)).to be true
    end

    it "returns false when formats config shrinks (obsolete formats already cleaned up)" do
      manifest = processor.instance_variable_get(:@manifest)
      # Simulate manifest with only the 2 remaining formats after config changed
      versions = current_default_versions(processor, image_path)
      kept_formats = %w[avif png]
      reduced_versions = versions.select { |v| kept_formats.include?(v["operations"][:format]) }
      # Stub config to only expect avif and png
      reduced_config = double("config", sizes: config.sizes, formats: %w[avif png],
                                        quality: config.quality)
      allow(processor).to receive_messages(
        expected_default_operations: reduced_config.sizes.each_value.flat_map do |width|
          reduced_config.formats.map do |format|
            { width: width, format: format, quality: reduced_config.quality }
          end
        end
      )
      allow(manifest).to receive(:get_versions).and_return({ "default" => reduced_versions })

      expect(processor.send(:needs_processing?, image_path)).to be false
    end

    it "returns true when original bytes change with the same mtime" do
      manifest = processor.instance_variable_get(:@manifest)
      versions = current_default_versions(processor, image_path)
      allow(manifest).to receive(:get_versions).and_return({ "default" => versions })
      original_bytes = File.binread(image_path)
      original_mtime = File.mtime(image_path)
      File.binwrite(image_path, "#{original_bytes}\0")
      FileUtils.touch(image_path, mtime: original_mtime)

      result = processor.send(:needs_processing?, image_path)

      expect(result).to be true
    ensure
      File.binwrite(image_path, original_bytes) if original_bytes
      FileUtils.touch(image_path, mtime: original_mtime) if original_mtime
    end

    it "returns false when only the original mtime changes" do
      manifest = processor.instance_variable_get(:@manifest)
      versions = current_default_versions(processor, image_path)
      allow(manifest).to receive(:get_versions).and_return({ "default" => versions })
      original_mtime = File.mtime(image_path)
      FileUtils.touch(image_path, mtime: Time.now + 60)

      expect(processor.send(:needs_processing?, image_path)).to be false
    ensure
      FileUtils.touch(image_path, mtime: original_mtime) if original_mtime
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
        manifest = processor.instance_variable_get(:@manifest)
        versions = current_default_versions(processor, image_path)
        allow(manifest).to receive(:get_versions).and_return({ "default" => versions })

        result = processor.send(:needs_processing?, image_path)
        expect(result).to be false
      end

      it "returns true when original file content is modified" do
        manifest = processor.instance_variable_get(:@manifest)
        versions = current_default_versions(processor, image_path)
        allow(manifest).to receive(:get_versions).and_return({ "default" => versions })
        original_bytes = File.binread(image_path)
        File.binwrite(image_path, "#{original_bytes}\0")

        result = processor.send(:needs_processing?, image_path)
        expect(result).to be true
      ensure
        File.binwrite(image_path, original_bytes) if original_bytes
      end

      it "handles a missing output path gracefully" do
        manifest = processor.instance_variable_get(:@manifest)
        versions = current_default_versions(processor, image_path)
        versions.first.delete("output")
        allow(manifest).to receive(:get_versions).and_return({ "default" => versions })

        result = processor.send(:needs_processing?, image_path)
        expect(result).to be true
      end

      it "handles provider change detection" do
        manifest = processor.instance_variable_get(:@manifest)
        versions = current_default_versions(processor, image_path)
        versions.each { |version| version["provider"] = "PreviousProvider" }
        allow(manifest).to receive(:get_versions).and_return({ "default" => versions })

        result = processor.send(:needs_processing?, image_path)
        expect(result).to be true
      end

      it "handles non-existent image gracefully" do
        non_existent_path = File.join(originals_dir, "non_existent.jpg")

        result = processor.send(:needs_processing?, non_existent_path)
        expect(result).to be(true).or(be(false))
      end
    end
  end
end
