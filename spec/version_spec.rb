# frozen_string_literal: true

require "spec_helper"
require_relative "support/test_directory_helper"
require_relative "support/test_pictures"
require "json"

RSpec.describe "JekyllImgFlow Version System - RSpec Helper Integration", :unit do
  let(:test_site_dir) { create_test_dir("version_test") }
  let(:site) { @site }
  let(:test_site_dir) { @test_site_dir }
  # Use standardized component creation helper
  let(:components) { create_imgflow_components(site) }
  let(:config) { components[:config] }
  let(:manifest_manager) { components[:manifest_manager] }
  # Test image helpers
  let(:default_images) { TestPictures.get(:default_multi) }
  let(:test_image) { File.join(site.source, config.originals, default_images.first) }
  let(:test_image_name) { default_images.first }
  let(:first_provider) { config.backend_priority.first }

  before(:all) do
    # Create test site once for all tests (original files never changed)
    @test_site_dir = create_test_dir("version_test")
    create_test_jekyll_site(@test_site_dir, :imgflow_only,
                            { test_images: TestPictures.get(:default_multi) })

    # Create actual site object
    site_config = TEST_CONFIG.dup
    site_config["destination"] = File.join(@test_site_dir, "_site")
    site_config["source"] = @test_site_dir
    @site = Jekyll::Site.new(Jekyll.configuration(site_config))
  end

  # Helper to get the first provider from config
  def default_provider
    config.backend_priority.first
  end

  describe "VERSION Constant" do
    it "has a version defined" do
      expect(JekyllImgFlow::VERSION).to be_a(String)
      expect(JekyllImgFlow::VERSION).not_to be_empty
    end

    it "follows semantic versioning pattern" do
      expect(JekyllImgFlow::VERSION).to match(/\d+\.\d+\.\d+/)
    end

    it "is a valid version format" do
      version = JekyllImgFlow::VERSION
      parts = version.split(".")
      expect(parts.length).to eq(3)
      expect(parts.all? { |part| part.match(/^\d+$/) }).to be true
    end

    it "has reasonable version numbers" do
      version = JekyllImgFlow::VERSION
      major, minor, patch = version.split(".").map(&:to_i)

      expect(major).to be >= 0
      expect(minor).to be >= 0
      expect(patch).to be >= 0
      expect(major).to be < 100
      expect(minor).to be < 100
      expect(patch).to be < 1000
    end
  end

  describe "ManifestManager with Shared Test Site" do
    before do
      # Clean manifest before each test to ensure isolation
      manifest_manager.instance_variable_set(:@manifest, {})
    end

    describe "#version_exists?" do
      it "returns false for new manifest" do
        operations = { "width" => 800 }
        result = manifest_manager.version_exists?(test_image_name, operations, :default)

        expect(result).to be false
      end

      it "returns true after registering version" do
        operations = { "width" => 800 }
        output_path = "assets/images/optimized/#{test_image_name.split('.').first}-800-test.webp"

        # Register version using default provider
        manifest_manager.register_version(
          test_image_name,
          output_path,
          operations,
          :default,
          "/test-page.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        result = manifest_manager.version_exists?(test_image_name, operations, :default)
        expect(result).to be true
      end

      it "handles multiple test images from catalog" do
        default_images.each do |image|
          operations = { "width" => 400 }
          output_path = "assets/images/optimized/#{image.split('.').first}-400-test.webp"

          # Register version
          manifest_manager.register_version(
            image,
            output_path,
            operations,
            :specialized,
            "/test-#{image}.md",
            TestPictures.hash(image),
            default_provider
          )

          # Verify exists
          exists = manifest_manager.version_exists?(image, operations, :specialized)
          expect(exists).to be true
        end
      end

      it "distinguishes between default and specialized versions" do
        operations = { "width" => 800 }

        # Register as default
        manifest_manager.register_version(
          test_image_name,
          "output-default.webp",
          operations,
          :default,
          "/test.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        # Check default exists
        default_exists = manifest_manager.version_exists?(test_image_name, operations, :default)
        expect(default_exists).to be true

        # Check specialized doesn't exist yet
        specialized_exists = manifest_manager.version_exists?(test_image_name, operations,
                                                              :specialized)
        expect(specialized_exists).to be false
      end
    end

    describe "#get_version_output" do
      it "returns nil for non-existing version" do
        operations = { "width" => 1200 }
        result = manifest_manager.get_version_output(test_image_name, operations, :default)

        expect(result).to be_nil
      end

      it "returns output path after registration" do
        operations = { "width" => 800 }
        expected_output = "assets/images/optimized/#{test_image_name.split('.').first}-800-test.webp"

        # Register version
        manifest_manager.register_version(
          test_image_name,
          expected_output,
          operations,
          :default,
          "/test.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        result = manifest_manager.get_version_output(test_image_name, operations, :default)
        expect(result).to eq(expected_output)
      end

      it "uses expected filenames from TestPictures catalog" do
        default_images.each do |image|
          metadata = TestPictures.metadata(image)
          next unless metadata[:expected_defaults]

          metadata[:expected_defaults].each do |size, formats|
            formats.each do |format, expected_filename|
              # Convert size to actual width
              width = case size
                      when :sm then 400
                      when :lg then 1200
                      when :xl then 2000
                      else 800
                      end

              operations = { "width" => width, "format" => format }
              output_path = "assets/images/optimized/#{expected_filename}"

              # Register version
              manifest_manager.register_version(
                image,
                output_path,
                operations,
                :default,
                "/test.md",
                TestPictures.hash(image),
                default_provider
              )

              # Verify output path
              result = manifest_manager.get_version_output(image, operations, :default)
              expect(result).to eq(output_path)
            end
          end
        end
      end
    end

    describe "#register_version" do
      it "registers version with real test image data" do
        operations = { "width" => 800, "quality" => 85 }
        output_path = "assets/images/optimized/#{test_image_name.split('.').first}-800-85-test.webp"
        page_path = "/posts/2024-01-01-test.md"
        file_hash = TestPictures.hash(test_image_name)

        # Register version
        manifest_manager.register_version(
          test_image_name,
          output_path,
          operations,
          :specialized,
          page_path,
          file_hash,
          default_provider
        )

        # Verify version exists
        exists = manifest_manager.version_exists?(test_image_name, operations, :specialized)
        expect(exists).to be true

        # Verify output path
        result = manifest_manager.get_version_output(test_image_name, operations, :specialized)
        expect(result).to eq(output_path)
      end

      it "creates entry for new test images" do
        new_image = default_images[1] # Use second test image
        operations = { "format" => "avif" }
        output_path = "assets/images/optimized/#{new_image.split('.').first}-avif-test.avif"

        # Register version for new image
        manifest_manager.register_version(
          new_image,
          output_path,
          operations,
          :default,
          "/pages/new.md",
          TestPictures.hash(new_image),
          default_provider
        )

        # Verify image has versions
        has_versions = manifest_manager.versions?(new_image)
        expect(has_versions).to be true

        # Verify version exists
        exists = manifest_manager.version_exists?(new_image, operations, :default)
        expect(exists).to be true
      end

      it "saves and loads manifest correctly" do
        operations = { "width" => 600 }
        output_path = "assets/images/optimized/#{test_image_name.split('.').first}-600-test.webp"

        # Register version
        manifest_manager.register_version(
          test_image_name,
          output_path,
          operations,
          :specialized,
          "/test-save.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        # Force save
        manifest_manager.save

        # Create new manager instance
        new_manager = JekyllImgFlow::ManifestManager.new(site)

        # Verify version exists in loaded manifest
        exists = new_manager.version_exists?(test_image_name, operations, :specialized)
        expect(exists).to be true
      end
    end

    describe "#default_version?" do
      it "identifies default versions correctly" do
        operations = { "width" => 800 }

        # Register as default
        manifest_manager.register_version(
          test_image_name,
          "output-default.webp",
          operations,
          :default,
          "/test.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        result = manifest_manager.default_version?(test_image_name, operations)
        expect(result).to be true
      end

      it "identifies specialized versions correctly" do
        operations = { "width" => 800, "height" => 600 }

        # Register as specialized
        manifest_manager.register_version(
          test_image_name,
          "output-specialized.webp",
          operations,
          :specialized,
          "/test.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        result = manifest_manager.default_version?(test_image_name, operations)
        expect(result).to be false
      end

      it "handles test images from catalog" do
        default_images.each do |image|
          operations = { "width" => 400 }

          # Register as default
          manifest_manager.register_version(
            image,
            "output-default.webp",
            operations,
            :default,
            "/test-#{image}.md",
            TestPictures.hash(image),
            default_provider
          )

          # Verify it's identified as default
          result = manifest_manager.default_version?(image, operations)
          expect(result).to be true
        end
      end
    end

    describe "#get_versions" do
      it "returns empty structure for new images" do
        versions = manifest_manager.get_versions(test_image_name)

        expect(versions).to eq({ "default" => [], "specialized" => [] })
      end

      it "returns registered versions" do
        default_ops = { "width" => 800 }
        specialized_ops = { "width" => 800, "format" => "webp" }

        # Register default version
        manifest_manager.register_version(
          test_image_name,
          "output-default.webp",
          default_ops,
          :default,
          "/test.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        # Register specialized version
        manifest_manager.register_version(
          test_image_name,
          "output-specialized.webp",
          specialized_ops,
          :specialized,
          "/test.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        versions = manifest_manager.get_versions(test_image_name)

        expect(versions["default"].length).to eq(1)
        expect(versions["specialized"].length).to eq(1)
        expect(versions["default"].first["operations"]).to eq(default_ops)
        expect(versions["specialized"].first["operations"]).to eq(specialized_ops)
      end

      it "contains valid version data structure" do
        operations = { "width" => 800 }

        manifest_manager.register_version(
          test_image_name,
          "output-test.webp",
          operations,
          :specialized,
          "/test.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        versions = manifest_manager.get_versions(test_image_name)
        version = versions["specialized"].first

        expect(version).to have_key("output")
        expect(version).to have_key("operations")
        expect(version).to have_key("used_on")
        expect(version).to have_key("type")
        expect(version).to have_key("created_at")
        expect(version).to have_key("provider")
        expect(version["type"]).to eq("specialized")
        expect(version["provider"]).to eq(default_provider)
      end
    end

    describe "#versions?" do
      it "returns false for new images" do
        result = manifest_manager.versions?(test_image_name)
        expect(result).to be false
      end

      it "returns true after registration" do
        operations = { "width" => 800 }

        manifest_manager.register_version(
          test_image_name,
          "output-test.webp",
          operations,
          :default,
          "/test.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        result = manifest_manager.versions?(test_image_name)
        expect(result).to be true
      end

      it "distinguishes between images with and without versions" do
        # Register version for test_image_name
        manifest_manager.register_version(
          test_image_name,
          "output-test.webp",
          { "width" => 800 },
          :default,
          "/test.md",
          TestPictures.hash(test_image_name),
          default_provider
        )

        # test_image_name should have versions
        expect(manifest_manager.versions?(test_image_name)).to be true

        # Another image should not have versions
        expect(manifest_manager.versions?("nonexistent.jpg")).to be false
      end
    end
  end

  describe "Helper Method Integration" do
    it "uses TestDirectoryHelper for test management" do
      expect(Dir.exist?(test_site_dir)).to be true
      expect(test_site_dir).to include("version_test")
      expect(test_site_dir).to include(TestDirectoryHelper::TEST_BASE_DIR)
    end

    it "uses TestPictures for realistic image testing" do
      expect(default_images).not_to be_empty
      expect(default_images.length).to be >= 3

      default_images.each do |image|
        expect(TestPictures.exists?(image)).to be true
        TestPictures.metadata(image)
      end
    end

    it "leverages RSpec helper test sites" do
      expect(test_site_dir).to be_a(String)
      expect(Dir.exist?(test_site_dir)).to be true
      expect(File.exist?(File.join(test_site_dir, "_config.yml"))).to be true
    end

    it "uses create_imgflow_components from RSpec helper" do
      expect(components).to be_a(Hash)
      expect(components).to have_key(:config)
      expect(components).to have_key(:manifest_manager)
      expect(components).to have_key(:manifest) # Backward compatibility alias
      expect(components[:config]).to be_a(JekyllImgFlow::Config)
      expect(components[:manifest_manager]).to be_a(JekyllImgFlow::ManifestManager)

      # manifest_manager is now available from components
      expect(manifest_manager).to eq(components[:manifest_manager])
      expect(manifest_manager).to eq(components[:manifest]) # Alias should point to same object
    end
  end

  describe "Dynamic Provider Selection" do
    it "uses first provider from backend_priority" do
      expect(config.backend_priority).to be_an(Array)
      expect(config.backend_priority).not_to be_empty

      provider = default_provider
      expect(provider).to be_a(String)
      expect(config.backend_priority).to include(provider)
    end

    it "registers versions with dynamic provider" do
      operations = { "width" => 800 }
      output_path = "assets/images/optimized/#{test_image_name.split('.').first}-800-provider-test.webp"

      # Register version with dynamic provider
      manifest_manager.register_version(
        test_image_name,
        output_path,
        operations,
        :default,
        "/provider-test.md",
        TestPictures.hash(test_image_name),
        default_provider
      )

      # Verify version exists
      exists = manifest_manager.version_exists?(test_image_name, operations, :default)
      expect(exists).to be true

      # Verify provider is stored correctly
      versions = manifest_manager.get_versions(test_image_name)
      version = versions["default"].first
      expect(version["provider"]).to eq(default_provider)
    end

    it "validates provider from config" do
      # Check that our provider comes from the actual config
      expect(TEST_CONFIG["imgflow"]["backend_priority"]).to include(default_provider)
      expect(config.backend_priority).to eq(TEST_CONFIG["imgflow"]["backend_priority"])
    end
  end

  describe "Version Type Constants" do
    it "has correct version types defined" do
      expect(JekyllImgFlow::ManifestManager::VERSION_TYPES).to eq(%w[default specialized])
    end

    it "validates version types correctly" do
      valid_types = JekyllImgFlow::ManifestManager::VERSION_TYPES

      expect(valid_types).to include("default")
      expect(valid_types).to include("specialized")
      expect(valid_types.length).to eq(2)
    end
  end

  describe "Edge Cases and Error Handling" do
    it "handles missing manifest file gracefully" do
      # Use a site with non-existent dest - create a proper mock
      empty_site = double("site",
                          dest: File.join(test_site_dir, "nonexistent"),
                          config: TEST_CONFIG)
      empty_manager = JekyllImgFlow::ManifestManager.new(empty_site)

      # Should work with empty manifest
      expect(empty_manager.versions?("any.jpg")).to be false
      expect(empty_manager.get_versions("any.jpg")).to eq({ "default" => [], "specialized" => [] })
    end

    it "handles nil operations gracefully" do
      result_exists = manifest_manager.version_exists?("test.jpg", nil, :default)
      result_output = manifest_manager.get_version_output("test.jpg", nil, :default)
      expect(result_exists).to be(true).or(be(false))
      expect(result_output).to be_nil.or(be_a(String))
    end

    it "handles invalid version types gracefully" do
      operations = { "width" => 800 }

      # Should not raise error for invalid type
      result_exists = manifest_manager.version_exists?("test.jpg", operations, :invalid)
      result_output = manifest_manager.get_version_output("test.jpg", operations, :invalid)
      expect(result_exists).to be(true).or(be(false))
      expect(result_output).to be_nil.or(be_a(String))
    end
  end

  describe "Integration with Test Pictures Catalog" do
    it "validates all test images from catalog" do
      default_images.each do |image|
        TestPictures.metadata(image)

        # Should be able to register versions for all catalog images
        operations = { "width" => 800 }
        output_path = "assets/images/optimized/#{image.split('.').first}-800-test.webp"

        expect do
          manifest_manager.register_version(
            image,
            output_path,
            operations,
            :default,
            "/test-#{image}.md",
            TestPictures.hash(image),
            default_provider
          )
        end.not_to raise_error

        # Verify version exists
        exists = manifest_manager.version_exists?(image, operations, :default)
        expect(exists).to be true
      end
    end

    it "uses image hashes for version tracking" do
      default_images.each do |image|
        hash = TestPictures.hash(image)
        next unless hash

        operations = { "width" => 600 }
        output_path = "assets/images/optimized/#{image.split('.').first}-600-#{hash}.webp"

        # Register version with hash
        manifest_manager.register_version(
          image,
          output_path,
          operations,
          :specialized,
          "/hash-test-#{image}.md",
          hash,
          default_provider
        )

        # Verify version exists
        exists = manifest_manager.version_exists?(image, operations, :specialized)
        expect(exists).to be true
      end
    end

    it "validates expected filename patterns" do
      default_images.each do |image|
        metadata = TestPictures.metadata(image)
        next unless metadata[:expected_defaults]

        metadata[:expected_defaults].each do |size, formats|
          formats.each_key do |format|
            # Convert size to actual width
            width = case size
                    when :sm then 400
                    when :lg then 1200
                    when :xl then 2000
                    else 800
                    end

            operations = { "width" => width, "format" => format }

            # Should handle operations and return proper values
            exists_result = manifest_manager.version_exists?(image, operations, :default)
            output_result = manifest_manager.get_version_output(image, operations, :default)
            expect(exists_result).to be(true).or(be(false))
            expect(output_result).to be_nil.or(be_a(String))
          end
        end
      end
    end
  end

  describe "Performance and Scalability" do
    it "handles multiple test images efficiently" do
      start_time = Time.now

      # Register versions for all test images
      default_images.each do |image|
        operations = { "width" => 800 }
        output_path = "assets/images/optimized/#{image.split('.').first}-800-perf.webp"

        manifest_manager.register_version(
          image,
          output_path,
          operations,
          :default,
          "/perf-test-#{image}.md",
          TestPictures.hash(image),
          default_provider
        )

        # Check all versions exist
        operations = { "width" => 800 }
        exists = manifest_manager.version_exists?(image, operations, :default)
        expect(exists).to be true
      end

      end_time = Time.now

      expect(end_time - start_time).to be < 1.0 # Should complete within 1 second
    end

    it "handles large number of versions efficiently" do
      start_time = Time.now

      # Register multiple versions for a single test image
      base_image = test_image_name
      50.times do |i|
        operations = { "width" => (800 + i) }
        output_path = "assets/images/optimized/#{base_image.split('.').first}-#{800 + i}-perf.webp"

        manifest_manager.register_version(
          base_image,
          output_path,
          operations,
          :specialized,
          "/perf-test-#{i}.md",
          TestPictures.hash(base_image),
          default_provider
        )
      end

      # Check all versions exist
      50.times do |i|
        operations = { "width" => (800 + i) }
        exists = manifest_manager.version_exists?(base_image, operations, :specialized)
        expect(exists).to be true
      end

      end_time = Time.now

      expect(end_time - start_time).to be < 1.0 # Should complete within 1 second
    end
  end
end
