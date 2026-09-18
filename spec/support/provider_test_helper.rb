# frozen_string_literal: true

require "spec_helper"
require "fastimage"
require "securerandom"

module ProviderTestHelper
  # Meta-testing helper for all providers
  # Tests actual command generation, execution, and output validation
  # Uses standard RSpec helpers and TestPatterns

  def self.test_all_providers_with_operations(test_image_path, operations, context = nil,
                                              shared_components = nil)
    results = {}

    # Use shared components if provided, otherwise create new ones
    if shared_components
      components = shared_components
      components[:site]
    elsif context.respond_to?(:create_mock_site)
      site = context.create_mock_site
      components = context.create_imgflow_components(site)
    else
      # Fallback for standalone usage
      site = double("site", config: TEST_CONFIG, source: "/tmp/test_site")
      components = create_imgflow_components(site)
    end
    all_providers = components[:registry].providers

    all_providers.each do |provider|
      provider_name = provider.class.name.split("::").last

      begin
        result = test_single_provider(provider, test_image_path, operations, context)
        results[provider_name] = result

        next if result[:success]
      rescue StandardError => e
        results[provider_name] = {
          success: false,
          error: e.message,
          exception: e
        }
      end
    end

    print_summary(results)

    results
  end

  def self.test_single_provider(provider, test_image_path, operations, context = nil)
    result = {
      provider: provider.class.name.split("::").last,
      available: provider.available?,
      operations: operations.dup,
      command_generated: nil,
      output_path: nil,
      output_info: nil,
      success: false,
      error: nil
    }

    # Skip if provider not available
    unless provider.available?
      result[:error] = "Provider not available"
      return result
    end

    # Create temporary output directory
    output_dir = create_temp_output_dir(provider.class.name.split("::").last)
    result[:output_dir] = output_dir

    begin
      run_provider_test(provider, test_image_path, operations, output_dir, result, context)
    rescue StandardError => e
      result[:error] = e.message
      result[:exception] = e
    ensure
      # Cleanup
      FileUtils.rm_rf(output_dir) if output_dir && Dir.exist?(output_dir)
    end

    result
  end

  def self.run_provider_test(provider, test_image_path, operations, output_dir, result, context)
    # Generate output path first (needed for tag processing)
    output_filename = generate_output_filename(test_image_path, operations)
    output_path = File.join(output_dir, output_filename)
    result[:output_path] = output_path

    # Use proper tag interface for agnostic data flow
    tag_result = process_operations_with_tags(provider, test_image_path, output_path, operations,
                                              context)
    result[:tag_result] = tag_result

    # Test command generation (for CLI providers)
    if provider.respond_to?(:execute_command)
      # Capture command without executing
      command = capture_provider_command(provider, test_image_path, output_path)
      result[:command_generated] = command
    end

    # Execute through provider (already done by tags)
    # Tags call provider.execute() internally

    validate_test_output(test_image_path, output_path, operations, result)
  end

  def self.validate_test_output(test_image_path, output_path, operations, result)
    unless File.exist?(output_path)
      result[:error] = "Output file not created"
      return
    end

    output_info = FastImage.new(output_path)
    result[:output_info] = {
      size: output_info.size,
      type: output_info.type,
      file_size: File.size(output_path)
    }

    # Validate expected results
    validation_errors = validate_output(test_image_path, output_path, operations, output_info)
    result[:validation_errors] = validation_errors

    if validation_errors.empty?
      result[:success] = true
      result[:summary] =
        "#{output_info.type} #{output_info.size.join('x')} (#{File.size(output_path)} bytes)"
    else
      result[:error] = validation_errors.join("; ")
    end
  end

  def self.capture_provider_command(provider, input_path, output_path)
    # This is a simplified version - in real implementation,
    # you'd need to mock the actual command execution
    if provider.class.name.include?("Sharp")
      "sharp #{input_path} --output #{output_path}"
    elsif provider.class.name.include?("Imagemagick")
      "convert #{input_path} #{output_path}"
    elsif provider.class.name.include?("Libvips")
      "vips #{input_path} #{output_path}"
    else
      "HTTP request to #{provider.class.name.split('::').last}"
    end
  end

  def self.validate_output(_input_path, _output_path, operations, output_info)
    validate_format_output(operations, output_info) +
      validate_resize_output(operations, output_info) +
      validate_crop_output(operations, output_info)
  end

  # Validate format conversion
  def self.validate_format_output(operations, output_info)
    format_op = operations.find { |op| op[:type] == :format }
    return [] unless format_op

    expected_format = normalize_format(format_op[:format])
    actual_format = normalize_format(output_info.type)
    return [] if actual_format == expected_format

    ["Format mismatch: expected #{format_op[:format]}, got #{output_info.type}"]
  end

  # Validate resize operations
  def self.validate_resize_output(operations, output_info)
    resize_op = operations.find { |op| op[:type] == :resize }
    return [] unless resize_op

    expected_width = resize_op[:width]
    expected_height = resize_op[:height]
    actual_width, actual_height = output_info.size

    # If both dimensions specified, expect exact match
    if expected_width && expected_height
      return [] if actual_width == expected_width && actual_height == expected_height

      ["Size mismatch: expected #{expected_width}x#{expected_height}, " \
       "got #{actual_width}x#{actual_height}"]
    # If only one dimension specified, expect it with aspect ratio preservation
    elsif expected_width && actual_width != expected_width
      ["Width mismatch: expected #{expected_width}, got #{actual_width}"]
    elsif expected_height && actual_height != expected_height
      ["Height mismatch: expected #{expected_height}, got #{actual_height}"]
    else
      []
    end
  end

  # Validate crop operations (only when no resize was also requested)
  def self.validate_crop_output(operations, output_info)
    crop_op = operations.find { |op| op[:type] == :crop }
    resize_op = operations.find { |op| op[:type] == :resize }
    return [] unless crop_op && !resize_op

    expected_width = crop_op[:width]
    expected_height = crop_op[:height]
    actual_width, actual_height = output_info.size
    return [] if actual_width == expected_width && actual_height == expected_height

    ["Crop size mismatch: expected #{expected_width}x#{expected_height}, " \
     "got #{actual_width}x#{actual_height}"]
  end

  def self.normalize_format(format)
    format.to_s.downcase.then { |value| value == "jpeg" ? "jpg" : value }
  end

  # Process operations using proper tag interface (agnostic pattern)
  def self.process_operations_with_tags(provider, test_image_path, output_path, operations,
                                        _rspec_context = nil)
    require_relative "../spec_helper" # Ensure tag classes are loaded

    # For single operation, use simple tag approach
    if operations.length == 1
      process_single_operation(provider, test_image_path, output_path, operations.first)
    else
      process_operation_chain(provider, test_image_path, output_path, operations)
    end
  end

  # Process a single operation through its tag interface and return output info.
  def self.process_single_operation(provider, input_path, output_path, operation)
    tag = get_tag_class_for_operation(operation[:type]).new(provider)

    # Process through tag interface (includes agnostic data flow)
    tag.process(input_path, output_path, extract_options_for_operation(operation))

    output_info_result(output_path)
  end

  # For multiple operations, process them sequentially (chaining):
  # each operation's output becomes the next operation's input.
  def self.process_operation_chain(provider, test_image_path, output_path, operations)
    current_input = test_image_path

    operations.each_with_index do |op, index|
      tag = get_tag_class_for_operation(op[:type]).new(provider)
      temp_output = chained_output_path(output_path, index, operations.length)

      # Process through tag interface (includes agnostic data flow)
      tag.process(current_input, temp_output, extract_options_for_operation(op))

      # Chain operations: output becomes input for next operation
      current_input = temp_output
    end

    output_info_result(output_path)
  end

  # Intermediate operations write to temp files; the last one writes the
  # final output path.
  def self.chained_output_path(output_path, index, total)
    return output_path if index >= total - 1

    output_path.gsub(/(\.[^.]+)$/, "_temp_#{index}\\1")
  end

  # Return output info hash for a produced file, or {} when absent.
  def self.output_info_result(path)
    return {} unless File.exist?(path)

    require "fastimage"
    output_info = FastImage.new(path)
    {
      output_path: path,
      output_info: {
        size: output_info.size,
        type: output_info.type,
        file_size: File.size(path)
      }
    }
  end

  # Get appropriate tag class for operation type
  def self.get_tag_class_for_operation(operation_type)
    case operation_type
    when :resize
      JekyllImgFlow::Tags::ResizeTag
    when :crop
      JekyllImgFlow::Tags::CropTag
    when :quality
      JekyllImgFlow::Tags::QualityTag
    when :format
      JekyllImgFlow::Tags::FormatTag
    when :optimize
      JekyllImgFlow::Tags::OptimizeTag
    when :opacity
      JekyllImgFlow::Tags::OpacityTag
    when :watermark
      JekyllImgFlow::Tags::WatermarkTag
    else
      raise "Unknown operation type: #{operation_type}"
    end
  end

  # Extract options hash for tag interface
  def self.extract_options_for_operation(operation)
    case operation[:type]
    when :resize
      { width: operation[:width], height: operation[:height] }
    when :crop
      {
        width: operation[:width],
        height: operation[:height],
        x: operation[:x] || 0,
        y: operation[:y] || 0
      }
    when :quality
      { quality: operation[:quality] }
    when :format
      { formats: [operation[:format]] }
    when :optimize
      { level: operation[:level] || :medium }
    when :opacity
      { opacity: operation[:opacity] }
    when :watermark
      {
        watermark_image: operation[:watermark_image],
        position: operation[:position] || "center"
      }
    else
      {}
    end
  end

  def self.create_temp_output_dir(provider_name)
    base_dir = File.join(Dir.tmpdir, "provider_test_#{provider_name}")
    # Millisecond precision plus a random suffix guarantee uniqueness even when
    # many operation sets are tested in quick succession within the same second.
    timestamp = Time.now.strftime("%Y%m%d-%H%M%S%L")
    output_dir = File.join(base_dir, "#{timestamp}-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(output_dir)
    output_dir
  end

  def self.generate_output_filename(input_path, operations)
    basename = File.basename(input_path, ".*")

    # Add operation suffixes
    suffixes = []
    operations.each do |op|
      case op[:type]
      when :resize
        suffixes << "#{op[:width]}x#{op[:height]}"
      when :crop
        suffixes << "crop#{op[:width]}x#{op[:height]}"
      when :format
        suffixes << op[:format].to_s
      when :quality
        suffixes << "q#{op[:quality]}"
      end
    end

    format_op = operations.find { |op| op[:type] == :format }
    ext = format_op ? format_op[:format].to_s : File.extname(input_path).sub(".", "")

    "#{basename}_#{suffixes.join('_')}.#{ext}"
  end

  def self.print_summary(results)
    successful_providers = results.count { |_, result| result[:success] }
    available_providers = results.count { |_, result| result[:available] }

    Jekyll.logger.info "📊 Provider Test Summary: #{successful_providers}/#{available_providers} " \
                       "available providers succeeded"
    results.each do |provider_name, result|
      next if result[:success] || !result[:available]

      Jekyll.logger.info "   ❌ #{provider_name}: #{result[:error]}"
    end
  end

  # Predefined operation sets for comprehensive testing
  OPERATION_SETS = {
    basic_resize: [
      { type: :resize, width: 800, height: 600 }
    ],

    format_conversion: [
      { type: :resize, width: 400, height: 300 },
      { type: :format, format: :webp }
    ],

    quality_optimization: [
      { type: :resize, width: 600, height: 400 },
      { type: :quality, quality: 75 },
      { type: :format, format: :jpg }
    ],

    complex_operations: [
      { type: :crop, width: 200, height: 200, x: 50, y: 50 },
      { type: :resize, width: 400, height: 400 },
      { type: :quality, quality: 85 },
      { type: :format, format: :webp }
    ],

    all_operations: [
      { type: :resize, width: 800, height: 600 },
      { type: :quality, quality: 80 },
      { type: :format, format: :webp },
      { type: :optimize, level: :medium }
    ]
  }.freeze

  # Convenience method to test all operation sets
  def self.test_all_operation_sets(test_image_path, context = nil)
    all_results = {}

    OPERATION_SETS.each do |set_name, operations|
      results = test_all_providers_with_operations(test_image_path, operations, context)
      all_results[set_name] = results
    end

    # Generate final summary

    all_results.each_value do |results|
      results.count { |_, result| result[:success] }
      results.count { |_, result| result[:available] }
    end

    all_results
  end
end
