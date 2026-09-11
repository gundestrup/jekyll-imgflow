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

      "{% imgflow #{[result[:markup], *translated_attributes(result[:attributes]), '%}'].join(' ')}"
    end

    def translated_attributes(attributes)
      parts = []
      parts << "alt:\"#{attributes[:alt]}\"" if attributes[:alt]
      parts.concat(prefixed_attributes(attributes[:img], "img"))
      parts.concat(prefixed_attributes(attributes[:picture], "picture"))
      parts
    end

    def prefixed_attributes(attributes, prefix)
      attributes.to_h.map { |name, value| "#{prefix}-#{name}:\"#{value}\"" }
    end

    # Convert Picture Tag markup to ImgFlow markup with HTML attributes
    # @param picture_markup [String] Picture Tag markup like "{% picture hero image.jpg 16:9 --alt Text %}"
    # @return [Hash] Translation result with markup and attributes
    def translate_to_imgflow(picture_markup)
      # Extract content between {% picture ... %} without a backtracking regex
      content = extract_picture_content(picture_markup)
      return { markup: "", attributes: {} } unless content

      content = content.strip
      return { markup: "", attributes: {} } if content.empty?

      # Parse arguments
      args = parse_arguments(content)
      return { markup: "", attributes: {} } if args.empty?

      # Step 1: Categorize arguments by type
      categorized = categorize_arguments(args)
      return { markup: "", attributes: {} } unless categorized[:image]

      imgflow_parts = translated_parts(categorized)
      {
        markup: imgflow_parts.join(" "),
        attributes: categorized[:html_attributes],
        markup_format: categorized[:markup_format]
      }
    end

    private

    def translated_parts(categorized)
      parts = [categorized[:image]]
      parts.concat(translate_media_queries(categorized[:media_queries]))
      parts.concat(translate_operations(categorized[:operations]))
      parts << "formats:webp,jpg" unless formats?(parts)
      format = categorized[:markup_format]
      parts << "markup:#{format}" if format && format != "auto"
      parts.compact
    end

    def extract_picture_content(markup)
      offset = 0
      while (opening = markup.index("{%", offset))
        cursor = skip_whitespace(markup, opening + 2)
        if markup[cursor, 7] == "picture"
          cursor += 7
          if cursor < markup.length && whitespace?(markup[cursor])
            cursor = skip_whitespace(markup, cursor)
            closing = markup.index("%}", cursor)
            return markup[cursor...closing] if closing
          end
        end
        offset = opening + 2
      end
      nil
    end

    def skip_whitespace(markup, cursor)
      cursor += 1 while cursor < markup.length && whitespace?(markup[cursor])
      cursor
    end

    def whitespace?(character)
      [" ", "\t", "\r", "\n"].include?(character)
    end

    # Parse arguments handling quoted paths and attributes
    # @param content [String] Raw content
    # @return [Array] Parsed arguments
    def parse_arguments(content)
      state = { args: [], current: +"", in_quotes: false, quote_char: nil }
      content.each_char { |char| consume_argument_character(state, char) }
      state[:args] << state[:current].dup unless state[:current].empty?
      state[:args]
    end

    def consume_argument_character(state, char)
      if quote_character?(char)
        consume_quote(state, char)
      elsif char == " " && !state[:in_quotes]
        append_argument(state)
      else
        state[:current] << char
      end
    end

    def quote_character?(char)
      ["\"", "'"].include?(char)
    end

    def consume_quote(state, char)
      if !state[:in_quotes]
        state[:in_quotes] = true
        state[:quote_char] = char
      elsif char == state[:quote_char]
        state[:in_quotes] = false
        state[:quote_char] = nil
      else
        state[:current] << char
      end
    end

    def append_argument(state)
      return if state[:current].empty?

      state[:args] << state[:current].dup
      state[:current] = +""
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
      index = 0
      index = categorize_argument(args, result, index) while index < args.length
      result
    end

    def categorize_argument(args, result, index)
      arg = args[index]
      return parse_alt_argument(args, result, index) if arg == "--alt"
      return parse_link_argument(args, result, index) if arg == "--link"
      return parse_element_arguments(args, result, index) if arg.match?(/^--(img|picture|source|a|parent)$/)
      return parse_media_argument(args, result, index) if arg.match?(/(mobile|tablet|desktop):/)

      categorize_simple_argument(arg, result)
      index + 1
    end

    def parse_alt_argument(args, result, index)
      values, next_index = values_until_option(args, index + 1)
      result[:html_attributes][:alt] = strip_quotes(values.join(" "))
      next_index
    end

    def parse_link_argument(args, result, index)
      result[:html_attributes][:link] = strip_quotes(args[index + 1]) if args[index + 1]
      index + 2
    end

    def parse_element_arguments(args, result, index)
      element = args[index].match(/^--(img|picture|source|a|parent)$/)[1].to_sym
      values, next_index = values_until_option(args, index + 1)
      values.each { |value| parse_element_attribute(value, result[:html_attributes][element]) }
      next_index
    end

    def values_until_option(args, index)
      start = index
      index += 1 while index < args.length && !args[index].start_with?("--")
      [args[start...index], index]
    end

    def parse_media_argument(args, result, index)
      device = args[index].match(/(mobile|tablet|desktop):/)[1]
      image = args[index + 1]
      return index + 1 unless image&.include?(".")

      crop = parse_crop_from_arg(args[index + 2])
      result[:media_queries][device] = { image: image, crop: crop }
      index + 2 + (crop ? 1 : 0)
    end

    def categorize_simple_argument(arg, result)
      case arg
      when /^(auto|data_auto|picture|img)$/
        result[:markup_format] = arg
      when /\./
        result[:image] ||= arg unless arg.include?(":")
      else
        result[:operations] << arg unless arg.start_with?("--")
      end
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
