# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::OperationProcessor, :unit do
  let(:site) { double("site", config: TEST_CONFIG, dest: "/tmp/test_site/_site", source: File.expand_path("..", __dir__)) }
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:manifest) { JekyllImgFlow::ManifestManager.new(site) }
  let(:path_resolver) { JekyllImgFlow::PathResolver.new(config) }
  let(:registry) { JekyllImgFlow::ProviderRegistry.new(config) }
  let(:provider) { registry.current_provider }
  let(:processor) { described_class.new(provider, path_resolver) }
  let(:test_image) { File.expand_path("fixtures/originals/mars-crater-large.jpg", __dir__) }
  let(:output_dir) { create_test_dir("operation_processor") }

  after do
    FileUtils.rm_rf(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  describe "#initialize" do
    it "initializes with provider and path_resolver" do
      expect(processor).to be_a(described_class)
      expect(processor.instance_variable_get(:@provider)).to eq(provider)
      expect(processor.instance_variable_get(:@path_resolver)).to eq(path_resolver)
      expect(processor.instance_variable_get(:@filename_generator)).to be_a(JekyllImgFlow::FilenameGenerator)
    end
  end

  describe "#process_single_operation" do
    let(:input_path) { test_image }
    let(:output_path) { File.join(output_dir, "output.jpg") }
    let(:params) { { width: 800, height: 600 } }

    it "processes a resize operation" do
      result = processor.process_single_operation(:resize, input_path, output_path, params)

      expect(result).to eq(output_path)
      expect(File.exist?(output_path)).to be true

      # Verify dimensions are correct
      valid = validate_resize_operation(input_path, output_path, 800, 600,
                                        maintain_aspect: false)
      expect(valid).to be true
    end

    it "processes a quality operation" do
      params = { quality: 90 }
      result = processor.process_single_operation(:quality, input_path, output_path, params)

      expect(result).to eq(output_path)
    end

    it "processes a format operation" do
      output_webp = File.join(output_dir, "output.webp")
      params = { format: "webp" }

      result = processor.process_single_operation(:format, input_path, output_webp, params)

      expect(result).to eq(output_webp)
    end

    it "raises error for unknown operation type" do
      expect do
        processor.process_single_operation(:unknown, input_path, output_path, {})
      end.to raise_error(/Unknown operation/)
    end
  end

  describe "#process_batch_operations" do
    let(:input_path) { test_image }
    let(:final_output) { File.join(output_dir, "final.webp") }

    it "processes multiple operations in sequence" do
      operations = [
        { type: :resize, params: { width: 800 } },
        { type: :quality, params: { quality: 90 } },
        { type: :format, params: { format: "webp" } }
      ]

      result = processor.process_batch_operations(operations, input_path, final_output)

      expect(result).to eq(final_output)
      expect(File.exist?(final_output)).to be true

      # Verify resize operation produced correct dimensions (width=800, height calculated)
      valid = validate_resize_operation(input_path, final_output, 800, nil,
                                        maintain_aspect: true)
      expect(valid).to be true
    end

    it "returns input path when operations array is empty" do
      result = processor.process_batch_operations([], input_path, final_output)

      expect(result).to eq(input_path)
    end

    it "cleans up temporary files" do
      operations = [
        { type: :resize, params: { width: 800 } },
        { type: :quality, params: { quality: 90 } }
      ]

      # Use a unique prefix to track only temp files created by this test,
      # avoiding race conditions with other parallel test processes.
      # We monkey-patch PathResolver#temp_output_path to use a test-specific prefix.
      test_prefix = "imgflow-test-#{Process.pid}-#{SecureRandom.hex(4)}-"
      path_resolver = processor.instance_variable_get(:@path_resolver)

      allow(path_resolver).to receive(:temp_output_path) do |format|
        File.join(Dir.tmpdir, "#{test_prefix}#{SecureRandom.hex}.#{format}")
      end

      # Get temp files with our prefix before processing
      temp_files_before = Dir.glob(File.join(Dir.tmpdir, "#{test_prefix}*"))

      processor.process_batch_operations(operations, input_path, final_output)

      # Check that no new temp files with our prefix were left behind
      temp_files_after = Dir.glob(File.join(Dir.tmpdir, "#{test_prefix}*"))
      new_temp_files = temp_files_after - temp_files_before

      expect(new_temp_files).to be_empty
    end
  end

  describe "#process_operation" do
    let(:original_name) { "mars-crater-large.jpg" }
    let(:input_path) { test_image }
    let(:operation) do
      { type: :resize, params: { width: 800, format: "jpg", quality: 85 } }
    end

    it "processes an operation and returns generated path" do
      result = processor.process_operation(
        original_name,
        operation,
        input_path
      )

      expect(result).to be_a(String)

      # Use TestPictures to validate filename
      filename = File.basename(result)
      expected_default = TestPictures.expected_filename("mars-crater-large.jpg", :md, :jpg)
      expect(filename).to eq(expected_default)

      expect(File.exist?(result)).to be true
    end

    it "generates JPT compatible filename" do
      result = processor.process_operation(
        original_name,
        operation,
        input_path
      )

      # Extract filename from result path
      filename = File.basename(result)

      # Use TestPictures to get expected default filename (with quality=85)
      expected_default = TestPictures.expected_filename("mars-crater-large.jpg", :md, :jpg)
      expect(filename).to eq(expected_default)
    end

    context "when input is an animated GIF" do
      let(:original_name) { "ang-head-animation.gif" }
      let(:input_path) do
        File.expand_path("fixtures/originals/ang-head-animation.gif", __dir__)
      end
      let(:operation) do
        { type: :resize, params: { width: 400, format: "webp", quality: 85 } }
      end

      it "copies the original instead of resizing" do
        result = processor.process_operation(
          original_name,
          operation,
          input_path
        )

        expect(result).to be_a(String)
        expect(File.exist?(result)).to be true

        # The output should be a byte-for-byte copy of the original GIF,
        # preserving the animation (not a converted/resized webp).
        expect(File.binread(result)).to eq(File.binread(input_path))
      end

      it "preserves the GIF magic header in the output" do
        result = processor.process_operation(
          original_name,
          operation,
          input_path
        )

        magic = File.binread(result, 6)
        expect(magic).to match(/\AGIF8[79]a\z/)
      end
    end
  end

  describe "#needs_processing?" do
    let(:input_path) { test_image }
    let(:output_path) { File.join(output_dir, "output.jpg") }
    let(:operations) { { resize: { width: 800 } } }

    it "returns true when output doesn't exist" do
      result = processor.needs_processing?(input_path, output_path, operations)

      expect(result).to be true
    end

    it "returns true when input is newer than output" do
      FileUtils.touch(output_path)
      sleep 0.1
      FileUtils.touch(input_path)

      result = processor.needs_processing?(input_path, output_path, operations)

      expect(result).to be true
    end

    it "returns false when output exists and is up-to-date" do
      FileUtils.touch(input_path)
      sleep 0.1
      FileUtils.touch(output_path)

      # Create cache key file so needs_processing? recognizes up-to-date state
      cache_key = processor.instance_variable_get(:@filename_generator)
                           .generate_cache_key(operations)
      File.write("#{output_path}.cache_key", cache_key)

      result = processor.needs_processing?(input_path, output_path, operations)

      expect(result).to be false
    end
  end

  describe "#build_operation_from_params" do
    it "builds resize operation from params" do
      params = { width: 800, height: 600, format: "jpg" }
      operation = processor.build_operation_from_params(params)

      expect(operation[:type]).to eq(:resize)
      expect(operation[:params]).to include(width: 800, height: 600, format: "jpg")
    end

    it "builds crop operation from params" do
      params = { crop: "16:9", format: "jpg" }
      operation = processor.build_operation_from_params(params)

      expect(operation[:type]).to eq(:crop)
      expect(operation[:params]).to include(crop: "16:9", format: "jpg")
    end

    it "builds format operation from params" do
      params = { format: "webp" }
      operation = processor.build_operation_from_params(params)

      expect(operation[:type]).to eq(:format)
      expect(operation[:params]).to include(format: "webp")
    end

    it "builds watermark operation from params" do
      params = { watermark: "logo.png", format: "jpg" }
      operation = processor.build_operation_from_params(params)

      expect(operation[:type]).to eq(:watermark)
      expect(operation[:params]).to include(watermark: "logo.png", format: "jpg")
    end

    it "combines all params into flat structure" do
      params = { width: 800, quality: 90, format: "webp" }
      operation = processor.build_operation_from_params(params)

      expect(operation[:type]).to eq(:resize)
      expect(operation[:params]).to include(width: 800, quality: 90, format: "webp")
    end

    it "handles empty params" do
      operation = processor.build_operation_from_params({})

      expect(operation).to be_a(Hash)
      expect(operation[:type]).to eq(:format)
    end
  end

  describe "#build_operations_from_params" do
    it "returns array with single operation" do
      params = { width: 800, format: "jpg" }
      operations = processor.build_operations_from_params(params)

      expect(operations).to be_an(Array)
      expect(operations.length).to eq(1)
      expect(operations.first[:type]).to eq(:resize)
    end
  end
end
