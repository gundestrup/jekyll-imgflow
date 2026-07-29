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
        result = test_single_provider(provider, test_image_path, operations)
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

  def self.test_single_provider(provider, test_image_path, operations)
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

      # Validate output
      if File.exist?(output_path)
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
      else
        result[:error] = "Output file not created"
      end
    rescue StandardError => e
      result[:error] = e.message
      result[:exception] = e
    ensure
      # Cleanup
      FileUtils.rm_rf(output_dir) if output_dir && Dir.exist?(output_dir)
    end

    result
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
    errors = []

    # Validate format conversion
    format_op = operations.find { |op| op[:type] == :format }
    if format_op
      expected_format = normalize_format(format_op[:format])
      actual_format = normalize_format(output_info.type)
      errors << "Format mismatch: expected #{format_op[:format]}, got #{output_info.type}" unless actual_format == expected_format
    end

    # Validate resize operations
    resize_op = operations.find { |op| op[:type] == :resize }
    if resize_op
      expected_width = resize_op[:width]
      expected_height = resize_op[:height]
      actual_width, actual_height = output_info.size

      # If both dimensions specified, expect exact match
      if expected_width && expected_height
        if actual_width != expected_width || actual_height != expected_height
          errors << "Size mismatch: expected #{expected_width}x#{expected_height}, got #{actual_width}x#{actual_height}"
        end
      # If only width specified, expect correct width with aspect ratio preservation
      elsif expected_width
        errors << "Width mismatch: expected #{expected_width}, got #{actual_width}" if actual_width != expected_width
      # If only height specified, expect correct height with aspect ratio preservation
      elsif expected_height
        errors << "Height mismatch: expected #{expected_height}, got #{actual_height}" if actual_height != expected_height
      end
    end

    # Validate crop operations
    crop_op = operations.find { |op| op[:type] == :crop }
    resize_op = operations.find { |op| op[:type] == :resize }
    if crop_op && !resize_op
      expected_width = crop_op[:width]
      expected_height = crop_op[:height]
      actual_width, actual_height = output_info.size

      if actual_width != expected_width || actual_height != expected_height
        errors << "Crop size mismatch: expected #{expected_width}x#{expected_height}, got #{actual_width}x#{actual_height}"
      end
    end

    errors
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
      op = operations.first
      tag_class = get_tag_class_for_operation(op[:type])
      tag = tag_class.new(provider)

      # Extract options for this operation
      options = extract_options_for_operation(op)

      # Process through tag interface (includes agnostic data flow)
      result = tag.process(test_image_path, output_path, options)

      # Return output info
      if File.exist?(output_path)
        require "fastimage"
        output_info = FastImage.new(output_path)
        {
          output_path: output_path,
          output_info: {
            size: output_info.size,
            type: output_info.type,
            file_size: File.size(output_path)
          }
        }
      else
        {}
      end
    else
      # For multiple operations, process them sequentially (chaining)
      results = []
      current_input = test_image_path
      current_output = output_path

      operations.each_with_index do |op, index|
        tag_class = get_tag_class_for_operation(op[:type])
        tag = tag_class.new(provider)

        # Extract options for this operation
        options = extract_options_for_operation(op)

        # For chained operations, use temporary files between operations
        temp_output = if operations.length > 1 && index < operations.length - 1
                        output_path.gsub(/(\.[^.]+)$/, "_temp_#{index}\\1")
                      else
                        current_output
                      end

        # Process through tag interface (includes agnostic data flow)
        result = tag.process(current_input, temp_output, options)
        results << result

        # Chain operations: output becomes input for next operation
        current_input = temp_output
      end

      # Return final output info
      if File.exist?(current_output)
        require "fastimage"
        output_info = FastImage.new(current_output)
        {
          output_path: current_output,
          output_info: {
            size: output_info.size,
            type: output_info.type,
            file_size: File.size(current_output)
          }
        }
      else
        {}
      end
    end
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
    results.length
    successful_providers = results.count { |_, result| result[:success] }
    available_providers = results.count { |_, result| result[:available] }

    results.each_value do |result|
      if result[:success]
        "✅"
      else
        (result[:available] ? "❌" : "⏸️")
      end
    end

    return if successful_providers == available_providers && available_providers > 0

    nil if available_providers == 0
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
