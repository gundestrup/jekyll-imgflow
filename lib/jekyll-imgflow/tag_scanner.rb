# frozen_string_literal: true

module JekyllImgFlow
  # Scans Jekyll content for {% imgflow %} and {% picture %} tags
  # Uses ManifestManager as single source of truth
  class TagScanner
    def initialize(site, config, manifest = nil)
      @site = site
      @config = config
      @manifest = manifest
    end

    # Scan all content files for image tags
    # Returns summary from ManifestManager instead of building own hash
    def scan_all_content
      # Scan posts, pages, and documents
      scannable_content.each do |item|
        scan_content_item(item)
      end

      # Return manifest summary if available, otherwise empty hash
      @manifest ? @manifest.get_all_versions : {}
    end

    # Scan a single content item
    # Note: With ManifestManager as single source of truth, this just discovers tags
    # Actual tracking happens in ManifestManager during ImgflowTag rendering
    def scan_content_item(item)
      content = item.content

      # Define tag patterns to scan for
      tag_patterns = {
        "imgflow" => "{% imgflow",
        "picture" => "{% picture"
      }

      # Use reusable scanner - just for discovery/validation
      scan_tags_from_content(content, tag_patterns) do |_tag_name, markup|
        # Tags are discovered but not tracked here
        # ManifestManager handles all tracking during actual rendering
      end

      nil # No longer returns requirements hash
    end

    # Scan raw content string and return array of tag info (for testing/direct use)
    def scan_content(content)
      tags = []

      # Define tag patterns to scan for
      tag_patterns = {
        "imgflow" => "{% imgflow"
      }

      # Use reusable scanner
      scan_tags_from_content(content, tag_patterns) do |_tag_name, markup|
        parsed = parse_tag_markup_simple(markup)
        tags << parsed
      end

      tags
    end

    # Find all imgflow tags in content
    def find_imgflow_tags(content)
      scan_content(content)
    end

    # Find all picture tags in content
    def find_picture_tags(content)
      tags = []

      # Define tag patterns to scan for
      tag_patterns = {
        "picture" => "{% picture"
      }

      # Use reusable scanner
      scan_tags_from_content(content, tag_patterns) do |_tag_name, markup|
        parsed = parse_tag_markup_simple(markup)
        tags << parsed
      end

      tags
    end

    # Extract operations from tag markup - returns raw strings only
    def extract_operations(markup)
      parsed = parse_tag_markup_simple(markup)
      parsed[:operations] # Just return array of ["width:800", "quality:90"]
    end

    # Determine if operations represent default or specialized version
    def determine_version_type(operations)
      determine_type(operations)
    end

    # Generic tag scanner - eliminates duplication
    def scan_tags_from_content(content, tag_patterns)
      content_lines = content.split("\n")
      content_lines.each do |line|
        tag_patterns.each do |tag_name, tag_prefix|
          next unless line.include?(tag_prefix)

          markup = extract_markup_from_line(line, tag_prefix)
          yield tag_name, markup if markup
        end
      end
    end

    # Extract markup from line - reusable method
    def extract_markup_from_line(line, tag_prefix)
      start_idx = line.index(tag_prefix)
      return unless start_idx

      start_idx += tag_prefix.length
      end_idx = line.index("%}", start_idx)
      return unless start_idx && end_idx

      line[start_idx..(end_idx - 1)].strip
    end

    # Simple parsing without regex gymnastics
    def parse_tag_markup_simple(markup)
      # Split by whitespace first to get image path
      parts = markup.split(/\s+/)
      image_path = parts.shift

      # Parse operations as key:value pairs separated by commas or spaces
      operations = []
      remaining = parts.join(" ")

      # Handle comma-separated: key:value,key:value
      operation_pairs = if remaining.include?(",")
                          remaining.split(",")
                        else
                          # Handle space-separated: key:value key:value
                          remaining.split(/\s+/)
                        end

      operation_pairs.each do |pair|
        next if pair.empty?

        next unless pair.include?(":")

        key, value = pair.split(":", 2)
        # Convert numeric values using simple string methods
        value_stripped = value.strip
        converted_value = if value_stripped.match?(/^\d+$/)
                            value_stripped.to_i
                          elsif value_stripped.match?(/^\d+\.\d+$/)
                            value_stripped.to_f
                          else
                            value_stripped
                          end
        # Store with converted value for downstream type correctness
        operations << "#{key.strip}:#{converted_value}"
      end

      {
        image: image_path, # Use :image key for test compatibility
        operations: operations # Return as array of strings
      }
    end

    private

    # Get all scannable content from site
    def scannable_content
      items = []
      items.concat(@site.posts.docs) if @site.posts
      items.concat(@site.pages)

      # Add documents from collections
      @site.collections.each_value do |collection|
        items.concat(collection.docs)
      end

      items
    end

    # NOTE: process_tag removed - ManifestManager handles all tracking
    # Tags are discovered during scanning but tracking happens during rendering

    def parse_tag_markup(markup)
      parts = markup.split(/\s+/)
      image_path = parts.shift
      operations = {}

      parts.each do |part|
        next unless part.include?(":")

        key, value = part.split(":", 2)
        operations[key.to_sym] = parse_value(value)
      end

      {
        image_path: image_path,
        operations: operations
      }
    end

    def parse_value(value)
      value = value.tr("'\"", "")
      return value.to_i if value.match?(/^\d+$/)
      return value.to_f if value.match?(/^\d+\.\d+$/)

      value
    end

    # Determine if operations match default configuration
    def determine_type(operations)
      # Check if operations match any default size + format combination
      default_sizes = @config.sizes.values
      default_formats = @config.formats

      # If width matches a default size and format is default, it's default type
      return "default" if operations[:width] && default_sizes.include?(operations[:width]) && (operations[:format].nil? || default_formats.include?(operations[:format]))

      # If only format is specified and it's a default format, it's default
      return "default" if operations.keys == [:format] && default_formats.include?(operations[:format])

      # Otherwise, it's specialized
      "specialized"
    end
  end
end
