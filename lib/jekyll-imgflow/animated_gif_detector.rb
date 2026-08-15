# frozen_string_literal: true

module JekyllImgFlow
  # Detects whether a GIF file is animated (contains multiple frames)
  #
  # Animated GIFs must not be resized or format-converted because the
  # operation would destroy the animation. This class parses the GIF
  # binary format and counts Image Descriptor blocks to determine
  # whether more than one frame is present.
  class AnimatedGifDetector
    # GIF block introducer bytes
    EXTENSION_INTRODUCER = 0x21
    IMAGE_DESCRIPTOR = 0x2C
    TRAILER = 0x3B

    # Check whether the file at +path+ is an animated GIF.
    #
    # @param path [String] Path to the image file
    # @return [Boolean] true if the file is a GIF with more than one frame
    def self.animated?(path)
      new(path).animated?
    end

    # @param path [String] Path to the image file
    def initialize(path)
      @path = path
    end

    def animated?
      return false unless gif?

      frame_count > 1
    end

    private

    def gif?
      return false unless File.exist?(@path)

      magic = File.binread(@path, 6)
      %w[GIF87a GIF89a].include?(magic)
    rescue StandardError
      false
    end

    # Count the number of Image Descriptor (0x2C) blocks in the GIF.
    # Each Image Descriptor marks the start of a frame.
    # @return [Integer] Number of frames found
    def frame_count
      data = File.binread(@path)
      reader = GifReader.new(data)

      reader.skip_header_and_global_color_table
      reader.count_image_descriptors
    end

    # Minimal forward-only GIF block reader.
    # Walks the block structure to locate Image Descriptor markers
    # without misinterpreting bytes that appear inside compressed data.
    class GifReader
      def initialize(data)
        @data = data
        @pos = 0
      end

      # Advance past the GIF header + Logical Screen Descriptor and
      # the optional Global Color Table.
      def skip_header_and_global_color_table
        # Signature (3) + Version (3) already validated by caller;
        # skip to Logical Screen Descriptor packed byte.
        @pos = 10 # 6 (magic) + 4 (width/height)
        packed = @data.getbyte(@pos)
        @pos += 1 # consume packed byte

        global_color_table_flag = packed.anybits?(0x80)
        return unless global_color_table_flag

        size_of_global_color_table = packed & 0x07
        table_size = 3 * (2**(size_of_global_color_table + 1))
        @pos += table_size
      end

      # Walk remaining blocks, counting Image Descriptors.
      # @return [Integer] frame count
      def count_image_descriptors
        count = 0

        while @pos < @data.length
          introducer = @data.getbyte(@pos)

          case introducer
          when IMAGE_DESCRIPTOR
            count += 1
            skip_image_data
          when EXTENSION_INTRODUCER
            skip_extension
          when TRAILER
            break
          else
            # Unknown block — advance one byte to avoid infinite loop
            @pos += 1
          end
        end

        count
      end

      private

      # Skip an Image Descriptor block + its Local Color Table +
      # the LZW-compressed image data sub-blocks.
      def skip_image_data
        # Image Descriptor is 10 bytes (introducer + 9)
        @pos += 10

        packed = @data.getbyte(@pos - 1)
        local_color_table_flag = packed.anybits?(0x80)

        if local_color_table_flag
          size_of_local_color_table = packed & 0x07
          table_size = 3 * (2**(size_of_local_color_table + 1))
          @pos += table_size
        end

        # LZW Minimum Code Size (1 byte)
        @pos += 1

        skip_sub_blocks
      end

      # Skip an Extension block (0x21 + label + sub-blocks).
      def skip_extension
        @pos += 2 # introducer + label
        skip_sub_blocks
      end

      # Skip a sequence of sub-blocks: each starts with a size byte
      # (1-255) followed by that many data bytes. A size of 0
      # terminates the sequence.
      def skip_sub_blocks
        loop do
          break if @pos >= @data.length

          size = @data.getbyte(@pos)
          @pos += 1
          break if size.zero?

          @pos += size
        end
      end
    end

    private_constant :GifReader
  end
end
