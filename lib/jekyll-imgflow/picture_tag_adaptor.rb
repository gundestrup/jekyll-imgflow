# frozen_string_literal: true

module JekyllImgFlow
  # Adaptor that translates Jekyll Picture Tag syntax to ImgFlow syntax
  # Simple tag-to-tag translation with values
  class PictureTagAdaptor
    def initialize(site, config)
      @site = site
      @config = config
    end

    # Convert Picture Tag to ImgFlow tag markup that can be used in templates
    # @param picture_markup [String] Picture Tag markup
    # @return [String] ImgFlow tag markup with attributes
    def to_imgflow_tag(picture_markup)
      result = translate_to_imgflow(picture_markup)
      return "" if result[:markup].empty?

      # Build ImgFlow tag with attributes
      tag_parts = ["{% imgflow", result[:markup]]

      # Add HTML attributes
      tag_parts << "alt:\"#{result[:attributes][:alt]}\"" if result[:attributes][:alt]

      if result[:attributes][:img]&.any?
        result[:attributes][:img].each do |name, value|
          tag_parts << "img-#{name}:\"#{value}\""
        end
      end

      if result[:attributes][:picture]&.any?
        result[:attributes][:picture].each do |name, value|
          tag_parts << "picture-#{name}:\"#{value}\""
        end
      end

      tag_parts << "%}"
      tag_parts.join(" ")
    end

    # Convert Picture Tag markup to ImgFlow markup with HTML attributes
    # @param picture_markup [String] Picture Tag markup like "{% picture hero image.jpg 16:9 --alt Text %}"
    # @return [Hash] Translation result with markup and attributes
    def translate_to_imgflow(picture_markup)
      # Extract content between {% picture ... %}
      match = picture_markup.match(/\{%\s*picture\s+(.+?)\s*%}/)
      return { markup: "", attributes: {} } unless match

      content = match[1].strip
      return { markup: "", attributes: {} } if content.empty?

      # Parse arguments
      args = parse_arguments(content)
      return { markup: "", attributes: {} } if args.empty?

      # Step 1: Categorize arguments by type
      categorized = categorize_arguments(args)
      return { markup: "", attributes: {} } unless categorized[:image]

      # Step 2: Translate each category to ImgFlow syntax
      imgflow_parts = []
      imgflow_parts << categorized[:image]
      imgflow_parts += translate_media_queries(categorized[:media_queries])
      imgflow_parts += translate_operations(categorized[:operations])
      imgflow_parts << "formats:webp,jpg" unless formats?(imgflow_parts)
      imgflow_parts << "markup:#{categorized[:markup_format]}" if categorized[:markup_format] && categorized[:markup_format] != "auto"

      # Step 3: Assemble result
      {
        markup: imgflow_parts.compact.join(" "),
        attributes: categorized[:html_attributes],
        markup_format: categorized[:markup_format]
      }
    end

    private

    # Parse arguments handling quoted paths and attributes
    # @param content [String] Raw content
    # @return [Array] Parsed arguments
    def parse_arguments(content)
      args = []
      current = +"" # Create unfrozen string
      in_quotes = false
      quote_char = nil

      content.dup.each_char do |char|
        case char
        when '"', "'"
          if !in_quotes
            in_quotes = true
            quote_char = char
          elsif char == quote_char
            in_quotes = false
            quote_char = nil
          else
            current << char
          end
        when " "
          if in_quotes
            current << char
          elsif !current.empty?
            args << current.dup
            current = +""
          end
        else
          current << char
        end
      end

      args << current.dup unless current.empty?
      args
    end

    # Categorize arguments into types
    # @param args [Array] All parsed arguments
    # @return [Hash] Categorized arguments
    def categorize_arguments(args)
      result = {
        image: nil,
        media_queries: {},
        operations: [],
        html_attributes: default_html_attributes,
        markup_format: nil
      }

      i = 0
      while i < args.length
        arg = args[i]

        case arg
        when /^--alt$/
          # Collect alt text until next --
          i += 1
          alt_parts = []
          while i < args.length && !args[i].start_with?("--")
            alt_parts << args[i]
            i += 1
          end
          result[:html_attributes][:alt] = strip_quotes(alt_parts.join(" "))
          next
        when /^--link$/
          result[:html_attributes][:link] = strip_quotes(args[i + 1]) if i + 1 < args.length
          i += 2
          next
        when /^--(img|picture|source|a|parent)$/
          element = ::Regexp.last_match(1).to_sym
          i += 1
          while i < args.length && !args[i].start_with?("--")
            parse_element_attribute(args[i], result[:html_attributes][element])
            i += 1
          end
          next
        when /(mobile|tablet|desktop):/
          device = ::Regexp.last_match(1)
          i += 1
          if i < args.length && args[i].include?(".")
            image = args[i]
            i += 1
            crop = parse_crop_from_arg(args[i]) if i < args.length && args[i] =~ /^\d+:\d+/
            i += 1 if crop
            result[:media_queries][device] = { image: image, crop: crop }
          end
          next
        when /^(auto|data_auto|picture|img)$/
          result[:markup_format] = arg
        when /\./
          # Image path (has extension, no colon)
          result[:image] ||= arg unless arg.include?(":")
        else
          # Operation argument
          result[:operations] << arg unless arg.start_with?("--")
        end

        i += 1
      end

      result
    end

    # Translate media queries to ImgFlow crop syntax
    # @param media_queries [Hash] Media queries by device
    # @return [Array<String>] Translated crop operations
    def translate_media_queries(media_queries)
      return [] if media_queries.empty?

      # Use mobile crop as primary (most important for responsive)
      primary = media_queries["mobile"] || media_queries.values.first
      return [] unless primary && primary[:crop]

      parts = []
      parts << "ratio:#{primary[:crop][:ratio]}" if primary[:crop][:ratio]
      parts << "keep:#{primary[:crop][:keep]}" if primary[:crop][:keep]
      parts
    end

    # Default HTML attributes structure
    def default_html_attributes
      {
        img: {},
        picture: {},
        source: {},
        a: {},
        parent: {},
        alt: nil,
        link: nil
      }
    end

    # Parse element attribute (class=value or boolean)
    # @param attr_string [String] Attribute string
    # @param attrs_hash [Hash] Hash to store parsed attributes
    def parse_element_attribute(attr_string, attrs_hash)
      case attr_string
      when /^(\w+(?:-\w+)*)=(["'])(.+?)\2$/
        attrs_hash[::Regexp.last_match(1)] = ::Regexp.last_match(3)
      when /^(\w+(?:-\w+)*)=([^"\s]+)$/
        attrs_hash[::Regexp.last_match(1)] = ::Regexp.last_match(2)
      when /^(\w+(?:-\w+)*)$/
        attrs_hash[::Regexp.last_match(1)] = true
      end
    end

    # Translate operation arguments to ImgFlow syntax
    # @param operations [Array<String>] Operation arguments
    # @return [Array<String>] Translated operations
    def translate_operations(operations)
      operations.map do |arg|
        case arg
        when /^\d+:\d+\s+(center|entropy|top|bottom|left|right|smart)$/
          parts = arg.split
          ["ratio:#{parts[0]}", "keep:#{parts[1]}"]
        when /^\d+:\d+$/
          "ratio:#{arg}"
        when /^(center|entropy|top|bottom|left|right|smart)$/
          "keep:#{arg}"
        when /^[a-zA-Z][a-zA-Z0-9_-]*$/
          "preset:#{arg}"
        when /^\d+$/
          "width:#{arg}"
        end
      end.flatten.compact
    end

    # Parse crop from argument string
    # @param arg [String] Argument like "16:9" or "16:9 center" or "16:9 attention"
    # @return [Hash, nil] Crop info with ratio and keep parameter
    def parse_crop_from_arg(arg)
      return unless arg

      parts = arg.split
      crop = {}

      if /^\d+:\d+$/.match?(parts[0])
        crop[:ratio] = parts[0]
        # Default keep to center if not specified
        crop[:keep] = parts[1] || "center"
      end

      crop.empty? ? nil : crop
    end

    # Parse crop information from crop string (for tests)
    # @param crop_string [String] Crop string like "16:9" or "16:9 center"
    # @return [Hash] Parsed crop info with ratio and keep
    def parse_crop(crop_string)
      parse_crop_from_arg(crop_string) || {}
    end

    # Strip quotes from string
    # @param str [String] String that may have quotes
    # @return [String] String without surrounding quotes
    def strip_quotes(str)
      return "" if str.nil? || str.empty?

      str = str[1..-2] if str.start_with?('"') && str.end_with?('"')
      str = str[1..-2] if str.start_with?("'") && str.end_with?("'")
      str
    end

    # Check if formats are already specified
    # @param parts [Array<String>] ImgFlow parts
    # @return [Boolean] True if formats already specified
    def formats?(parts)
      parts.any? { |part| part&.include?("formats:") }
    end

    # Determine primary crop from multiple crop options (for tests)
    # @param crops [Hash] Hash of crops by breakpoint
    # @return [Hash] Primary crop info
    def determine_primary_crop(crops)
      return crops["mobile"] if crops["mobile"]
      return crops["tablet"] if crops["tablet"]
      return crops["default"] if crops["default"]

      crops.values.first
    end
  end
end
