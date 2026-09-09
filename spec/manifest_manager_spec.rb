# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::ManifestManager, :unit do
  # Use TestPictures for standardized test data
  let(:test_site_dir) { create_test_dir("manifest_manager") }
  let(:test_images) { TestPictures.get(:default) }
  let(:test_image_name) { test_images.first }
  let(:manifest_manager) { described_class.new(@site) }
  let(:manifest_path) { manifest_manager.manifest_path }
  let(:filename_generator) { JekyllImgFlow::FilenameGenerator.new }
  let(:path_resolver) { JekyllImgFlow::PathResolver.new(@config) }

  before(:all) do
    # Create one real site as foundation for manifest testing
    test_base_dir = File.join(File.expand_path("../..", __dir__), "tmp", "tests")
    FileUtils.mkdir_p(test_base_dir)
    @test_site_dir = File.join(test_base_dir, "manifest_manager_real")

    # Only create if doesn't exist (reuse across test runs)
    unless Dir.exist?(@test_site_dir)
      create_test_jekyll_site(@test_site_dir, :imgflow_only, {
                                test_images: TestPictures.get(:default),
                                title: "Manifest Manager Test"
                              })
    end

    # Create site and config objects for tests
    site_config = TEST_CONFIG.dup
    site_config["destination"] = File.join(@test_site_dir, "_site")
    site_config["source"] = @test_site_dir
    @site = Jekyll::Site.new(Jekyll.configuration(site_config))
    @config = JekyllImgFlow::Config.new(@site)
  end

  before do
    FileUtils.mkdir_p(File.dirname(manifest_path))
  end

  describe "#initialize" do
    it "initializes with site" do
      expect(manifest_manager).to be_a(described_class)
      expect(manifest_manager.instance_variable_get(:@site)).to eq(@site)
    end

    it "stores the manifest in the configured cache directory" do
      expected = File.join(@site.source, @config.cache_dir, "imgflow-manifest.json")
      expect(manifest_path).to eq(expected)
    end

    it "loads existing manifest if present" do
      manifest_data = {
        "test.jpg" => {
          "versions" => {
            "default" => [],
            "specialized" => []
          }
        }
      }
      File.write(manifest_path, JSON.pretty_generate(manifest_data))

      manager = described_class.new(@site)
      manifest = manager.instance_variable_get(:@manifest)

      expect(manifest).to have_key("test.jpg")
      expect(manifest["test.jpg"]["versions"]).to have_key("default")
      expect(manifest["test.jpg"]["versions"]).to have_key("specialized")
    end

    it "creates empty manifest if none exists" do
      # Delete manifest files to ensure clean state
      FileUtils.rm_f(manifest_path)
      FileUtils.rm_f(File.join(@site.source, "assets/images/imgflow-manifest.json"))
      FileUtils.rm_f(File.join(@site.dest, "assets/images/imgflow-manifest.json"))

      # Create a fresh manifest manager
      fresh_manager = described_class.new(@site)
      manifest = fresh_manager.instance_variable_get(:@manifest)

      expect(manifest).to be_a(Hash)
      expect(manifest).to eq({})
    end

    it "migrates a legacy source manifest into the configured cache" do
      FileUtils.rm_f(manifest_path)
      legacy_path = File.join(@site.source, "assets/images/imgflow-manifest.json")
      legacy_data = {
        "provider" => manifest_manager.current_provider,
        "images" => { "legacy.jpg" => { "versions" => { "default" => [] } } }
      }
      FileUtils.mkdir_p(File.dirname(legacy_path))
      File.write(legacy_path, JSON.pretty_generate(legacy_data))

      migrated = described_class.new(@site)
      migrated.save

      expect(migrated.get_versions("legacy.jpg")).to eq({ "default" => [] })
      expect(File.exist?(manifest_path)).to be true
      expect(File.exist?(legacy_path)).to be false
    end
  end

  describe "#register_version" do
    let(:original_name) { test_image_name }
    let(:operations) { { width: 800, format: "webp", quality: 85 } }
    let(:output_path) do
      filename = filename_generator.generate_filename(original_name, operations)
      File.join(@site.dest, path_resolver.resolve_output_path(filename))
    end
    let(:version_type) { :default }
    let(:page_path) { "blog/post.html" }

    it "registers a new image version" do
      manifest_manager.register_version(
        original_name,
        output_path,
        operations,
        version_type,
        page_path
      )

      versions = manifest_manager.get_versions(original_name)
      expect(versions["default"]).not_to be_empty
    end

    it "tracks page usage for specialized versions" do
      manifest_manager.register_version(
        original_name,
        output_path,
        operations,
        :specialized,
        page_path
      )

      versions = manifest_manager.get_versions(original_name)
      specialized = versions["specialized"].first

      expect(specialized["used_on"]).to include(page_path)
    end

    it "adds page to existing version if already registered" do
      manifest_manager.register_version(
        original_name,
        output_path,
        operations,
        :specialized,
        "page1.html"
      )

      manifest_manager.register_version(
        original_name,
        output_path,
        operations,
        :specialized,
        "page2.html"
      )

      versions = manifest_manager.get_versions(original_name)
      specialized = versions["specialized"].first

      expect(specialized["used_on"]).to include("page1.html", "page2.html")
    end

    it "stores creation timestamp" do
      manifest_manager.register_version(
        original_name,
        output_path,
        operations,
        version_type,
        page_path
      )

      versions = manifest_manager.get_versions(original_name)
      version = versions["default"].first

      expect(version["created_at"]).to be_a(Integer)
      expect(version["created_at"]).to be <= Time.now.to_i
    end
  end

  describe "#get_versions" do
    let(:original_name) { test_image_name }

    it "returns versions for an image" do
      test_ops = { width: 800, format: "webp", quality: 85 }
      test_filename = filename_generator.generate_filename(original_name, test_ops)
      test_path = File.join(@site.dest, path_resolver.resolve_output_path(test_filename))

      manifest_manager.register_version(
        original_name,
        test_path,
        test_ops,
        :default,
        nil
      )

      versions = manifest_manager.get_versions(original_name)

      expect(versions).to have_key("default")
      expect(versions).to have_key("specialized")
    end

    it "returns empty structure for unknown image" do
      versions = manifest_manager.get_versions("unknown.jpg")

      expect(versions).to eq({ "default" => [], "specialized" => [] })
    end
  end

  describe "#versions?" do
    let(:original_name) { test_image_name }

    it "returns true when image has versions" do
      test_ops = { width: 800, format: "webp", quality: 85 }
      test_filename = filename_generator.generate_filename(original_name, test_ops)
      test_path = File.join(@site.dest, path_resolver.resolve_output_path(test_filename))

      manifest_manager.register_version(
        original_name,
        test_path,
        test_ops,
        :default,
        nil
      )

      expect(manifest_manager.versions?(original_name)).to be true
    end

    it "returns false when image has no versions" do
      expect(manifest_manager.versions?("unknown.jpg")).to be false
    end
  end

  describe "#version_exists?" do
    let(:original_name) { test_image_name }
    let(:operations) { { width: 800, format: "webp", quality: 85 } }

    it "returns true when exact version exists" do
      test_filename = filename_generator.generate_filename(original_name, operations)
      test_path = File.join(@site.dest, path_resolver.resolve_output_path(test_filename))

      manifest_manager.register_version(
        original_name,
        test_path,
        operations,
        :default,
        nil
      )

      expect(manifest_manager.version_exists?(original_name, operations, :default)).to be true
    end

    it "returns false when version doesn't exist" do
      expect(manifest_manager.version_exists?(original_name, operations, :default)).to be false
    end

    it "returns false when the source digest changed" do
      manifest_manager.register_version(
        original_name, "/output.webp", operations, :specialized, "/page.md", "old-digest"
      )

      expect(manifest_manager.version_exists?(
               original_name, operations, :specialized, "new-digest"
             )).to be false
      expect(manifest_manager.version_exists?(
               original_name, operations, :specialized, "old-digest"
             )).to be true
    end

    it "distinguishes between default and specialized versions" do
      test_filename = filename_generator.generate_filename(original_name, operations)
      test_path = File.join(@site.dest, path_resolver.resolve_output_path(test_filename))

      manifest_manager.register_version(
        original_name,
        test_path,
        operations,
        :default,
        nil
      )

      expect(manifest_manager.version_exists?(original_name, operations, :default)).to be true
      expect(manifest_manager.version_exists?(original_name, operations,
                                              :specialized)).to be false
    end

    it "matches nested symbol operations after JSON persistence" do
      nested_operations = { width: 800, crop: { position: :center } }
      manifest_manager.register_version(
        original_name, "/output.webp", nested_operations, :specialized, "/page.md"
      )
      manifest_manager.save

      reloaded = described_class.new(@site)
      reloaded.register_version(
        original_name, "/output.webp", nested_operations, :specialized, "/page.md"
      )

      versions = reloaded.get_versions(original_name)["specialized"]
      matches = versions.select do |version|
        reloaded.same_operations?(version["operations"], nested_operations)
      end
      expect(matches.length).to eq(1)
    end
  end

  describe "#get_version_output" do
    let(:original_name) { test_image_name }
    let(:operations) { { width: 800, format: "webp", quality: 85 } }
    let(:output_path) do
      filename = filename_generator.generate_filename(original_name, operations)
      File.join(@site.dest, path_resolver.resolve_output_path(filename))
    end

    it "returns output path for existing version" do
      manifest_manager.register_version(
        original_name,
        output_path,
        operations,
        :default,
        nil
      )

      result = manifest_manager.get_version_output(original_name, operations, :default)

      expect(result).to eq(output_path)
    end

    it "returns nil for non-existent version" do
      result = manifest_manager.get_version_output(original_name, operations, :default)

      expect(result).to be_nil
    end
  end

  describe "#cleanup_orphans" do
    let(:original_name) { test_image_name }

    before do
      # Create some test files using FilenameGenerator naming with TestPictures
      filename_generator = JekyllImgFlow::FilenameGenerator.new
      path_resolver = JekyllImgFlow::PathResolver.new(@config)

      # Orphan file: 800px width, default quality
      orphan_operations = { width: 800, format: "webp", quality: 85 }
      orphan_filename = filename_generator.generate_filename(original_name, orphan_operations)
      @orphan_file = path_resolver.resolve_source_output_path(orphan_filename)
      # Manifest stores relative paths (with leading /) — match production behavior
      @orphan_relative = "/#{path_resolver.resolve_relative_output_path(orphan_filename)}"

      # Used file: 800px width + quality 90 (different operations)
      used_operations = { width: 800, quality: 90, format: "webp" }
      used_filename = filename_generator.generate_filename(original_name, used_operations)
      @used_file = path_resolver.resolve_source_output_path(used_filename)
      used_relative = "/#{path_resolver.resolve_relative_output_path(used_filename)}"

      # Ensure directories exist
      FileUtils.mkdir_p(File.dirname(@orphan_file))
      FileUtils.mkdir_p(File.dirname(@used_file))

      FileUtils.touch(@orphan_file)
      FileUtils.touch(@used_file)

      # Register the orphan file with no page usage (nil page_path)
      manifest_manager.register_version(
        original_name,
        @orphan_relative,
        orphan_operations,
        :specialized,
        nil # No page usage = orphan
      )

      # Register the used file with page usage
      manifest_manager.register_version(
        original_name,
        used_relative,
        used_operations,
        :specialized,
        "page.html" # Has page usage = not orphan
      )
    end

    it "deletes orphaned specialized images" do
      cleaned = manifest_manager.cleanup_orphans

      expect(File.exist?(@orphan_file)).to be false
      expect(File.exist?(@used_file)).to be true
      # cleanup_orphans returns the relative path stored in the manifest
      expect(cleaned).to include(@orphan_relative)
    end

    it "does not delete default versions" do
      # Create a default version file (even with no page usage, defaults shouldn't be cleaned)
      default_ops = { width: 1200, format: "webp", quality: 85 }
      default_filename = filename_generator.generate_filename(original_name, default_ops)
      default_file = File.join(@site.dest, path_resolver.resolve_output_path(default_filename))
      FileUtils.mkdir_p(File.dirname(default_file))
      FileUtils.touch(default_file)

      # Register as DEFAULT version with no page usage
      manifest_manager.register_version(
        original_name,
        default_file,
        default_ops,
        :default,
        nil
      )

      # Cleanup should only remove specialized orphans, not defaults
      cleaned = manifest_manager.cleanup_orphans

      # Default file should still exist
      expect(File.exist?(default_file)).to be true
      # Should not be in cleaned list
      expect(cleaned).not_to include(default_file)
    end
  end

  describe "#save" do
    it "saves manifest to disk" do
      test_ops = { width: 800, format: "webp", quality: 85 }
      test_filename = filename_generator.generate_filename(test_image_name, test_ops)
      test_path = File.join(@site.dest, path_resolver.resolve_output_path(test_filename))

      manifest_manager.register_version(
        test_image_name,
        test_path,
        test_ops,
        :default,
        nil
      )

      manifest_manager.save

      expect(File.exist?(manifest_path)).to be true

      saved_data = JSON.parse(File.read(manifest_path))
      expect(saved_data.fetch("images")).to have_key(test_image_name)
      expect(saved_data.fetch("images").fetch(test_image_name)).to have_key("versions")
    end

    it "does not rewrite an unchanged manifest" do
      manifest_manager.save
      initial_mtime = File.mtime(manifest_path)
      sleep 0.02

      manifest_manager.save

      expect(File.mtime(manifest_path)).to eq(initial_mtime)
    end

    it "validates TestPictures filename patterns in manifest" do
      # Clear existing manifest and use fresh manifest manager
      FileUtils.rm_f(manifest_path)
      fresh_manager = described_class.new(@site)

      # Test multiple operations with TestPictures
      test_operations = [
        { width: 400, format: "webp", quality: 85 },  # sm size
        { width: 800, format: "jpg", quality: 85 },   # md size
        { width: 1200, format: "avif", quality: 85 } # lg size
      ]

      test_operations.each do |ops|
        # Generate filename using real FilenameGenerator
        actual_filename = filename_generator.generate_filename(test_image_name, ops)

        # Get TestPictures expected for comparison
        size_name = case ops[:width]
                    when 400 then :sm
                    when 800 then :md
                    when 1200 then :lg
                    end
        expected_filename = TestPictures.expected_filename(test_image_name, size_name, ops[:format])

        # Register version in manifest
        output_path = File.join(@site.dest, path_resolver.resolve_output_path(actual_filename))
        fresh_manager.register_version(
          test_image_name,
          output_path,
          ops,
          :default,
          nil
        )

        # The actual filename should match TestPictures expectation exactly!
        expect(actual_filename).to eq(expected_filename)
      end

      # Save and validate manifest contains all versions
      fresh_manager.save
      expect(File.exist?(manifest_path)).to be true

      saved_data = JSON.parse(File.read(manifest_path))
      images = saved_data.fetch("images")
      expect(images).to have_key(test_image_name)
      expect(images.fetch(test_image_name)["versions"]["default"].length).to eq(3)
    end

    it "creates directory if it doesn't exist" do
      FileUtils.rm_rf(File.dirname(manifest_path))

      manifest_manager.save

      expect(File.exist?(manifest_path)).to be true
    end
  end

  describe "#cleanup_deleted_originals" do
    let(:original_name) { test_image_name }

    it "removes manifest entries and generated files for deleted originals" do
      output = "/#{@config.output}/deleted/out.jpg"
      source_output = File.join(@site.source, output)
      destination_output = File.join(@site.dest, output)
      [source_output, destination_output].each do |path|
        FileUtils.mkdir_p(File.dirname(path))
        FileUtils.touch(path)
      end
      manifest_manager.register_version(original_name, output, { width: 800 }, :default, nil)

      manifest_manager.cleanup_deleted_originals(["nonexistent"])

      expect(manifest_manager.versions?(original_name)).to be false
      expect(File.exist?(source_output)).to be false
      expect(File.exist?(destination_output)).to be false
    end

    it "keeps entries for existing originals" do
      manifest_manager.register_version(original_name, "/tmp/out.jpg",
                                        { width: 800 }, :default, nil)
      manifest_manager.cleanup_deleted_originals([original_name])
      expect(manifest_manager.versions?(original_name)).to be true
    end
  end

  describe "#cleanup_obsolete_defaults" do
    it "removes defaults and files that are no longer configured" do
      kept_operations = { width: 400, format: "webp", quality: 85 }
      obsolete_operations = { width: 800, format: "jpg", quality: 85 }
      kept_output = "/#{@config.output}/kept.webp"
      obsolete_output = "/#{@config.output}/obsolete.jpg"
      obsolete_file = File.join(@site.source, obsolete_output)
      FileUtils.mkdir_p(File.dirname(obsolete_file))
      FileUtils.touch(obsolete_file)
      relative = obsolete_file.delete_prefix("#{@site.source}/")
      @site.static_files << Jekyll::StaticFile.new(
        @site, @site.source, File.dirname(relative), File.basename(relative)
      )
      manifest_manager.register_version(test_image_name, kept_output, kept_operations,
                                        :default, nil)
      manifest_manager.register_version(test_image_name, obsolete_output, obsolete_operations,
                                        :default, nil)

      manifest_manager.cleanup_obsolete_defaults([kept_operations])

      defaults = manifest_manager.get_versions(test_image_name)["default"]
      expect(defaults.length).to eq(1)
      expect(manifest_manager.same_operations?(defaults.first["operations"], kept_operations))
        .to be true
      expect(File.exist?(obsolete_file)).to be false
      expect(@site.static_files.none? { |static_file| static_file.path == obsolete_file }).to be true
    end

    it "deletes obsolete format files when formats config shrinks (avif,webp,png,jpg → avif,png)" do
      # Simulate manifest with all 4 formats at width 400
      formats_before = %w[avif webp png jpg]
      formats_after = %w[avif png]
      expected_operations = formats_after.map do |format|
        { width: 400, format: format, quality: 85 }
      end

      created_files = []
      formats_before.each do |format|
        output = "/#{@config.output}/test-400-#{format}.#{format}"
        file = File.join(@site.source, output)
        FileUtils.mkdir_p(File.dirname(file))
        FileUtils.touch(file)
        created_files << file
        manifest_manager.register_version(test_image_name, output,
                                          { width: 400, format: format, quality: 85 },
                                          :default, nil)
      end

      manifest_manager.cleanup_obsolete_defaults(expected_operations)

      defaults = manifest_manager.get_versions(test_image_name)["default"]
      remaining_formats = defaults.map { |v| v["operations"]["format"] }
      expect(remaining_formats).to contain_exactly("avif", "png")
      # webp and jpg files should be deleted
      expect(File.exist?(created_files.find { |f| f.end_with?(".webp") })).to be false
      expect(File.exist?(created_files.find { |f| f.end_with?(".jpg") })).to be false
      # avif and png files should remain
      expect(File.exist?(created_files.find { |f| f.end_with?(".avif") })).to be true
      expect(File.exist?(created_files.find { |f| f.end_with?(".png") })).to be true
    ensure
      created_files.each { |f| FileUtils.rm_f(f) }
    end

    it "keeps existing formats and does not delete when formats config grows (avif,png → avif,png,jpg)" do
      # Simulate manifest with only 2 formats at width 400
      formats_before = %w[avif png]
      expected_operations = %w[avif png jpg].map do |format|
        { width: 400, format: format, quality: 85 }
      end

      created_files = []
      formats_before.each do |format|
        output = "/#{@config.output}/test-grow-400-#{format}.#{format}"
        file = File.join(@site.source, output)
        FileUtils.mkdir_p(File.dirname(file))
        FileUtils.touch(file)
        created_files << file
        manifest_manager.register_version(test_image_name, output,
                                          { width: 400, format: format, quality: 85 },
                                          :default, nil)
      end

      manifest_manager.cleanup_obsolete_defaults(expected_operations)

      defaults = manifest_manager.get_versions(test_image_name)["default"]
      # Existing formats should remain (new jpg will be generated by needs_processing?)
      remaining_formats = defaults.map { |v| v["operations"]["format"] }
      expect(remaining_formats).to contain_exactly("avif", "png")
      # All existing files should still exist
      created_files.each { |f| expect(File.exist?(f)).to be true }
    ensure
      created_files.each { |f| FileUtils.rm_f(f) }
    end

    it "does not remove specialized versions when cleaning up obsolete defaults" do
      expected_default = { width: 400, format: "avif", quality: 85 }
      obsolete_default = { width: 400, format: "webp", quality: 85 }
      specialized_ops = { width: 300, format: "webp" }

      obsolete_file = File.join(@site.source, @config.output, "obsolete-default.webp")
      specialized_file = File.join(@site.source, @config.output, "specialized.webp")
      [obsolete_file, specialized_file].each do |f|
        FileUtils.mkdir_p(File.dirname(f))
        FileUtils.touch(f)
      end

      manifest_manager.register_version(test_image_name,
                                        obsolete_file.delete_prefix("#{@site.source}/"),
                                        obsolete_default, :default, nil)
      manifest_manager.register_version(test_image_name,
                                        specialized_file.delete_prefix("#{@site.source}/"),
                                        specialized_ops, :specialized, "/page.html")

      manifest_manager.cleanup_obsolete_defaults([expected_default])

      # Obsolete default should be removed
      expect(File.exist?(obsolete_file)).to be false
      # Specialized version should be untouched
      expect(File.exist?(specialized_file)).to be true
      specialized = manifest_manager.get_versions(test_image_name)["specialized"]
      expect(specialized.length).to eq(1)
    ensure
      FileUtils.rm_f([obsolete_file, specialized_file])
    end
  end

  describe "#provider_changed?" do
    it "returns false when no cached provider (new manifest)" do
      FileUtils.rm_f(manifest_path)
      fresh_manager = described_class.new(@site)
      expect(fresh_manager.provider_changed?).to be false
    end

    it "returns false when provider matches cached" do
      manifest_manager.save
      same_manager = described_class.new(@site)
      expect(same_manager.provider_changed?).to be false
    end

    it "returns true when provider changed" do
      manifest_manager.instance_variable_set(:@cached_provider, "old_provider")
      manifest_manager.instance_variable_set(:@current_provider, "new_provider")
      expect(manifest_manager.provider_changed?).to be true
    end
  end

  describe "#handle_provider_change" do
    it "clears manifest and deletes optimized files" do
      # Setup: register a version and create the output file
      test_ops = { width: 800, format: "webp", quality: 85 }
      test_filename = filename_generator.generate_filename(test_image_name, test_ops)
      test_path = path_resolver.resolve_source_output_path(test_filename)
      destination_path = path_resolver.resolve_output_path(test_filename)
      [test_path, destination_path].each do |path|
        FileUtils.mkdir_p(File.dirname(path))
        FileUtils.touch(path)
      end
      manifest_manager.register_version(test_image_name, test_path, test_ops, :default, nil)

      # Simulate provider change by setting cached provider to different value
      manifest_manager.instance_variable_set(:@cached_provider, "old_provider")
      manifest_manager.instance_variable_set(:@current_provider,
                                             manifest_manager.current_provider)

      manifest_manager.handle_provider_change

      # Manifest should be cleared
      expect(manifest_manager.versions?(test_image_name)).to be false
      # Files in optimized dirs should be deleted
      expect(File.exist?(test_path)).to be false
      expect(File.exist?(destination_path)).to be false
    end
  end

  describe "#update_page_usage" do
    let(:original_name) { test_image_name }
    let(:operations) { { width: 800, format: "webp", quality: 85 } }
    let(:output_path) do
      filename = filename_generator.generate_filename(original_name, operations)
      File.join(@site.dest, path_resolver.resolve_output_path(filename))
    end

    it "adds page usage to existing version" do
      manifest_manager.register_version(original_name, output_path, operations,
                                        :specialized, "page1.html")
      manifest_manager.update_page_usage(original_name, operations, :specialized, "page2.html")

      versions = manifest_manager.get_versions(original_name)
      specialized = versions["specialized"].first
      expect(specialized["used_on"]).to include("page1.html", "page2.html")
    end

    it "does nothing when version doesn't exist" do
      manifest_manager.update_page_usage(original_name, operations, :specialized, "page.html")
      expect(manifest_manager.versions?(original_name)).to be false
    end
  end

  describe "#default_version?" do
    let(:original_name) { test_image_name }
    let(:operations) { { width: 800, format: "webp", quality: 85 } }

    it "returns true when version is registered as default" do
      manifest_manager.register_version(original_name, "/tmp/out.jpg", operations,
                                        :default, nil)
      expect(manifest_manager.default_version?(original_name, operations)).to be true
    end

    it "returns false when version is specialized only" do
      manifest_manager.register_version(original_name, "/tmp/out.jpg", operations,
                                        :specialized, nil)
      expect(manifest_manager.default_version?(original_name, operations)).to be false
    end

    it "returns false for unknown image" do
      expect(manifest_manager.default_version?("unknown.jpg", operations)).to be false
    end
  end

  describe "#find_orphans" do
    let(:original_name) { test_image_name }

    it "finds specialized versions with no page usage" do
      manifest_manager.register_version(original_name, "/tmp/orphan.jpg",
                                        { width: 400 }, :specialized, nil)
      manifest_manager.register_version(original_name, "/tmp/used.jpg",
                                        { width: 800 }, :specialized, "page.html")

      orphans = manifest_manager.find_orphans
      expect(orphans.length).to eq(1)
      expect(orphans.first["output"]).to eq("/tmp/orphan.jpg")
    end

    it "returns empty array when all specialized versions have page usage" do
      manifest_manager.register_version(original_name, "/tmp/used.jpg",
                                        { width: 800 }, :specialized, "page.html")
      expect(manifest_manager.find_orphans).to be_empty
    end
  end

  describe "#reset_page_usage" do
    it "clears specialized usage while preserving default versions" do
      manifest_manager.register_version(test_image_name, "/default.jpg", { width: 400 },
                                        :default, nil)
      manifest_manager.register_version(test_image_name, "/specialized.jpg", { width: 500 },
                                        :specialized, "page.html")

      manifest_manager.reset_page_usage

      versions = manifest_manager.get_versions(test_image_name)
      expect(versions["default"].length).to eq(1)
      expect(versions["specialized"].first["used_on"]).to be_empty
    end
  end

  describe "#remove_page_usage" do
    let(:original_name) { test_image_name }

    it "removes page from all version usage tracking" do
      manifest_manager.register_version(original_name, "/tmp/out1.jpg",
                                        { width: 400 }, :specialized, "page1.html")
      manifest_manager.register_version(original_name, "/tmp/out2.jpg",
                                        { width: 800 }, :specialized, ["page1.html", "page2.html"])

      manifest_manager.remove_page_usage("page1.html")

      versions = manifest_manager.get_versions(original_name)
      versions["specialized"].each do |v|
        expect(v["used_on"]).not_to include("page1.html")
      end
    end

    it "handles non-existent page gracefully" do
      manifest_manager.register_version(original_name, "/tmp/out.jpg",
                                        { width: 800 }, :specialized, "page.html")
      result = manifest_manager.remove_page_usage("nonexistent.html")
      expect(result).to be_a(Hash)
    end
  end

  describe "#register_version with file_digest and provider" do
    let(:original_name) { test_image_name }
    let(:operations) { { width: 800, format: "webp" } }

    it "stores file_digest when provided" do
      digest = "abc123sha256"
      manifest_manager.register_version(original_name, "/tmp/out.jpg", operations,
                                        :default, nil, digest)
      data = manifest_manager.instance_variable_get(:@manifest)
      expect(data[original_name]["file_digest"]).to eq(digest)
      version = data.dig(original_name, "versions", "default").first
      expect(version["file_digest"]).to eq(digest)
    end

    it "updates file_digest when provided on subsequent calls" do
      manifest_manager.register_version(original_name, "/tmp/out.jpg", operations,
                                        :default, nil, "old_digest")
      manifest_manager.register_version(original_name, "/tmp/out2.jpg",
                                        { width: 400 }, :default, nil, "new_digest")
      data = manifest_manager.instance_variable_get(:@manifest)
      expect(data[original_name]["file_digest"]).to eq("new_digest")
    end

    it "stores provider when provided" do
      manifest_manager.register_version(original_name, "/tmp/out.jpg", operations,
                                        :default, nil, nil, "sharp")
      versions = manifest_manager.get_versions(original_name)
      expect(versions["default"].first["provider"]).to eq("sharp")
    end

    it "updates provider on existing version when provided" do
      manifest_manager.register_version(original_name, "/tmp/out.jpg", operations,
                                        :default, nil, nil, "sharp")
      manifest_manager.register_version(original_name, "/tmp/out.jpg", operations,
                                        :default, nil, nil, "imagemagick")
      versions = manifest_manager.get_versions(original_name)
      expect(versions["default"].first["provider"]).to eq("imagemagick")
    end

    it "handles array page_paths" do
      manifest_manager.register_version(original_name, "/tmp/out.jpg", operations,
                                        :specialized, ["page1.html", "page2.html"])
      versions = manifest_manager.get_versions(original_name)
      expect(versions["specialized"].first["used_on"]).to include("page1.html", "page2.html")
    end
  end

  describe "#load_manifest with old format" do
    it "loads old format manifest (without images wrapper)" do
      old_format = { "test.jpg" => { "versions" => { "default" => [] } } }
      File.write(manifest_path, JSON.pretty_generate(old_format))

      manager = described_class.new(@site)
      manifest = manager.instance_variable_get(:@manifest)
      expect(manifest).to have_key("test.jpg")
      cached = manager.instance_variable_get(:@cached_provider)
      expect(cached).to be_nil
    end
  end

  describe "legacy manifest migration (v0.1.10 → v0.1.11)" do
    it "clears entries without file_digest so they get re-registered" do
      # Simulate a v0.1.10 manifest: operations have no format/quality,
      # no file_digest on versions
      legacy = {
        "provider" => "sharp",
        "images" => {
          "test.jpg" => {
            "versions" => {
              "default" => [{
                "output" => "/assets/images/optimized/test-400-abc123.webp",
                "operations" => { "width" => 400 },
                "type" => "default",
                "used_on" => [],
                "created_at" => 1_700_000_000,
                "provider" => "sharp"
              }],
              "specialized" => []
            }
          }
        }
      }
      File.write(manifest_path, JSON.pretty_generate(legacy))

      manager = described_class.new(@site)
      manifest = manager.instance_variable_get(:@manifest)

      # Legacy entries should be cleared
      expect(manifest).to be_empty
    end

    it "clears entries where operations lack format key" do
      legacy = {
        "provider" => "sharp",
        "images" => {
          "photo.jpg" => {
            "versions" => {
              "default" => [{
                "output" => "/assets/images/optimized/photo-800-def456.jpg",
                "operations" => { "width" => 800 },
                "type" => "default",
                "used_on" => [],
                "created_at" => 1_700_000_000,
                "file_digest" => "abc123",
                "provider" => "sharp"
              }],
              "specialized" => []
            }
          }
        }
      }
      File.write(manifest_path, JSON.pretty_generate(legacy))

      manager = described_class.new(@site)
      manifest = manager.instance_variable_get(:@manifest)

      # Has file_digest but operations lack format → still legacy
      expect(manifest).to be_empty
    end

    it "preserves entries that already have file_digest and format" do
      modern = {
        "provider" => "sharp",
        "images" => {
          "test.jpg" => {
            "versions" => {
              "default" => [{
                "output" => "/assets/images/optimized/test-400-abc123.webp",
                "operations" => { "width" => 400, "format" => "webp", "quality" => 85 },
                "type" => "default",
                "used_on" => [],
                "created_at" => 1_700_000_000,
                "file_digest" => "sha256hash",
                "provider" => "sharp"
              }],
              "specialized" => []
            }
          }
        }
      }
      File.write(manifest_path, JSON.pretty_generate(modern))

      manager = described_class.new(@site)
      manifest = manager.instance_variable_get(:@manifest)

      expect(manifest).to have_key("test.jpg")
      versions = manifest["test.jpg"]["versions"]["default"]
      expect(versions.length).to eq(1)
      expect(versions.first["file_digest"]).to eq("sha256hash")
    end
  end
end
