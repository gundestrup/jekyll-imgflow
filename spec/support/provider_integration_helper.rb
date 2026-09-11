# frozen_string_literal: true

require "json"
require "open3"

module ProviderIntegrationHelper
  # SVG files with large viewBox dimensions can cause slow processing in
  # ImageMagick (its internal SVG parser is very slow without the rsvg
  # delegate). Other providers (weserv via librsvg, sharp, libvips) handle
  # SVGs correctly — the weserv provider adds a default max size for SVGs
  # without explicit dimensions (see SVG_DEFAULT_MAX_SIZE).
  SLOW_INPUT_FORMAT_EXCLUSIONS = {
    "imagemagick" => %w[svg]
  }.freeze

  def test_images_for_provider(provider_name, set: nil)
    set ||= ENV.fetch("IMGFLOW_TEST_PICTURES", "all").to_sym
    images = TestPictures.get(set)
    provider = provider_name.to_s.downcase
    excluded_formats = SLOW_INPUT_FORMAT_EXCLUSIONS.fetch(provider, [])
    excluded_formats -= ["svg"] if ENV["FULL_SVG_TEST"] == "true"
    return images if excluded_formats.empty?

    skipped = images.count do |image|
      excluded_formats.include?(File.extname(image).delete_prefix("."))
    end
    if skipped.positive?
      Jekyll.logger.info "ImgFlow Test:",
                         "Skipping #{skipped} input file(s) for #{provider_name}: " \
                         "#{excluded_formats.join(', ')} " \
                         "(use FULL_SVG_TEST=true to include SVG)."
    end
    images.reject do |image|
      excluded_formats.include?(File.extname(image).delete_prefix("."))
    end
  end

  def provider_available_for_test?(provider_name)
    config = JekyllImgFlow::Config.new(MockSite.new(TEST_CONFIG))
    provider = JekyllImgFlow::ProviderRegistry.new(config).providers.find do |candidate|
      candidate.class.name.split("::").last.downcase == provider_name.to_s.downcase
    end
    provider&.available? || false
  end

  def scaffold_provider_test_site(site_dir, provider_name, images = nil, **options)
    images ||= test_images_for_provider(provider_name)
    create_test_jekyll_site(site_dir, :imgflow_only,
                            options.merge(
                              test_images: images,
                              backend_priority: [provider_name],
                              test_output_format: "webp",
                              url: TestEnvironment.site_url(provider: provider_name),
                              title: "Provider Real-World Test - #{provider_name}"
                            ))
  end

  def build_provider_test_site(site_dir, provider_name = nil, allow_failure: false)
    stdout, stderr, status = Dir.chdir(site_dir) do
      Open3.capture3("bundle exec jekyll build --trace")
    end
    output = stdout + stderr

    failed = !status.success? || output.include?("❌ Failed:")
    return status if allow_failure || !failed

    provider = provider_name ? " for #{provider_name}" : ""
    details = output.lines.last(20).join
    raise "Jekyll build failed#{provider} in #{site_dir}\n#{details}"
  end

  def optimized_files_for(site_dir)
    output = JekyllImgFlow::Config.new(MockSite.new(TEST_CONFIG)).output
    output_dir = File.join(site_dir, "_site", output)
    return [] unless Dir.exist?(output_dir)

    Dir.glob(File.join(output_dir, "**", "*")).select { |file| File.file?(file) }
  end

  def manifest_path_for(site_dir)
    config = JekyllImgFlow::Config.new(MockSite.new(TEST_CONFIG))
    File.join(site_dir, config.cache_dir, "imgflow-manifest.json")
  end

  def manifest_data_for(site_dir)
    path = manifest_path_for(site_dir)
    File.exist?(path) ? JSON.parse(File.read(path)) : {}
  end

  def expected_filenames_for(image_name)
    config = JekyllImgFlow::Config.new(MockSite.new(TEST_CONFIG))
    config.sizes.each_key.filter_map do |size_name|
      config.formats.filter_map do |format|
        TestPictures.expected_filename(image_name, size_name, format)
      end
    end.flatten
  end

  def validate_jpt_hash_patterns(filenames)
    filenames.each do |filename|
      basename = File.basename(filename)
      parts = basename.match(/\A(.+)-(?:(\d+)-)?([a-f0-9]{9})\.([a-z]+)\z/)
      expect(parts).not_to be_nil, "Could not parse filename pattern: #{basename}"

      image_stem = parts[1].delete_suffix("-")
      hash = parts[3]
      known_image = TestPictures::CATALOG.keys.find do |image_name|
        File.basename(image_name, File.extname(image_name)) == image_stem &&
          TestPictures.hash(image_name) == hash
      end
      next if known_image

      expect(hash).to match(/\A[a-f0-9]{9}\z/)
    end
  end
end
