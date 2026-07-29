# frozen_string_literal: true

# Test Pictures - Centralized test image fixture management
# Provides categorized image sets for different test scenarios
module TestPictures
  # Base fixtures directory
  FIXTURES_DIR = File.join("spec", "fixtures", "originals")

  # Image catalog with metadata
  # Hash calculated using JPT method: MD5([file_digest, crop, keep, quality].join)[0..8]
  # Default quality: 85, crop: nil, keep: nil
  CATALOG = {
    # JPEG images
    "mars-crater-large.jpg" => {
      format: :jpg, size: :large, type: :photo,
      hash: "f33ea0792",
      expected_defaults: {
        sm: { webp: "mars-crater-large-400-f33ea0792.webp",
              avif: "mars-crater-large-400-f33ea0792.avif", jpg: "mars-crater-large-400-f33ea0792.jpg", png: "mars-crater-large-400-f33ea0792.png" },
        md: { webp: "mars-crater-large-800-f33ea0792.webp",
              avif: "mars-crater-large-800-f33ea0792.avif", jpg: "mars-crater-large-800-f33ea0792.jpg", png: "mars-crater-large-800-f33ea0792.png" },
        lg: { webp: "mars-crater-large-1200-f33ea0792.webp",
              avif: "mars-crater-large-1200-f33ea0792.avif", jpg: "mars-crater-large-1200-f33ea0792.jpg", png: "mars-crater-large-1200-f33ea0792.png" },
        xl: { webp: "mars-crater-large-2000-f33ea0792.webp",
              avif: "mars-crater-large-2000-f33ea0792.avif", jpg: "mars-crater-large-2000-f33ea0792.jpg", png: "mars-crater-large-2000-f33ea0792.png" }
      },
      expected_specialized: {
        # Parser behavior: no quality unless specified (hash: a89ee2bc2)
        sm: { webp: "mars-crater-large-400-a89ee2bc2.webp",
              avif: "mars-crater-large-400-a89ee2bc2.avif", jpg: "mars-crater-large-400-a89ee2bc2.jpg", png: "mars-crater-large-400-a89ee2bc2.png" },
        md: { webp: "mars-crater-large-800-a89ee2bc2.webp",
              avif: "mars-crater-large-800-a89ee2bc2.avif", jpg: "mars-crater-large-800-a89ee2bc2.jpg", png: "mars-crater-large-800-a89ee2bc2.png" },
        lg: { webp: "mars-crater-large-1200-a89ee2bc2.webp",
              avif: "mars-crater-large-1200-a89ee2bc2.avif", jpg: "mars-crater-large-1200-a89ee2bc2.jpg", png: "mars-crater-large-1200-a89ee2bc2.png" },
        xl: { webp: "mars-crater-large-2000-a89ee2bc2.webp",
              avif: "mars-crater-large-2000-a89ee2bc2.avif", jpg: "mars-crater-large-2000-a89ee2bc2.jpg", png: "mars-crater-large-2000-a89ee2bc2.png" }
      }
    },
    "spider_web-large.jpg" => { format: :jpg, size: :large, type: :photo },
    "spider_web-small.jpg" => { format: :jpg, size: :small, type: :photo },
    "artificial-large.jpg" => { format: :jpg, size: :large, type: :artificial },
    "artificial-small.jpg" => { format: :jpg, size: :small, type: :artificial },
    "file_example-large.jpg" => { format: :jpg, size: :large, type: :sample },
    "file_example-small.jpg" => { format: :jpg, size: :small, type: :sample },

    # PNG images
    "file_example-large.png" => {
      format: :png, size: :large, type: :sample,
      hash: "aa4ec6a4c",
      expected_defaults: {
        sm: { webp: "file_example-large-400-aa4ec6a4c.webp",
              avif: "file_example-large-400-aa4ec6a4c.avif", jpg: "file_example-large-400-aa4ec6a4c.jpg", png: "file_example-large-400-aa4ec6a4c.png" },
        md: { webp: "file_example-large-800-aa4ec6a4c.webp",
              avif: "file_example-large-800-aa4ec6a4c.avif", jpg: "file_example-large-800-aa4ec6a4c.jpg", png: "file_example-large-800-aa4ec6a4c.png" },
        lg: { webp: "file_example-large-1200-aa4ec6a4c.webp",
              avif: "file_example-large-1200-aa4ec6a4c.avif", jpg: "file_example-large-1200-aa4ec6a4c.jpg", png: "file_example-large-1200-aa4ec6a4c.png" },
        xl: { webp: "file_example-large-2000-aa4ec6a4c.webp",
              avif: "file_example-large-2000-aa4ec6a4c.avif", jpg: "file_example-large-2000-aa4ec6a4c.jpg", png: "file_example-large-2000-aa4ec6a4c.png" }
      },
      expected_specialized: {
        # Parser behavior: no quality unless specified (hash: 9d454e8d2)
        sm: { webp: "file_example-large-400-9d454e8d2.webp",
              avif: "file_example-large-400-9d454e8d2.avif", jpg: "file_example-large-400-9d454e8d2.jpg", png: "file_example-large-400-9d454e8d2.png" },
        md: { webp: "file_example-large-800-9d454e8d2.webp",
              avif: "file_example-large-800-9d454e8d2.avif", jpg: "file_example-large-800-9d454e8d2.jpg", png: "file_example-large-800-9d454e8d2.png" },
        lg: { webp: "file_example-large-1200-9d454e8d2.webp",
              avif: "file_example-large-1200-9d454e8d2.avif", jpg: "file_example-large-1200-9d454e8d2.jpg", png: "file_example-large-1200-9d454e8d2.png" },
        xl: { webp: "file_example-large-2000-9d454e8d2.webp",
              avif: "file_example-large-2000-9d454e8d2.avif", jpg: "file_example-large-2000-9d454e8d2.jpg", png: "file_example-large-2000-9d454e8d2.png" }
      }
    },
    "file_example-small.png" => { format: :png, size: :small, type: :sample },

    # WebP images
    "file_example-large.webp" => {
      format: :webp, size: :large, type: :sample,
      hash: "036a28acb",
      expected_defaults: {
        sm: { webp: "file_example-large-400-036a28acb.webp",
              avif: "file_example-large-400-036a28acb.avif", jpg: "file_example-large-400-036a28acb.jpg", png: "file_example-large-400-036a28acb.png" },
        md: { webp: "file_example-large-800-036a28acb.webp",
              avif: "file_example-large-800-036a28acb.avif", jpg: "file_example-large-800-036a28acb.jpg", png: "file_example-large-800-036a28acb.png" },
        lg: { webp: "file_example-large-1200-036a28acb.webp",
              avif: "file_example-large-1200-036a28acb.avif", jpg: "file_example-large-1200-036a28acb.jpg", png: "file_example-large-1200-036a28acb.png" },
        xl: { webp: "file_example-large-2000-036a28acb.webp",
              avif: "file_example-large-2000-036a28acb.avif", jpg: "file_example-large-2000-036a28acb.jpg", png: "file_example-large-2000-036a28acb.png" }
      },
      expected_specialized: {
        # Parser behavior: no quality unless specified (hash: 1b28aa612)
        sm: { webp: "file_example-large-400-1b28aa612.webp",
              avif: "file_example-large-400-1b28aa612.avif", jpg: "file_example-large-400-1b28aa612.jpg", png: "file_example-large-400-1b28aa612.png" },
        md: { webp: "file_example-large-800-1b28aa612.webp",
              avif: "file_example-large-800-1b28aa612.avif", jpg: "file_example-large-800-1b28aa612.jpg", png: "file_example-large-800-1b28aa612.png" },
        lg: { webp: "file_example-large-1200-1b28aa612.webp",
              avif: "file_example-large-1200-1b28aa612.avif", jpg: "file_example-large-1200-1b28aa612.jpg", png: "file_example-large-1200-1b28aa612.png" },
        xl: { webp: "file_example-large-2000-1b28aa612.webp",
              avif: "file_example-large-2000-1b28aa612.avif", jpg: "file_example-large-2000-1b28aa612.jpg", png: "file_example-large-2000-1b28aa612.png" }
      }
    },
    "file_example-medium.webp" => { format: :webp, size: :medium, type: :sample },
    "file_example-small.webp" => { format: :webp, size: :small, type: :sample },

    # TIFF images
    "file_example-large.tiff" => {
      format: :tiff, size: :large, type: :sample,
      hash: "17854b3ca",
      expected_defaults: {
        sm: { webp: "file_example-large-400-17854b3ca.webp",
              avif: "file_example-large-400-17854b3ca.avif", jpg: "file_example-large-400-17854b3ca.jpg", png: "file_example-large-400-17854b3ca.png" },
        md: { webp: "file_example-large-800-17854b3ca.webp",
              avif: "file_example-large-800-17854b3ca.avif", jpg: "file_example-large-800-17854b3ca.jpg", png: "file_example-large-800-17854b3ca.png" },
        lg: { webp: "file_example-large-1200-17854b3ca.webp",
              avif: "file_example-large-1200-17854b3ca.avif", jpg: "file_example-large-1200-17854b3ca.jpg", png: "file_example-large-1200-17854b3ca.png" },
        xl: { webp: "file_example-large-2000-17854b3ca.webp",
              avif: "file_example-large-2000-17854b3ca.avif", jpg: "file_example-large-2000-17854b3ca.jpg", png: "file_example-large-2000-17854b3ca.png" }
      }
    },
    "file_example-medium.tiff" => { format: :tiff, size: :medium, type: :sample },
    "file_example-small.tiff" => { format: :tiff, size: :small, type: :sample },

    # AVIF images
    "ayousef-espanioly.avif" => {
      format: :avif, size: :medium, type: :photo,
      hash: "ea7fb3a40",
      expected_defaults: {
        sm: { webp: "ayousef-espanioly-400-ea7fb3a40.webp",
              avif: "ayousef-espanioly-400-ea7fb3a40.avif", jpg: "ayousef-espanioly-400-ea7fb3a40.jpg", png: "ayousef-espanioly-400-ea7fb3a40.png" },
        md: { webp: "ayousef-espanioly-800-ea7fb3a40.webp",
              avif: "ayousef-espanioly-800-ea7fb3a40.avif", jpg: "ayousef-espanioly-800-ea7fb3a40.jpg", png: "ayousef-espanioly-800-ea7fb3a40.png" },
        lg: { webp: "ayousef-espanioly-1200-ea7fb3a40.webp",
              avif: "ayousef-espanioly-1200-ea7fb3a40.avif", jpg: "ayousef-espanioly-1200-ea7fb3a40.jpg", png: "ayousef-espanioly-1200-ea7fb3a40.png" },
        xl: { webp: "ayousef-espanioly-2000-ea7fb3a40.webp",
              avif: "ayousef-espanioly-2000-ea7fb3a40.avif", jpg: "ayousef-espanioly-2000-ea7fb3a40.jpg", png: "ayousef-espanioly-2000-ea7fb3a40.png" }
      }
    },
    "parrot-avif.avif" => { format: :avif, size: :small, type: :photo },

    # SVG images
    "file_example-medium.svg" => {
      format: :svg, size: :medium, type: :vector,
      hash: "adb860343",
      expected_defaults: {
        sm: { webp: "file_example-medium-400-adb860343.webp",
              avif: "file_example-medium-400-adb860343.avif", jpg: "file_example-medium-400-adb860343.jpg", png: "file_example-medium-400-adb860343.png" },
        md: { webp: "file_example-medium-800-adb860343.webp",
              avif: "file_example-medium-800-adb860343.avif", jpg: "file_example-medium-800-adb860343.jpg", png: "file_example-medium-800-adb860343.png" },
        lg: { webp: "file_example-medium-1200-adb860343.webp",
              avif: "file_example-medium-1200-adb860343.avif", jpg: "file_example-medium-1200-adb860343.jpg", png: "file_example-medium-1200-adb860343.png" },
        xl: { webp: "file_example-medium-2000-adb860343.webp",
              avif: "file_example-medium-2000-adb860343.avif", jpg: "file_example-medium-2000-adb860343.jpg", png: "file_example-medium-2000-adb860343.png" }
      }
    },
    "file_example-small.svg" => { format: :svg, size: :small, type: :vector }
  }.freeze

  # Predefined image sets for different test scenarios
  SETS = {
    # Default set - fast, reliable test images
    default: ["mars-crater-large.jpg"],

    # Small default - smallest reliable test image
    default_small: ["spider_web-small.jpg"],

    # Multi-format default - one of each common format
    default_multi: [
      "mars-crater-large.jpg",
      "file_example-large.png",
      "file_example-large.webp",
      "file_example-large.tiff",
      "ayousef-espanioly.avif",
      "file_example-medium.svg"
    ],

    # Format-specific sets
    jpg: -> { CATALOG.select { |_, meta| meta[:format] == :jpg }.keys },
    png: -> { CATALOG.select { |_, meta| meta[:format] == :png }.keys },
    webp: -> { CATALOG.select { |_, meta| meta[:format] == :webp }.keys },
    tiff: -> { CATALOG.select { |_, meta| meta[:format] == :tiff }.keys },
    avif: -> { CATALOG.select { |_, meta| meta[:format] == :avif }.keys },
    svg: -> { CATALOG.select { |_, meta| meta[:format] == :svg }.keys },

    # Size-specific sets (one of each format)
    small: lambda {
      CATALOG.select { |_, meta| meta[:size] == :small }
             .group_by { |_, meta| meta[:format] }
             .map { |_, images| images.first[0] }
    },
    medium: lambda {
      CATALOG.select { |_, meta| meta[:size] == :medium }
             .group_by { |_, meta| meta[:format] }
             .map { |_, images| images.first[0] }
    },
    large: lambda {
      CATALOG.select { |_, meta| meta[:size] == :large }
             .group_by { |_, meta| meta[:format] }
             .map { |_, images| images.first[0] }
    },

    # All images
    all: -> { CATALOG.keys },

    # Quick test set - minimal images for fast tests (one of each format)
    quick: [
      "mars-crater-large.jpg",
      "file_example-large.png",
      "file_example-large.webp",
      "file_example-large.tiff",
      "ayousef-espanioly.avif",
      "file_example-medium.svg"
    ],

    # Full test set - comprehensive format coverage
    full: lambda {
      full_formats = %i[jpg png webp tiff avif]
      CATALOG.select { |_, meta| full_formats.include?(meta[:format]) }
             .keys
    }
  }.freeze

  # Get images for a specific set
  # @param set_name [Symbol] Name of the image set
  # @return [Array<String>] Array of image filenames
  def self.get(set_name = :default)
    set = SETS[set_name]
    return [] unless set

    # Handle lambda sets (dynamic)
    images = set.is_a?(Proc) ? set.call : set

    # Filter to only existing files
    images.select { |img| File.exist?(File.join(FIXTURES_DIR, img)) }
  end

  # Get metadata for an image
  # @param filename [String] Image filename
  # @return [Hash] Metadata hash
  def self.metadata(filename)
    CATALOG[filename] || {}
  end

  # Get test mode from environment variable
  # @return [Symbol] Test mode (:quick, :full, or custom set name)
  def self.test_mode
    mode = ENV["TEST_PICTURES"] || ENV["TEST_MODE"] || "default"
    mode.to_sym
  end

  # Get images for current test mode
  # @return [Array<String>] Array of image filenames
  def self.for_test
    get(test_mode)
  end

  # Check if an image exists in fixtures
  # @param filename [String] Image filename
  # @return [Boolean] True if image exists
  def self.exists?(filename)
    File.exist?(File.join(FIXTURES_DIR, filename))
  end

  # Get full path to fixture image
  # @param filename [String] Image filename
  # @return [String] Full path to image
  def self.path(filename)
    File.join(FIXTURES_DIR, filename)
  end

  # List all available sets
  # @return [Array<Symbol>] Array of set names
  def self.available_sets
    SETS.keys
  end

  # Get images by format
  # @param format [Symbol] Format symbol (:jpg, :png, etc.)
  # @return [Array<String>] Array of image filenames
  def self.by_format(format)
    CATALOG.select { |_, meta| meta[:format] == format }.keys
  end

  # Get images by size
  # @param size [Symbol] Size symbol (:small, :medium, :large)
  # @return [Array<String>] Array of image filenames
  def self.by_size(size)
    CATALOG.select { |_, meta| meta[:size] == size }.keys
  end

  # Get expected filename for a specific size and format
  # @param image_name [String] Image filename
  # @param size [Symbol] Size symbol (:sm, :md, :lg, :xl)
  # @param format [Symbol, String] Format symbol (:webp, :avif, :jpg, :png)
  # @return [String, nil] Expected filename or nil if not found
  def self.expected_filename(image_name, size, format)
    meta = CATALOG[image_name]
    return unless meta && meta[:expected_defaults]

    meta[:expected_defaults].dig(size, format.to_sym)
  end

  # Get specialized filename for parser behavior (no quality unless specified)
  # @param image_name [String] Image filename
  # @param size [Symbol] Size symbol (:sm, :md, :lg, :xl)
  # @param format [Symbol, String] Format symbol (:webp, :avif, :jpg, :png)
  # @return [String, nil] Expected specialized filename or nil if not found
  def self.specialized_filename(image_name, size, format)
    meta = CATALOG[image_name]
    return unless meta && meta[:expected_specialized]

    meta[:expected_specialized].dig(size, format.to_sym)
  end

  # Get all expected filenames for an image
  # @param image_name [String] Image filename
  # @param size [Symbol, nil] Optional size filter
  # @param format [Symbol, nil] Optional format filter
  # @return [Hash, String, nil] Hash of expected filenames or single filename
  def self.expected_defaults(image_name, size = nil, format = nil)
    meta = CATALOG[image_name]
    return {} unless meta && meta[:expected_defaults]

    if size && format
      meta[:expected_defaults].dig(size, format.to_sym)
    elsif size
      meta[:expected_defaults][size] || {}
    else
      meta[:expected_defaults]
    end
  end

  # Get expected output path for a filename
  # @param image_name [String] Image filename
  # @param size [Symbol] Size symbol
  # @param format [Symbol, String] Format symbol
  # @param output_dir [String] Output directory path (default: assets/images/optimized)
  # @return [String, nil] Expected output path
  def self.expected_output_path(image_name, size, format, output_dir = "assets/images/optimized")
    filename = expected_filename(image_name, size, format)
    return unless filename

    File.join(output_dir, filename)
  end

  # Generate mock completed tasks for testing
  # @param image_name [String] Image filename
  # @param sizes [Array<Symbol>] Sizes to include (default: [:sm, :md])
  # @param formats [Array<Symbol>] Formats to include (default: [:webp, :avif])
  # @param output_dir [String] Output directory path
  # @return [Array<Hash>] Array of mock completed task hashes
  def self.mock_completed_tasks(image_name, sizes: %i[sm md], formats: %i[webp avif],
                                output_dir: "/assets/images/optimized")
    tasks = []
    meta = CATALOG[image_name]
    return tasks unless meta && meta[:expected_defaults]

    sizes.each do |size|
      formats.each do |format|
        filename = expected_filename(image_name, size, format)
        next unless filename

        # Size values from config
        width = case size
                when :sm then 400
                when :lg then 1200
                when :xl then 2000
                else 800
                end

        tasks << {
          task: {
            original_name: image_name,
            params: { size: size, format: format, width: width }
          },
          result: File.join(output_dir, filename)
        }
      end
    end

    tasks
  end

  # Get hash for an image (for testing filename generation)
  # @param image_name [String] Image filename
  # @return [String, nil] Hash string or nil
  def self.hash(image_name)
    meta = CATALOG[image_name]
    meta ? meta[:hash] : nil
  end
end
