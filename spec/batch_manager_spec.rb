# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::BatchManager, :unit do
  let(:test_site_dir) { create_test_dir("batch_manager_test") }
  let(:site) { @site }
  let(:test_site_dir) { @test_site_dir }
  # Use standardized component creation helper
  let(:components) { create_imgflow_components(site) }
  let(:config) { components[:config] }
  let(:batch_manager) { components[:batch_manager] }
  let(:operation_processor) { components[:operation_processor] }
  # Test image helpers
  let(:default_images) { TestPictures.get(:default_multi) }
  let(:test_image) { File.join(site.source, config.originals, default_images.first) }
  let(:output_dir) { File.join(site.dest, config.output) }
  let(:output_extension) { File.extname(default_images.first)[1..] }
  let(:test_image_name) { default_images.first }
  # Enhanced helpers using TestPictures
  let(:expected_md_webp) { TestPictures.expected_filename(test_image_name, :md, :webp) }
  let(:expected_md_avif) { TestPictures.expected_filename(test_image_name, :md, :avif) }
  let(:expected_sm_webp) { TestPictures.expected_filename(test_image_name, :sm, :webp) }
  let(:expected_lg_webp) { TestPictures.expected_filename(test_image_name, :lg, :webp) }

  before(:all) do
    # Create test site once for all tests (original files never changed)
    @test_site_dir = create_test_dir("batch_manager_test")
    create_test_jekyll_site(@test_site_dir, :imgflow_only,
                            { test_images: TestPictures.get(:default_multi) })

    # Create actual site object
    site_config = TEST_CONFIG.dup
    site_config["destination"] = File.join(@test_site_dir, "_site")
    site_config["source"] = @test_site_dir
    @site = Jekyll::Site.new(Jekyll.configuration(site_config))
  end

  def create_realistic_task(image_name = test_image_name, size = :md, format = :webp)
    filename = TestPictures.expected_filename(image_name, size, format)
    {
      original_name: image_name,
      operation_type: :resize,
      input_path: File.join(site.source, config.originals, image_name),
      output_path: File.join(output_dir, filename || "output.#{format}"),
      params: { width: config.sizes[size], format: format,
                quality: config.quality },
      version_type: :default,
      page_path: nil,
      skip_if_exists: true
    }
  end

  def create_realistic_completed_tasks(image_name = test_image_name, sizes: %i[sm md],
                                       formats: %i[webp avif])
    TestPictures.mock_completed_tasks(image_name, sizes: sizes, formats: formats,
                                                  output_dir: output_dir)
  end

  after(:all) do
    FileUtils.rm_rf(@test_site_dir) if @test_site_dir && Dir.exist?(@test_site_dir)
  end

  describe "#initialize" do
    it "initializes with operation processor" do
      expect(batch_manager).to be_a(described_class)
      expect(batch_manager.queue).to eq([])
      expect(batch_manager.completed).to eq([])
      expect(batch_manager.failed).to eq([])
    end
  end

  describe "#add_task" do
    let(:task) { create_realistic_task }

    it "adds a task to the queue" do
      batch_manager.add_task(task)

      expect(batch_manager.queue.length).to eq(1)
      expect(batch_manager.queue.first).to eq(task)
    end

    it "uses realistic filenames" do
      batch_manager.add_task(task)

      added_task = batch_manager.queue.first
      expect(added_task[:output_path]).to include(expected_md_webp)
      expect(added_task[:params]).to include(width: config.sizes[:md], format: :webp)
    end

    it "is thread-safe with realistic filenames" do
      threads = Array.new(10) do |i|
        Thread.new do
          # Use different TestPictures images for realistic testing
          image_names = TestPictures.get(:default_multi)
          image_name = image_names[i % image_names.length]
          size = %i[sm md lg][i % 3]
          format = %i[webp avif][i % 2]

          batch_manager.add_task(create_realistic_task(image_name, size, format))
        end
      end
      threads.each(&:join)

      expect(batch_manager.queue.length).to eq(10)

      # Tasks are validated by create_realistic_task method which uses TestPictures
    end
  end

  describe "#add_tasks" do
    let(:tasks) do
      Array.new(3) do |i|
        # Create realistic tasks with different sizes and formats
        size = %i[sm md lg][i]
        format = %i[webp avif jpg][i]
        create_realistic_task(test_image_name, size, format)
      end
    end

    it "adds multiple tasks to the queue" do
      batch_manager.add_tasks(tasks)

      expect(batch_manager.queue.length).to eq(3)
    end

    it "adds tasks with realistic filenames" do
      batch_manager.add_tasks(tasks)

      # Verify each task has correct expected filename
      sizes = %i[sm md lg]
      formats = %i[webp avif jpg]
      batch_manager.queue.each_with_index do |task, i|
        size = sizes[i]
        format = formats[i]
        expected_filename = TestPictures.expected_filename(test_image_name, size, format)
        expect(task[:output_path]).to include(expected_filename)
        expect(task[:params][:width]).to eq(config.sizes[size])
        expect(task[:params][:format]).to eq(format)
      end
    end
  end

  describe "#process_all" do
    before do
      allow(operation_processor).to receive_messages(process_operation: "/output/path.jpg",
                                                     needs_processing?: false)
    end

    let(:task) { create_realistic_task }

    it "processes all queued tasks" do
      batch_manager.add_task(task)
      batch_manager.add_task(task.merge(original_name: "test2.jpg"))

      results = batch_manager.process_all

      expect(results[:total]).to eq(2)
      expect(results[:completed]).to eq(2)
      expect(results[:failed]).to eq(0)
      expect(batch_manager.queue).to be_empty
    end

    it "returns processing statistics" do
      batch_manager.add_task(task)

      results = batch_manager.process_all

      expect(results).to include(:total, :completed, :failed, :duration)
      expect(results[:duration]).to be_a(Numeric)
    end

    it "processes tasks sequentially by default" do
      batch_manager.add_task(task)

      results = batch_manager.process_all(parallel: false)

      expect(results[:completed]).to eq(1)
    end

    it "validates realistic task structure" do
      batch_manager.add_task(task)

      # Verify the task has realistic filename structure
      added_task = batch_manager.queue.first
      expect(added_task[:output_path]).to include(expected_md_webp)
      expect(added_task[:params][:width]).to eq(config.sizes[:md])
      expect(added_task[:params][:format]).to eq(:webp)

      # Process the task
      results = batch_manager.process_all
      expect(results[:completed]).to eq(1)
    end
  end

  describe "#status" do
    let(:task) do
      {
        original_name: default_images.first,
        operation_type: :resize,
        input_path: test_image,
        output_path: File.join(output_dir, "output.#{output_extension}"),
        params: { width: 800 },
        version_type: :default,
        page_path: nil,
        skip_if_exists: true
      }
    end

    it "returns current queue status" do
      batch_manager.add_task(task)
      batch_manager.add_task(task.merge(original_name: "test2.jpg"))

      status = batch_manager.status

      expect(status[:queued]).to eq(2)
      expect(status[:completed]).to eq(0)
      expect(status[:failed]).to eq(0)
      expect(status[:total]).to eq(2)
    end
  end

  describe "#clear" do
    let(:task) do
      {
        original_name: default_images.first,
        operation_type: :resize,
        input_path: test_image,
        output_path: File.join(output_dir, "output.#{output_extension}"),
        params: { width: 800 },
        version_type: :default,
        page_path: nil,
        skip_if_exists: true
      }
    end

    it "clears all queues" do
      batch_manager.add_task(task)
      batch_manager.clear

      expect(batch_manager.queue).to be_empty
      expect(batch_manager.completed).to be_empty
      expect(batch_manager.failed).to be_empty
    end
  end

  describe "#retry_failed" do
    it "moves failed tasks back to queue" do
      # Simulate a failed task
      failed_task = {
        original_name: default_images.first,
        operation_type: :resize,
        input_path: test_image,
        output_path: File.join(output_dir, "output.#{output_extension}"),
        params: { width: 800 },
        version_type: :default,
        page_path: nil,
        skip_if_exists: true
      }

      batch_manager.instance_variable_get(:@failed) << {
        task: failed_task,
        error: "Test error",
        failed_at: Time.now
      }

      count = batch_manager.retry_failed

      expect(count).to eq(1)
      expect(batch_manager.queue.length).to eq(1)
      expect(batch_manager.failed).to be_empty
    end
  end

  describe ".build_default_tasks" do
    let(:original_name) { test_image }
    let(:input_path) { test_image }

    it "builds tasks for all configured sizes and formats" do
      tasks = described_class.build_default_tasks(original_name, input_path, config, site)

      expect(tasks).to be_an(Array)
      expect(tasks).not_to be_empty

      # Should have one task per size × format combination
      expected_count = config.sizes.length * config.formats.length
      expect(tasks.length).to eq(expected_count)
    end

    it "generates correct filenames in default tasks" do
      tasks = described_class.build_default_tasks(original_name, input_path, config, site)

      # Verify each task has correct expected filename
      tasks.each do |task|
        image_name = File.basename(original_name)
        size = task[:params][:size]
        format = task[:params][:format]

        expected_filename = TestPictures.expected_filename(image_name, size, format)
        if expected_filename
          expect(task[:output_path]).to include(expected_filename)
        else
          # Fallback for images not in TestPictures catalog
          expect(task[:output_path]).to include(File.basename(image_name, ".*"))
        end

        # Check that width is set correctly (it might be using a different key)
        expect(task[:params][:width]).to be_a(Integer)
        expect(task[:params][:width]).to be > 0
        expect(task[:params][:quality]).to eq(config.quality)
      end
    end

    it "creates tasks with correct structure" do
      tasks = described_class.build_default_tasks(original_name, input_path, config, site)

      task = tasks.first
      expect(task).to include(
        :original_name,
        :operation_type,
        :input_path,
        :output_path,
        :params,
        :version_type,
        :page_path,
        :skip_if_exists
      )

      expect(task[:version_type]).to eq(:default)
      expect(task[:operation_type]).to eq(:resize)
      expect(task[:skip_if_exists]).to be true
    end

    it "includes width, format, and quality in params" do
      tasks = described_class.build_default_tasks(original_name, input_path, config, site)

      task = tasks.first
      expect(task[:params]).to include(:width, :format, :quality)
    end

    it "preserves original directory structure in output paths" do
      nested_name = "valdemar/#{test_image}"
      nested_input = File.join(config.site.source, config.originals, nested_name)
      tasks = described_class.build_default_tasks(nested_name, nested_input, config, site)

      tasks.each do |task|
        expect(task[:output_path]).to include("valdemar/")
        expect(task[:output_path]).not_to include("/valdemar/valdemar/")
      end
    end
  end

  describe ".build_specialized_task" do
    let(:original_name) { default_images.first }
    let(:input_path) { test_image }
    let(:operations) { [{ type: :resize, params: { width: 750, quality: 90 } }] }
    let(:output_path) { File.join(output_dir, "specialized.#{output_extension}") }
    let(:page_path) { "blog/post.html" }

    it "builds a specialized task" do
      task = described_class.build_specialized_task(
        original_name,
        input_path,
        operations,
        output_path,
        page_path
      )

      expect(task).to be_a(Hash)
      expect(task[:version_type]).to eq(:specialized)
      expect(task[:page_path]).to eq(page_path)
      expect(task[:skip_if_exists]).to be false
    end

    it "uses first operation from operations array" do
      task = described_class.build_specialized_task(
        original_name,
        input_path,
        operations,
        output_path,
        page_path
      )

      expect(task[:operation_type]).to eq(:resize)
      expect(task[:params]).to include(width: 750, quality: 90)
    end
  end

  describe "error handling" do
    let(:task) do
      {
        original_name: default_images.first,
        operation_type: :resize,
        input_path: test_image,
        output_path: File.join(output_dir, "output.#{output_extension}"),
        params: { width: 800 },
        version_type: :default,
        page_path: nil,
        skip_if_exists: false
      }
    end

    it "manages failed tasks correctly" do
      # Test mark_failed method directly
      error = StandardError.new("Test error")
      batch_manager.mark_failed(task, error)

      expect(batch_manager.failed.length).to eq(1)
      expect(batch_manager.failed.first[:task]).to eq(task)
      expect(batch_manager.failed.first[:error]).to eq("Test error")
      expect(batch_manager.failed.first[:failed_at]).to be_within(1).of(Time.now)
    end

    it "retries failed tasks" do
      # Manually add a failed task
      error = StandardError.new("Test error")
      batch_manager.mark_failed(task, error)

      # Retry failed tasks
      retried_count = batch_manager.retry_failed

      expect(retried_count).to eq(1)
      expect(batch_manager.failed.length).to eq(0)
      expect(batch_manager.queue.length).to eq(1)
    end
  end

  describe "#next_task" do
    let(:task) do
      {
        original_name: default_images.first,
        operation_type: :resize,
        input_path: test_image,
        output_path: File.join(output_dir, "output.#{output_extension}"),
        params: { width: 800 },
        version_type: :default,
        page_path: nil,
        skip_if_exists: true
      }
    end

    before do
      batch_manager.add_task(task)
      batch_manager.add_task(task.merge(original_name: "test2.jpg"))
    end

    it "returns the next task from queue" do
      first_task = batch_manager.next_task
      expect(first_task[:original_name]).to eq(default_images.first)
      expect(batch_manager.queue.length).to eq(1)
    end

    it "returns nil when queue is empty" do
      # Clear all tasks
      batch_manager.next_task
      batch_manager.next_task

      expect(batch_manager.next_task).to be_nil
    end
  end

  describe "#process_task" do
    let(:task) do
      {
        original_name: default_images.first,
        operation_type: :resize,
        input_path: test_image,
        output_path: File.join(output_dir, "output.#{output_extension}"),
        params: { width: 800 },
        version_type: :default,
        page_path: nil,
        skip_if_exists: true
      }
    end

    # NOTE: process_task is tested indirectly via process_all tests
    # Direct testing requires complex mocking of operation_processor
    # The queue management and error handling are tested in other methods

    it "adds task to queue for processing" do
      batch_manager.add_task(task)
      expect(batch_manager.queue.length).to eq(1)
      expect(batch_manager.queue.first).to eq(task)
    end
  end

  describe "#mark_completed" do
    let(:task) do
      {
        original_name: default_images.first,
        operation_type: :resize,
        input_path: test_image,
        output_path: File.join(output_dir, "output.#{output_extension}"),
        params: { width: 800 },
        version_type: :default,
        page_path: nil,
        skip_if_exists: true
      }
    end

    it "marks a task as completed with status" do
      batch_manager.mark_completed(task, :processed, "/output/path.jpg")

      expect(batch_manager.completed.length).to eq(1)
      completed_task = batch_manager.completed.first
      expect(completed_task[:task]).to eq(task)
      expect(completed_task[:status]).to eq(:processed)
      expect(completed_task[:result]).to eq("/output/path.jpg")
    end

    it "records completion timestamp" do
      before_time = Time.now
      batch_manager.mark_completed(task, :processed)
      after_time = Time.now

      completed_at = batch_manager.completed.first[:completed_at]
      expect(completed_at).to be_between(before_time, after_time)
    end
  end

  describe "#mark_failed" do
    let(:task) do
      {
        original_name: default_images.first,
        operation_type: :resize,
        input_path: test_image,
        output_path: File.join(output_dir, "output.#{output_extension}"),
        params: { width: 800 },
        version_type: :default,
        page_path: nil,
        skip_if_exists: true
      }
    end

    it "marks a task as failed with error" do
      error = StandardError.new("Test error")
      batch_manager.mark_failed(task, error)

      expect(batch_manager.failed.length).to eq(1)
      failed_task = batch_manager.failed.first
      expect(failed_task[:task]).to eq(task)
      expect(failed_task[:error]).to eq("Test error")
      expect(failed_task[:failed_at]).to be_within(1).of(Time.now)
    end
  end

  describe "#failed_tasks" do
    let(:task) do
      {
        original_name: default_images.first,
        operation_type: :resize,
        input_path: test_image,
        output_path: File.join(output_dir, "output.#{output_extension}"),
        params: { width: 800 },
        version_type: :default,
        page_path: nil,
        skip_if_exists: true
      }
    end

    it "returns array of failed tasks without error info" do
      error = StandardError.new("Test error")
      batch_manager.mark_failed(task, error)

      failed_tasks = batch_manager.failed_tasks

      expect(failed_tasks.length).to eq(1)
      expect(failed_tasks.first).to eq(task)
      expect(failed_tasks.first).not_to have_key(:error)
    end

    it "returns empty array when no failed tasks" do
      expect(batch_manager.failed_tasks).to be_empty
    end
  end

  describe "#process_all with parallel: true" do
    it "falls back to sequential when parallel is true" do
      task = create_batch_task("test.jpg", "/input.jpg", "/output.jpg")
      batch_manager.add_task(task)

      allow(operation_processor).to receive_messages(needs_processing?: true, process_operation: "/output.jpg")

      result = batch_manager.process_all(parallel: true)
      expect(result[:completed]).to eq(1)
    end
  end

  describe "#process_task skip path" do
    it "skips task when output exists and doesn't need processing" do
      task = create_batch_task("test.jpg", "/input.jpg", "/output.jpg", skip_if_exists: true)
      batch_manager.add_task(task)

      allow(File).to receive(:exist?).with("/output.jpg").and_return(true)
      allow(operation_processor).to receive(:needs_processing?).and_return(false)
      allow(Jekyll.logger).to receive(:debug)

      batch_manager.process_all
      expect(batch_manager.completed.first[:status]).to eq(:skipped)
    end
  end

  describe "#process_task error handling" do
    it "marks task as failed when processing raises" do
      task = create_batch_task("test.jpg", "/input.jpg", "/output.jpg", skip_if_exists: false)
      batch_manager.add_task(task)

      allow(operation_processor).to receive(:process_operation).and_raise(StandardError, "Processing failed")
      allow(Jekyll.logger).to receive(:error)
      allow(Jekyll.logger).to receive(:debug)

      batch_manager.process_all
      expect(batch_manager.failed.length).to eq(1)
      expect(batch_manager.failed.first[:error]).to eq("Processing failed")
    end
  end
end
