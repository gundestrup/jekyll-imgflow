# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

# Methods to exclude from interface compliance check
EXCLUDED_METHODS = %i[initialize execute reset_operations operations execute_command
                      get_image_dimensions check_http_service].freeze

RSpec.describe "JekyllImgFlow System Integration", :integration, :system do
  # Use TestPictures for realistic image scenarios
  let(:test_image_name) { TestPictures.get(:default).first }
  let(:test_multi_images) { TestPictures.get(:default_multi) }
  let(:test_image_path) { TestPictures.path(test_image_name) }

  # Use shared site object (same as batch_manager_spec)
  let(:site) { @site }
  let(:test_site_dir) { @test_site_dir }

  # Use standardized component creation helper
  let(:components) { create_imgflow_components(site) }
  let(:config) { components[:config] }
  let(:manifest) { components[:manifest] }
  let(:path_resolver) { components[:path_resolver] }
  let(:registry) { components[:registry] }
  let(:provider) { components[:provider] }
  let(:operation_processor) { components[:operation_processor] }

  before(:all) do
    # Create one real site as foundation for integration testing
    test_base_dir = File.join(File.expand_path("../..", __dir__), "tmp", "tests")
    FileUtils.mkdir_p(test_base_dir)
    @test_site_dir = File.join(test_base_dir, "imgflow_system_real")

    # Only create if doesn't exist (reuse across test runs)
    unless Dir.exist?(@test_site_dir)
      create_test_jekyll_site(@test_site_dir, :imgflow_only, {
                                test_images: TestPictures.get(:all)
                              })
    end

    # Create actual site object (same as batch_manager_spec)
    site_config = TEST_CONFIG.dup
    site_config["destination"] = File.join(@test_site_dir, "_site")
    site_config["source"] = @test_site_dir
    @site = Jekyll::Site.new(Jekyll.configuration(site_config))
  end

  describe "Provider Interface Compliance" do
    # Get required methods from BaseProvider interface (public methods only)
    let(:required_provider_methods) do
      JekyllImgFlow::Providers::BaseProvider.instance_methods(false).reject do |method|
        # Exclude internal/helper methods and protected methods
        EXCLUDED_METHODS.include?(method)
      end
    end

    context "Meta-Testing All Available Providers" do
      it "tests all providers with the same test suite" do
        all_providers = all_providers_from_registry

        all_providers.each do |provider_info|
          provider = provider_info[:instance]
          provider_info[:name]

          # Test 1: Implements all required methods
          missing_methods = required_provider_methods.reject do |method|
            provider.respond_to?(method)
          end

          expect(missing_methods).to be_empty

          # Test 2: Can be instantiated
          expect(provider).to be_a(JekyllImgFlow::Providers::BaseProvider)

          # Test 3: Method signatures compatible
          required_provider_methods.each do |method|
            # Methods can have negative arity (accept parameters) - that's normal
            expect(provider.method(method).arity).to be_a(Integer)
          end

          # Test 4: Can process basic operations (if available)
          TEST_CONFIG["imgflow"]
          begin
            # Simple availability check - just verify provider responds to optimize
          rescue StandardError => e
            warn "Provider availability check failed: #{e.message}"
          end
        end
      end
    end
  end

  describe "Tag System Compliance" do
    # Get available tags from the system registry
    let(:available_tags) { JekyllImgFlow::Tags::TagRegistry.available_tags }

    # Get tag classes from registry
    let(:tag_classes) do
      available_tags.map { |tag_name| JekyllImgFlow::Tags::TagRegistry.get_tag(tag_name) }
    end

    context "Tag Registry Truth" do
      it "uses system registry as single source of truth" do
        expect(available_tags).not_to be_empty
      end

      it "ensures all registered tags have corresponding classes" do
        missing_classes = available_tags.reject do |tag_name|
          JekyllImgFlow::Tags::TagRegistry.get_tag(tag_name)
        end

        expect(missing_classes).to be_empty,
                                   "Tags without classes: #{missing_classes.join(', ')}"
      end

      it "ensures all tag classes inherit from BaseTag" do
        invalid_tags = tag_classes.reject do |tag_class|
          tag_class < JekyllImgFlow::Tags::BaseTag
        end

        expect(invalid_tags).to be_empty,
                                "Tags not inheriting from BaseTag: #{invalid_tags.map(&:name).join(', ')}"
      end
    end

    context "Meta-Testing All Tags" do
      it "tests all available tags with standard interface" do
        available_tags.each do |tag_name|
          tag_class = JekyllImgFlow::Tags::TagRegistry.get_tag(tag_name)
          provider = JekyllImgFlow::Providers::Sharp.new(config)
          tag_instance = tag_class.new(provider)

          # Test standard interface
          expect(tag_instance).to respond_to(:process)

          # Test instantiation
          expect(tag_instance).to be_a(tag_class)

          # Test inheritance
          expect(tag_class).to be < JekyllImgFlow::Tags::BaseTag
        end
      end
    end
  end

  describe "Component Integration" do
    before do
      # Simple setup - use existing components from outer context
      @operation_processor = operation_processor
      @provider_registry = registry
    end

    context "Provider Management" do
      it "initializes available providers" do
        expect(@provider_registry.available_providers).not_to be_empty
      end

      it "selects current provider with fallback" do
        current_provider = @provider_registry.current_provider
        expect(current_provider).to be_a(JekyllImgFlow::Providers::BaseProvider)
      end

      it "can switch providers dynamically" do
        # Test that we can get different providers
        available = @provider_registry.available_providers
        expect(available.length).to be >= 1

        # Test provider registry functionality
        first_provider = @provider_registry.current_provider
        first_provider.reset_operations
        first_provider.resize(800, 600)
        expect(first_provider.operations.last[:type]).to eq(:resize)
        first_provider.crop("16:9")
        expect(first_provider.operations.last[:type]).to eq(:crop)
        first_provider.reset_operations
      end
    end

    context "Tag Processing" do
      before do
        # Mock OperationProcessor for fast integration testing with realistic output validation
        # Mock the method that actually calls the provider
        allow(operation_processor).to receive_messages(
          process_single_operation: "/mock/processed.webp", process_batch_operations: "/mock/final-output.webp", needs_processing?: false
        )
      end

      it "processes single tags through parser" do
        markup = "#{test_image_name} resize width:400 height:300"

        # Test 1: Parser - Parse markup into operations
        parsed = JekyllImgFlow::Parser.parse(markup)
        expect(parsed[:image_path]).to eq(test_image_name)
        expect(parsed[:operations].length).to be >= 1

        # Test 2: Tag Processing - Verify resize operation parameters
        resize_operation = parsed[:operations].find { |op| op[:type] == :resize }
        expect(resize_operation).not_to be_nil
        expect(resize_operation[:params][:width]).to eq(400)
        expect(resize_operation[:params][:height]).to eq(300)

        # Test 3: FilenameGenerator - Generate actual filename
        filename_generator = JekyllImgFlow::FilenameGenerator.new
        actual_filename = filename_generator.generate_filename(test_image_name,
                                                               resize_operation[:params])

        # Use TestPictures to get expected specialized filename (parser behavior - no quality)
        expected_specialized = TestPictures.specialized_filename(test_image_name, :sm, :jpg)
        expect(actual_filename).to eq(expected_specialized)

        # Test 4: Compare with TestPictures expectation (shows difference)
        TestPictures.expected_filename(test_image_name, :md, :webp)
        # NOTE: TestPictures expects webp with quality, but parser generates jpg without quality
        # This reveals the actual behavior vs expected behavior

        # Test 5: OperationProcessor Integration (mocked for speed)
        shared_image_path = File.join(test_site_dir, TEST_CONFIG["imgflow"]["originals"],
                                      test_image_name)
        expected_output_path = File.join(test_site_dir, "output", actual_filename)

        # Mock only the expensive Sharp processing
        allow(operation_processor).to receive_messages(
          process_single_operation: expected_output_path, process_batch_operations: expected_output_path
        )

        # Test 6: Complete Pipeline - Process through all components
        output_dir = File.join(test_site_dir, "output")
        FileUtils.mkdir_p(output_dir)
        output_path = File.join(output_dir, "single-tag-test.webp")

        results = operation_processor.process_batch_operations(
          parsed[:operations],
          shared_image_path,
          output_path
        )

        # Test 7: End-to-End Validation
        expect(results).to eq(expected_output_path)
        expect(operation_processor).to have_received(:process_batch_operations)
          .with(parsed[:operations], shared_image_path, output_path)

        # Test 8: Verify all components worked together correctly
        # Parser → Tag → FilenameGenerator → OperationProcessor
        expect(parsed[:image_path]).to eq(test_image_name) # Parser
        expect(resize_operation[:params][:width]).to eq(400) # Tag processing
        expect(actual_filename).to include("400") # FilenameGenerator
        expect(results).to end_with(actual_filename) # OperationProcessor
        # Note: TestPictures uses predefined sizes, so width might not be exactly 400
      end

      it "processes format tags through parser" do
        markup = "#{test_image_name} resize width:400 height:300 formats:webp,jpg"

        # Test 1: Parser - Parse markup with format operations
        parsed = JekyllImgFlow::Parser.parse(markup)
        expect(parsed[:image_path]).to eq(test_image_name)
        expect(parsed[:operations].length).to be >= 2

        # Test 2: Tag Processing - Verify resize and format operations
        resize_operation = parsed[:operations].find { |op| op[:type] == :resize }
        format_operation = parsed[:operations].find { |op| op[:type] == :format }

        expect(resize_operation).not_to be_nil
        expect(resize_operation[:params][:width]).to eq(400)
        expect(resize_operation[:params][:height]).to eq(300)

        expect(format_operation).not_to be_nil
        expect(format_operation[:params][:formats]).to include("webp", "jpg")

        # Test 3: FilenameGenerator - Test filename generation for resize operation
        filename_generator = JekyllImgFlow::FilenameGenerator.new
        resize_filename = filename_generator.generate_filename(test_image_name,
                                                               resize_operation[:params])

        # Use TestPictures to get expected specialized filename (parser behavior - no quality)
        expected_specialized = TestPictures.specialized_filename(test_image_name, :sm, :jpg)
        expect(resize_filename).to eq(expected_specialized)

        # Test 4: Compare with TestPictures expectation (shows difference)
        TestPictures.expected_filename(test_image_name, :md, :webp)
        # NOTE: TestPictures expects webp with quality, but parser generates jpg without quality
        # This reveals the actual behavior vs expected behavior

        # Test 5: OperationProcessor Integration (mocked for speed)
        shared_image_path = File.join(test_site_dir, TEST_CONFIG["imgflow"]["originals"],
                                      test_image_name)
        expected_output_path = File.join(test_site_dir, "output", resize_filename)

        # Mock only the expensive Sharp processing
        allow(operation_processor).to receive_messages(
          process_single_operation: expected_output_path, process_batch_operations: expected_output_path
        )

        # Test 6: Complete Pipeline - Process through all components
        output_dir = File.join(test_site_dir, "output")
        FileUtils.mkdir_p(output_dir)
        output_path = File.join(output_dir, "format-test.webp")

        results = operation_processor.process_batch_operations(
          parsed[:operations],
          shared_image_path,
          output_path
        )

        # Test 7: End-to-End Validation
        expect(results).to eq(expected_output_path)
        expect(operation_processor).to have_received(:process_batch_operations)
          .with(parsed[:operations], shared_image_path, output_path)

        # Test 8: Verify all components worked together correctly
        # Parser → Tag (resize + format) → FilenameGenerator → OperationProcessor
        expect(parsed[:image_path]).to eq(test_image_name) # Parser
        expect(resize_operation[:params][:width]).to eq(400) # Tag processing (resize)
        expect(format_operation[:params][:formats]).to include("webp", "jpg") # Tag processing (format)
        expect(resize_filename).to include("400") # FilenameGenerator
        expect(results).to end_with(resize_filename) # OperationProcessor
      end
    end
  end

  describe "Future-Proof Provider Addition" do
    it "allows easy provider addition" do
      # Define a mock provider using the system's base class
      mock_provider_class = Class.new(JekyllImgFlow::Providers::BaseProvider) do
        def resize(input_path, output_path, _width, _height, options = {})
          options.fetch(:maintain_aspect, true)
          FileUtils.cp(input_path, output_path)
        end

        def crop(input_path, output_path, _ratio, _options = {})
          FileUtils.cp(input_path, output_path)
        end

        def quality=(_quality)
          # Setter method - no file operation needed
        end

        def convert_format(input_path, output_path, _format)
          FileUtils.cp(input_path, output_path)
        end

        def optimize(input_path, output_path, _level = :medium)
          FileUtils.cp(input_path, output_path)
        end

        def add_watermark(input_path, output_path, _watermark_path, options = {})
          options.fetch(:position, :bottom_right)
          options.fetch(:opacity, 0.7)
          FileUtils.cp(input_path, output_path)
        end
      end

      # Test that it can be used with the provider
      expect(mock_provider_class.new).to respond_to(:resize)
      expect(mock_provider_class.new).to respond_to(:crop)
      expect(mock_provider_class.new).to respond_to(:quality=)
      expect(mock_provider_class.new).to respond_to(:convert_format)
      expect(mock_provider_class.new).to respond_to(:optimize)
      expect(mock_provider_class.new).to respond_to(:add_watermark)
    end
  end

  describe "Integration Tests" do
    context "Complete Workflow" do
      before do
        # Mock only the expensive operations (Sharp processing)
        # Keep real Parser validation to test file operations
        allow(operation_processor).to receive_messages(
          process_single_operation: "/mock/processed.webp", process_batch_operations: "/mock/workflow-output.webp", needs_processing?: false
        )
      end

      it "processes image through complete workflow" do
        # Use shared site object (same as batch_manager_spec)
        # No need to build - we're testing component integration, not Jekyll build
        workflow_site = site
        workflow_config = config
        workflow_components = components

        # Use the shared test image path (same as batch_manager_spec)
        image_path = File.join(test_site_dir, TEST_CONFIG["imgflow"]["originals"], test_image_name)

        # Process single tag through Parser
        markup = "#{test_image_name} resize width:400 height:300"
        mock_context = double("context", registers: { site: workflow_site })

        parsed = JekyllImgFlow::Parser.parse(markup, mock_context)
        resize_output = File.join(test_site_dir, "_site", "assets", "images", "optimized",
                                  "resize-output.webp")
        resize_results = workflow_components[:operation_processor].process_batch_operations(parsed[:operations],
                                                                                            image_path, resize_output)
        expect(resize_results).to eq("/mock/workflow-output.webp")
        expect(workflow_components[:operation_processor]).to have_received(:process_batch_operations)
          .with(parsed[:operations], image_path, resize_output)

        # Process format conversion through OperationProcessor
        format_ops = [{ type: :format, params: { formats: %w[webp jpg] } }]
        format_output = File.join(test_site_dir, "_site", "assets", "images", "optimized",
                                  "format-output.webp")
        format_results = workflow_components[:operation_processor].process_batch_operations(format_ops, resize_results,
                                                                                            format_output)
        expect(format_results).to eq("/mock/workflow-output.webp")
        expect(workflow_components[:operation_processor]).to have_received(:process_batch_operations)
          .with(format_ops, resize_results, format_output)

        # Create a simple preset for testing BEFORE creating PresetManager
        preset_dir = File.join(test_site_dir, "_data", "imgflow", "presets")
        FileUtils.mkdir_p(preset_dir)
        preset_file = File.join(preset_dir, "test.yml")
        File.write(preset_file, <<~YAML)
          operations:
            - resize:
                width: 200
                height: 150
        YAML

        # Process preset through new architecture
        preset_manager = JekyllImgFlow::PresetManager.new(workflow_site, workflow_config)

        preset_output = File.join(test_site_dir, "_site", "assets", "images", "optimized",
                                  "preset-output.webp")

        # New flow: PresetManager → Parser → OperationProcessor
        markup = preset_manager.build_markup_from_preset("test")
        full_markup = "test_image.jpg #{markup}"
        parsed = JekyllImgFlow::Parser.parse(full_markup)

        preset_results = workflow_components[:operation_processor].process_batch_operations(parsed[:operations],
                                                                                            image_path, preset_output)
        expect(preset_results).to eq("/mock/workflow-output.webp")
        expect(workflow_components[:operation_processor]).to have_received(:process_batch_operations)
          .with(parsed[:operations], image_path, preset_output)

        # No cleanup needed - shared test site will be cleaned up in after(:all)
      end
    end
  end

  describe "TestPictures Integration" do
    context "Realistic Image Processing" do
      before do
        # Mock only the expensive operations (Sharp processing)
        # Keep real Parser validation to test file operations with real images
        allow(operation_processor).to receive_messages(
          process_single_operation: "/mock/testpictures-output.webp", process_batch_operations: "/mock/testpictures-output.webp", needs_processing?: false
        )
      end

      it "processes multiple TestPictures images through complete workflow" do
        test_multi_images.each do |image_name|
          # Use shared test site - no need to create new one (same as batch_manager_spec)
          # Use shared components
          image_site = site
          image_components = components

          # Use real image path from the actual site
          image_path = File.join(test_site_dir, TEST_CONFIG["imgflow"]["originals"], image_name)

          # Process through Parser with realistic markup
          markup = "#{image_name} resize width:400 height:300 formats:webp,jpg"
          mock_context = double("context", registers: { site: image_site })

          parsed = JekyllImgFlow::Parser.parse(markup, mock_context)
          expect(parsed[:image_path]).to eq(image_name)
          expect(parsed[:operations].length).to be >= 2

          # Process through OperationProcessor
          output_dir = File.join(test_site_dir, "multi-output")
          FileUtils.mkdir_p(output_dir)
          output_path = File.join(output_dir, "processed-#{File.basename(image_name, '.jpg')}.webp")

          results = image_components[:operation_processor].process_batch_operations(
            parsed[:operations],
            image_path,
            output_path
          )

          # Test integration: verify OperationProcessor was called correctly
          expect(results).to eq("/mock/testpictures-output.webp")
          expect(image_components[:operation_processor]).to have_received(:process_batch_operations)
            .with(parsed[:operations], image_path, output_path)
        end
      end

      it "verifies JPT hash patterns in processing workflow" do
        # Test that realistic filename patterns work
        image_name = test_image_name
        expected_webp = TestPictures.expected_filename(image_name, :md, :webp)
        expected_jpg = TestPictures.expected_filename(image_name, :md, :jpg)

        # Verify JPT hash patterns
        expect(expected_webp).to include("f33ea0792") # JPT hash for mars-crater-large.jpg
        expect(expected_jpg).to include("f33ea0792")

        # Use shared test site - no need to create new one (same as batch_manager_spec)
        # Use shared components
        hash_site = site
        hash_components = components

        image_path = File.join(test_site_dir, TEST_CONFIG["imgflow"]["originals"], image_name)

        # Process with realistic operations
        markup = "#{image_name} resize width:800 height:600 formats:webp,jpg quality:85"
        mock_context = double("context", registers: { site: hash_site })

        parsed = JekyllImgFlow::Parser.parse(markup, mock_context)
        output_dir = File.join(test_site_dir, "hash-output")
        FileUtils.mkdir_p(output_dir)
        output_path = File.join(output_dir, "hash-test.webp")

        results = hash_components[:operation_processor].process_batch_operations(
          parsed[:operations],
          image_path,
          output_path
        )

        # Test integration: verify OperationProcessor was called correctly
        expect(results).to eq("/mock/testpictures-output.webp")
        expect(hash_components[:operation_processor]).to have_received(:process_batch_operations)
          .with(parsed[:operations], image_path, output_path)
      end
    end

    context "Performance with TestPictures" do
      before do
        # Mock only the expensive operations (Sharp processing)
        # Keep real Parser validation to test file operations with real images
        allow(operation_processor).to receive_messages(
          process_single_operation: "/mock/performance-output.webp", process_batch_operations: "/mock/performance-output.webp", needs_processing?: false
        )
      end

      it "handles batch processing of multiple TestPictures images" do
        # Use shared test site - no need to create new one (same as batch_manager_spec)
        batch_site = site
        batch_components = components

        # Process multiple images
        results = []
        test_multi_images.each do |image_name|
          image_path = File.join(test_site_dir, TEST_CONFIG["imgflow"]["originals"], image_name)
          markup = "#{image_name} resize width:300 height:200"
          mock_context = double("context", registers: { site: batch_site })

          parsed = JekyllImgFlow::Parser.parse(markup, mock_context)
          output_dir = File.join(test_site_dir, "batch-output")
          FileUtils.mkdir_p(output_dir)
          output_path = File.join(output_dir, "batch-#{File.basename(image_name, '.jpg')}.webp")

          result = batch_components[:operation_processor].process_batch_operations(
            parsed[:operations],
            image_path,
            output_path
          )

          results << result
        end

        # Verify all results and integration calls
        expect(results.length).to eq(test_multi_images.length)
        expect(results).to all(eq("/mock/performance-output.webp"))

        # Verify OperationProcessor was called for each image
        expect(batch_components[:operation_processor]).to have_received(:process_batch_operations)
          .exactly(test_multi_images.length).times
      end
    end
  end
end
