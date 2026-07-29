# frozen_string_literal: true

require "digest"
require "json"

module JekyllImgFlow
  # Generates unique filenames for processed images
  # Compatible with Jekyll Picture Tag format
  class FilenameGenerator
    # Generate filename for processed image (Jekyll Picture Tag compatible)
    # @param original_name [String] Original image filename
    # @param operations [Hash] Operations applied to image
    # @return [String] Generated filename (without path)
    def generate_filename(original_name, operations)
      base_name = File.basename(original_name, ".*")
      width = operations[:width]
      format = operations[:format] || File.extname(original_name).delete(".")

      # Generate hash using Jekyll Picture Tag approach
      hash = generate_jpt_hash(original_name, operations)

      "#{base_name}-#{width}-#{hash}.#{format}"
    end

    # Generate cache key for operations (SHA256 for manifest tracking)
    # @param operations [Hash] Operations hash
    # @return [String] Cache key
    def generate_cache_key(operations)
      # Sort keys to ensure consistent hashing
      sorted_operations = operations.sort.to_h
      Digest::SHA256.hexdigest(sorted_operations.to_json)
    end

    # Get file digest for manifest tracking
    # @param original_path [String] Path to original image
    # @return [String] SHA256 digest of file
    def file_digest(original_path)
      Digest::SHA256.file(original_path).hexdigest
    end

    # Parse filename to extract width and hash
    # @param filename [String] Generated filename
    # @return [Hash] Parsed components {base_name, width, hash, format}
    def parse_filename(filename)
      # Parse pattern: basename-width-hash.format - simple string operations
      # Find last dot to separate format
      last_dot = filename.rindex(".")
      return {} unless last_dot

      format = filename[(last_dot + 1)..]
      name_part = filename[0...last_dot]

      # Find last dash to separate hash
      last_dash = name_part.rindex("-")
      return {} unless last_dash

      hash = name_part[(last_dash + 1)..]
      name_without_hash = name_part[0...last_dash]

      # Find second-to-last dash to separate width
      second_last_dash = name_without_hash.rindex("-")
      return {} unless second_last_dash

      width_str = name_without_hash[(second_last_dash + 1)..]
      base_name = name_without_hash[0...second_last_dash]

      # Validate components
      return {} unless hash.match?(/^[a-f0-9]+$/)
      return {} unless width_str.match?(/^\d+$/)

      {
        base_name: base_name,
        width: width_str.to_i,
        hash: hash,
        format: format
      }
    end

    private

    # Generate hash using Jekyll Picture Tag approach
    # @param original_path [String] Path to original image (relative or absolute)
    # @param operations [Hash] Operations hash
    # @return [String] 9-character MD5 hash
    def generate_jpt_hash(original_path, operations)
      # Get filename digest (MD5 of filename) - exactly like JPT
      filename = File.basename(original_path)
      file_digest = Digest::MD5.hexdigest(filename)

      # Build settings array (like Jekyll Picture Tag)
      settings = [
        file_digest,
        operations[:crop],
        operations[:keep],
        operations[:quality]
      ]

      # Generate MD5 hash of settings (9 chars like JPT)
      Digest::MD5.hexdigest(settings.join)[0..8]
    end
  end
end
