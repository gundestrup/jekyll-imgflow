# frozen_string_literal: true

module JekyllImgFlow
  # Unified HTML Generator for all markup formats
  # Supports Picture Tag compatibility with multiple markup formats and attributes
  class HtmlGenerator
    MARKUP_FORMATS = %w[auto picture img data_auto data_picture data_img direct_url
                        naked_srcset].freeze

    # Generate HTML based on markup format and attributes
    # @param results [Array<String>] Processed image paths
    # @param attributes [Hash] HTML attributes by element
    # @param markup_format [String] Markup format (auto, picture, img, data_auto, etc.)
    # @param context [Liquid::Context] Liquid context
    # @param config [JekyllImgFlow::Config] ImgFlow configuration
    # @return [String] Generated HTML
    def self.generate(results, attributes, markup_format, context, config = nil)
      return "" if results.empty?

      generator = new(results, attributes, markup_format, context, config)
      generator.generate
    end

    def initialize(results, attributes, markup_format, context, config = nil)
      @results = results
      @attributes = normalize_attributes(attributes)
      @markup_format = markup_format || "img"
      @context = context
      @config = config
      @path_resolver = config ? JekyllImgFlow::PathResolver.new(config) : nil
      @fallback_formats = fallback_formats
    end

    def generate
      html = case @markup_format
             when "picture", "auto"
               generate_picture_element
             when "data_picture"
               generate_data_picture_element
             when "data_img", "data_auto"
               generate_data_img_element
             when "direct_url"
               generate_direct_url
             when "naked_srcset"
               generate_naked_srcset
             else
               generate_img_element # Default fallback
             end

      # Wrap in link if specified
      html = wrap_with_link(html) if @attributes[:link]

      # Wrap in parent container if specified
      html = wrap_with_parent(html) if @attributes[:parent]&.any?

      html
    end

    private

    # Get fallback formats — only the configured fallback format (e.g. jpg).
    # These are skipped in the <source> loop and used for the <img> fallback.
    # All other formats (webp, avif, etc.) get <source> tags.
    def fallback_formats
      if @config&.fallback_format
        [".#{@config.fallback_format}"]
      else
        %w[.jpg .jpeg .png]
      end
    end

    # Normalize attributes from different sources
    def normalize_attributes(attributes)
      return default_attributes if attributes.nil? || attributes.empty?

      {
        img: attributes[:img] || {},
        picture: attributes[:picture] || {},
        source: attributes[:source] || {},
        a: attributes[:a] || {},
        parent: attributes[:parent] || {},
        alt: attributes[:alt],
        link: attributes[:link]
      }
    end

    def default_attributes
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

    # Generate standard <picture> element with <source> tags
    def generate_picture_element
      picture_attrs = build_attributes(@attributes[:picture])
      img_attrs = build_img_attributes

      html = "<picture#{picture_attrs}>"

      # Generate source elements for each format (except fallback)
      format_groups = group_by_format(@results)

      format_groups.each do |ext, files|
        next if @fallback_formats.include?(ext) # Skip fallback formats

        mime_type = mime_type_for(ext)
        source_attrs = build_attributes(@attributes[:source])
        srcset = files.map { |f| html_path(f) }.join(", ")

        html << "<source srcset=\"#{srcset}\" type=\"#{mime_type}\"#{source_attrs}>"
      end

      # Fallback img element
      fallback = find_fallback_image(@results)
      html << "<img src=\"#{html_path(fallback)}\"#{img_attrs}>"
      html << "</picture>"

      html
    end

    # Generate standard <img> element
    def generate_img_element
      img_attrs = build_img_attributes
      primary = @results.first

      # Build srcset if multiple results
      srcset_attr = if @results.length > 1
                      srcset = generate_srcset_string(@results)
                      " srcset=\"#{srcset}\""
                    else
                      ""
                    end

      "<img src=\"#{html_path(primary)}\"#{srcset_attr}#{img_attrs}>"
    end

    # Generate <picture> element with data-* attributes for lazy loading
    def generate_data_picture_element
      picture_attrs = build_attributes(@attributes[:picture])
      img_attrs = build_data_img_attributes

      html = "<picture#{picture_attrs}>"

      # Generate source elements with data-srcset
      format_groups = group_by_format(@results)

      format_groups.each do |ext, files|
        next if @fallback_formats.include?(ext)

        mime_type = mime_type_for(ext)
        source_attrs = build_attributes(@attributes[:source])
        srcset = files.map { |f| html_path(f) }.join(", ")

        html << "<source data-srcset=\"#{srcset}\" type=\"#{mime_type}\"#{source_attrs}>"
      end

      # Fallback img with data-src
      fallback = find_fallback_image(@results)
      html << "<img data-src=\"#{html_path(fallback)}\"#{img_attrs}>"
      html << "</picture>"

      html
    end

    # Generate <img> element with data-* attributes for lazy loading
    def generate_data_img_element
      img_attrs = build_data_img_attributes
      primary = @results.first

      # Build data-srcset if multiple results
      srcset_attr = if @results.length > 1
                      srcset = generate_srcset_string(@results)
                      " data-srcset=\"#{srcset}\""
                    else
                      ""
                    end

      "<img data-src=\"#{html_path(primary)}\"#{srcset_attr}#{img_attrs}>"
    end

    # Generate just the URL (for direct_url format)
    def generate_direct_url
      absolute_url(@results.first)
    end

    # Generate just the srcset string (for naked_srcset format)
    def generate_naked_srcset
      generate_srcset_string(@results)
    end

    # Build img attributes including alt, loading, and custom attributes
    def build_img_attributes
      attrs = @attributes[:img].dup
      attrs["alt"] = @attributes[:alt] if @attributes[:alt]
      attrs["loading"] = "lazy" unless attrs["loading"]

      build_attributes(attrs)
    end

    # Build img attributes with data-* for lazy loading
    def build_data_img_attributes
      attrs = @attributes[:img].dup
      attrs["alt"] = @attributes[:alt] if @attributes[:alt]
      attrs["class"] = [attrs["class"], "lazy"].compact.join(" ")

      build_attributes(attrs)
    end

    # Build HTML attribute string from hash
    def build_attributes(attrs_hash)
      return "" if attrs_hash.nil? || attrs_hash.empty?

      attrs_hash.filter_map do |key, value|
        if value.is_a?(TrueClass)
          " #{escape_attr_name(key)}" # Boolean attribute
        elsif value.is_a?(FalseClass) || value.nil?
          nil # Skip false/nil attributes
        else
          " #{escape_attr_name(key)}=\"#{escape_attr_value(value)}\""
        end
      end.join
    end

    # Wrap HTML in anchor tag
    def wrap_with_link(html)
      link_attrs = build_attributes(@attributes[:a])
      href = escape_attr_value(@attributes[:link])

      "<a href=\"#{href}\"#{link_attrs}>#{html}</a>"
    end

    # Wrap HTML in parent container
    def wrap_with_parent(html)
      parent_attrs = build_attributes(@attributes[:parent])

      "<div#{parent_attrs}>#{html}</div>"
    end

    # Group results by file extension, ordered by config format priority
    # (avif → webp → png → jpg). The browser picks the first <source> format
    # it supports, so the order of <source> tags determines format priority.
    def group_by_format(results)
      grouped = results.group_by { |r| File.extname(r).downcase }
      sort_format_groups(grouped)
    end

    # Sort format groups by config format priority (first = highest priority).
    # Formats not in config.formats are appended at the end alphabetically.
    def sort_format_groups(grouped)
      priority = build_format_priority
      grouped.sort_by { |ext, _| priority.index(ext) || Float::INFINITY }
    end

    # Build a lookup of format extensions ordered by config.formats priority.
    # E.g. ["avif", "webp", "png", "jpg"] → [".avif", ".webp", ".png", ".jpg"]
    def build_format_priority
      return %w[.avif .webp .png .jpg] unless @config&.formats

      @config.formats.map { |fmt| ".#{fmt.downcase}" }
    end

    # Find fallback image — prefer the configured fallback format,
    # then any legacy format (jpg/jpeg/png), then first result.
    def find_fallback_image(results)
      return results.first if results.empty?

      preferred = @config&.fallback_format
      if preferred
        found = results.find { |r| r.end_with?(".#{preferred}") }
        return found if found
      end

      results.find { |r| r.match?(/\.(jpe?g|png)$/i) } || results.first
    end

    # Generate srcset string from results
    def generate_srcset_string(results)
      results.map do |result|
        width = extract_width_from_filename(result)
        descriptor = width ? "#{width}w" : "1x"
        "#{absolute_url(result)} #{descriptor}"
      end.join(", ")
    end

    # Extract width from filename (format: base_name-width-hash.format)
    def extract_width_from_filename(result)
      filename = File.basename(result, ".*")
      match = filename.match(/-(\d+)-[a-f0-9]+$/)
      match ? match[1].to_i : nil
    end

    # Get MIME type for file extension
    def mime_type_for(ext)
      case ext.downcase
      when ".webp"
        "image/webp"
      when ".avif"
        "image/avif"
      when ".jp2"
        "image/jp2"
      when ".jxr"
        "image/jxr"
      when ".png"
        "image/png"
      when ".svg"
        "image/svg+xml"
      when ".gif"
        "image/gif"
      else
        "image/jpeg" # .jpg, .jpeg, and default
      end
    end

    # Escape HTML attribute name
    def escape_attr_name(name)
      name.to_s.gsub(/[^a-zA-Z0-9\-_:]/, "")
    end

    # Escape HTML attribute value
    def escape_attr_value(value)
      value.to_s
           .gsub("&", "&amp;")
           .gsub('"', "&quot;")
           .gsub("'", "&#39;")
           .gsub("<", "&lt;")
           .gsub(">", "&gt;")
    end

    # Get correct path for HTML generation (relative paths for Jekyll sites)
    def html_path(relative_path)
      # For HTML generation, we want relative paths within the site
      # Remove leading slash to make it relative to site root
      relative_path.start_with?("/") ? relative_path[1..] : relative_path
    end

    # Get absolute URL when needed (for direct_url format)
    def absolute_url(relative_path)
      return relative_path unless @context && @context.registers[:site]

      site = @context.registers[:site]
      base_url = site.config["url"] || "http://localhost:4000"
      baseurl = site.config["baseurl"] || ""

      # Ensure base_url ends without trailing slash and baseurl starts without slash
      base_url = base_url.chomp("/")
      baseurl = baseurl[1..] if baseurl.start_with?("/")

      # Build URL parts carefully to avoid double slashes
      url_parts = [base_url]
      url_parts << baseurl unless baseurl.empty?
      url_parts << html_path(relative_path)

      url_parts.join("/")
    end
  end
end
