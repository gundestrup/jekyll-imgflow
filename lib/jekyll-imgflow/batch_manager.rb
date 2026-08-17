# frozen_string_literal: true

require_relative "filename_generator"

module JekyllImgFlow
  # BatchManager - manages batch processing of image operations
  # Queues tasks and processes them efficiently
  class BatchManager
    attr_reader :queue, :completed, :failed

    def initialize(operation_processor)
      @operation_processor = operation_processor
      @filename_generator = FilenameGenerator.new
      @queue = []
      @completed = []
      @failed = []
      @mutex = Mutex.new
    end

    # Add a task to the batch queue
    # @param task [Hash] Task definition
    # @option task [String] :original_name Original image filename
    # @option task [Symbol] :operation_type Type of operation
    # @option task [String] :input_path Path to input image
    # @option task [String] :output_path Path to output image
    # @option task [Hash] :params Operation parameters
    # @option task [Symbol] :version_type :default or :specialized
    # @option task [String] :page_path Page using this image
    def add_task(task)
      @mutex.synchronize do
        @queue << task
      end
    end

    # Add multiple tasks to the queue
    # @param tasks [Array<Hash>] Array of task definitions
    def add_tasks(tasks)
      @mutex.synchronize do
        @queue.concat(tasks)
      end
    end

    # Process all queued tasks
    # @param parallel [Boolean] Whether to process in parallel (future enhancement)
    # @return [Hash] Results summary
    def process_all(parallel: false)
      start_time = Time.now

      if parallel
        # Future: implement parallel processing
        process_parallel
      else
        process_sequential
      end

      end_time = Time.now
      duration = end_time - start_time

      {
        total: @queue.length + @completed.length + @failed.length,
        completed: @completed.length,
        failed: @failed.length,
        duration: duration
      }
    end

    # Process tasks sequentially
    def process_sequential
      while (task = next_task)
        process_task(task)
      end
    end

    # Process tasks in parallel (future enhancement)
    def process_parallel
      # Future: implement thread pool for parallel processing
      # For now, fall back to sequential
      process_sequential
    end

    # Get the next task from the queue
    # @return [Hash, nil] Next task or nil if queue is empty
    def next_task
      @mutex.synchronize do
        @queue.shift
      end
    end

    # Process a single task
    # @param task [Hash] Task to process
    def process_task(task)
      # Check if processing is needed
      # Check if output is up-to-date
      if task[:skip_if_exists] && File.exist?(task[:output_path]) && !@operation_processor.needs_processing?(
        task[:input_path],
        task[:output_path],
        task[:params]
      )
        Jekyll.logger.debug "⏭️  Skipping #{task[:original_name]} - already up-to-date"
        mark_completed(task, :skipped)
        return
      end

      # Process the operation
      operation = {
        type: task[:operation_type],
        params: task[:params]
      }

      Jekyll.logger.debug "🔍 BatchManager: Processing task - input: #{task[:input_path]}, original: #{task[:original_name]}"
      result = @operation_processor.process_operation(
        task[:original_name],
        operation,
        task[:input_path]
      )
      Jekyll.logger.debug "🔍 BatchManager: OperationProcessor returned - result: #{result}"

      # Store result for manifest registration
      task[:result_path] = result

      mark_completed(task, :processed, result)
      Jekyll.logger.debug "✅ Processed: #{task[:original_name]} → #{File.basename(result)}"
    rescue StandardError => e
      mark_failed(task, e)
      Jekyll.logger.error "❌ Failed: #{task[:original_name]} - #{e.message}"
    end

    # Mark a task as completed
    # @param task [Hash] Completed task
    # @param status [Symbol] Completion status (:processed or :skipped)
    # @param result [String] Result path
    def mark_completed(task, status, result = nil)
      @mutex.synchronize do
        @completed << {
          task: task,
          status: status,
          result: result,
          completed_at: Time.now
        }
      end
    end

    # Mark a task as failed
    # @param task [Hash] Failed task
    # @param error [Exception] Error that occurred
    def mark_failed(task, error)
      @mutex.synchronize do
        @failed << {
          task: task,
          error: error.message,
          backtrace: error.backtrace&.first(5),
          failed_at: Time.now
        }
      end
    end

    # Get queue status
    # @return [Hash] Current queue status
    def status
      @mutex.synchronize do
        {
          queued: @queue.length,
          completed: @completed.length,
          failed: @failed.length,
          total: @queue.length + @completed.length + @failed.length
        }
      end
    end

    # Clear all queues
    def clear
      @mutex.synchronize do
        @queue.clear
        @completed.clear
        @failed.clear
      end
    end

    # Get failed tasks for retry
    # @return [Array<Hash>] Array of failed tasks
    def failed_tasks
      @mutex.synchronize do
        @failed.map { |f| f[:task] }
      end
    end

    # Retry failed tasks
    # @return [Integer] Number of tasks added back to queue
    def retry_failed
      tasks = failed_tasks
      @mutex.synchronize do
        @failed.clear
        @queue.concat(tasks)
      end
      tasks.length
    end

    # Build batch tasks for default image versions
    # @param original_name [String] Original image filename
    # @param input_path [String] Path to original image
    # @param config [Config] ImgFlow configuration
    # @param site [Jekyll::Site] Jekyll site object
    # @return [Array<Hash>] Array of tasks
    def self.build_default_tasks(original_name, input_path, config, _site)
      tasks = []

      # Use FilenameGenerator for consistent naming
      filename_generator = JekyllImgFlow::FilenameGenerator.new
      path_resolver = JekyllImgFlow::PathResolver.new(config)

      config.sizes.each_value do |width|
        config.formats.each do |format|
          # Use FilenameGenerator to generate proper filename
          operations = { width: width, format: format, quality: config.quality }
          filename = filename_generator.generate_filename(original_name, operations)

          # Preserve original directory structure under output
          subdir = File.dirname(original_name)
          subdir = nil if subdir == "."

          # Write to source directory so Jekyll copies files to _site during write phase
          output_path = path_resolver.resolve_source_output_path(filename, subdir)

          tasks << {
            original_name: original_name,
            operation_type: :resize,
            input_path: input_path,
            output_path: output_path,
            params: {
              width: width,
              format: format,
              quality: config.quality
            },
            version_type: :default,
            page_path: nil, # Default versions not tied to specific page
            skip_if_exists: true
          }
        end
      end

      tasks
    end

    # Build batch tasks for specialized image version
    # @param original_name [String] Original image filename
    # @param input_path [String] Path to original image
    # @param operations [Array<Hash>] Operations to apply
    # @param output_path [String] Path to output image
    # @param page_path [String] Page using this image
    # @return [Hash] Task definition
    def self.build_specialized_task(original_name, input_path, operations, output_path, page_path)
      # For now, assume single operation
      # Future: support chaining multiple operations
      operation = operations.first

      {
        original_name: original_name,
        operation_type: operation[:type],
        input_path: input_path,
        output_path: output_path,
        params: operation[:params],
        version_type: :specialized,
        page_path: page_path,
        skip_if_exists: false
      }
    end
  end
end
