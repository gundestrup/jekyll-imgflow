# frozen_string_literal: true

require "shellwords"

module JekyllImgFlow
  # Central parser for all ImgFlow markup (tags, presets, etc.)
  # Optimized version with reduced duplication and complexity
  class Parser
    # Define valid operation parameters and attribute types
    OPERATION_PARAMS = %i[width height ratio aspect_ratio quality format formats
                          optimize level watermark opacity position keep preset].freeze
    HTML_ATTRIBUTES = %i[alt class title loading].freeze

    # Simple operation mappings for single-parameter operations
    SIMPLE_OPERATIONS = {
      quality: ->(val) { { type: :quality, params: { quality: val } } },
      watermark: ->(val) { { type: :watermark, params: { text: val } } },
      opacity: ->(val) { { type: :alpha_opacity, params: { opacity: val } } }
    }.freeze

    def self.parse(markup, _context = nil)
      # For KISS architecture: expect structured data from TagScanner
      return validate_structured_data(markup) if markup.is_a?(Hash) && markup.key?(:image_path)

      # Parse simple markup (backward compatibility)
      raw_options = parse_markup_to_hash(markup)
      operations = detect_operations(raw_options)
      html_attributes = extract_html_attributes(raw_options)
      image_path = extract_image_path(raw_options, markup)

      # Early return if no image path
      return build_error_response(raw_options, "No image path found in markup") unless image_path

      # File validation handled by PathResolver when resolving paths
      build_success_response(image_path, operations, html_attributes, raw_options)
    end

    def self.parse_markup_to_hash(markup)
      options = {}

      # Handle different markup formats
      if markup.include?("=")
        parse_key_value_format(markup, options)
      else
        parse_positional_format(markup, options)
      end

      options
    end

    def self.parse_key_value_format(markup, options)
      parse_key_value_pairs(markup.split, "=", result: options, handle_arrays: false)
    end

    def self.parse_positional_format(markup, options)
      # Use Shellwords for proper quote handling
      parts = Shellwords.split(markup)

      parse_key_value_pairs(
        parts,
        ":",
        result: options,
        handle_arrays: true,
        image_path_handler: lambda { |part, result|
          result[:image_path] = part unless result[:image_path]
        }
      )
    end

    def self.parse_key_value_pairs(pairs, separator, options = {})
      pairs.each do |pair|
        if pair.include?(separator)
          key, value = pair.split(separator, 2)
          options[:result][key.to_sym] = clean_and_convert_value(value, options)
        elsif options[:image_path_handler]
          options[:image_path_handler].call(pair, options[:result])
        end
      end
    end

    def self.clean_and_convert_value(value, options = {})
      value = value.tr("'\"", "")
      value = convert_numeric_value(value)

      # Handle comma-separated arrays
      value = value.split(",").map(&:strip) if options[:handle_arrays] && value.is_a?(String) && value.include?(",")

      value
    end

    def self.convert_numeric_value(value)
      return value.to_i if value.match?(/^\d+$/)
      return value.to_f if value.match?(/^\d+\.\d+$/)

      value
    end

    def self.validate_structured_data(data)
      image_path = data[:image_path]
      operations = data[:operations] || {}

      return build_error_response(data, "No image path found in structured data") unless image_path

      # Operations validation handled by Tags - Parser only parses structure
      # File validation handled by PathResolver when resolving paths
      build_success_response(image_path, operations, data[:html_attributes] || {}, data)
    end

    def self.detect_operations(options)
      operations = []
      operation_options = options.slice(*OPERATION_PARAMS)

      # Handle crop+resize combination (needs sequential processing)
      has_crop = operation_options[:ratio] || operation_options[:aspect_ratio]
      has_resize = operation_options[:width] || operation_options[:height]

      if has_crop && has_resize
        crop_params = operation_options.slice(:ratio, :aspect_ratio, :keep, :position)
        resize_params = operation_options.except(:ratio, :aspect_ratio, :keep, :position)
        operations << { type: :crop, params: crop_params }
        operations << { type: :resize, params: resize_params }
      elsif has_crop
        crop_params = operation_options.slice(:ratio, :aspect_ratio, :keep, :position)
        operations << { type: :crop, params: crop_params }
      elsif has_resize
        operations << { type: :resize, params: operation_options }
      end

      # Add simple operations using mappings
      SIMPLE_OPERATIONS.each do |key, builder|
        operations << builder.call(operation_options[key]) if operation_options[key]
      end

      # Handle format operation (can be array or single value)
      if operation_options[:format] || operation_options[:formats]
        format_value = operation_options[:format] || operation_options[:formats]
        operations << if format_value.is_a?(Array)
                        { type: :format, params: { formats: format_value } }
                      else
                        { type: :format, params: { format: format_value } }
                      end
      end

      # Handle optimize operation
      if operation_options[:optimize] || operation_options[:level]
        operations << { type: :optimize,
                        params: { level: operation_options[:level] || :medium } }
      end

      operations
    end

    def self.extract_html_attributes(options)
      options.slice(*HTML_ATTRIBUTES)
    end

    def self.extract_image_path(options, markup)
      return options[:image_path] if options[:image_path]
      return if markup.strip.empty?

      # Extract first word (before space or =)
      markup.split(/[\s=]/, 2).first&.strip
    end

    # Convert operations array from TagScanner to structured hash
    def self.convert_operations_array(operations_array)
      operations_array.each_with_object({}) do |op_str, hash|
        next unless op_str.include?(":")

        key, value = op_str.split(":", 2)
        hash[key.strip.to_sym] = clean_and_convert_value(value.strip, handle_arrays: true)
      end
    end

    def self.build_error_response(raw_options, error_message)
      {
        image_path: nil,
        operations: [],
        html_attributes: {},
        raw_options: raw_options,
        preset: nil,
        error: error_message
      }
    end

    def self.build_success_response(image_path, operations, html_attributes, raw_options)
      {
        image_path: image_path,
        operations: operations,
        html_attributes: html_attributes,
        raw_options: raw_options,
        preset: raw_options[:preset]
      }
    end

    # File validation removed - handled by PathResolver when resolving paths
    # Operations validation removed - handled by Tags
  end
end
