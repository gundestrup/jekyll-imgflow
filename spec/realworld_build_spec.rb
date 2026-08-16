# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "yaml"
require "json"

# End-to-end Jekyll build test using real-world fixture images.
#
# Regression test for v0.1.6 bug where optimized images were written directly
# into _site/ and then wiped by Jekyll's site reset on the next build. The fix
# (v0.1.7) writes optimized images to the source directory so Jekyll copies them
# into _site/ during its normal write phase.
#
# This test builds a real Jekyll site with the plugin, runs `jekyll build`
# twice, and verifies that optimized images survive in _site/ across rebuilds.
#
# Tagged :slow so it is excluded from the default run (see .rspec ~slow).
# Run explicitly with:
#   bundle exec rspec spec/realworld_build_spec.rb --tag slow

# Use the pictures/109th subdir: 12 images (6 JPG, 6 GIF, 1 animated GIF).
# Exercises nested originals discovery, multiple formats, and animated GIF skip.
REALWORLD_FIXTURE_DIR =
  File.expand_path("fixtures/realworld/images/pictures/109th", __dir__)

# Reduced sizes/formats to keep the :slow test reasonable (4 versions/image
# instead of 16). backend_priority is left unchanged from the standard config
# so the first available real provider (sharp/imagemagick/libvips/...) is used.
TEST_SIZES = { "sm" => 400, "md" => 800 }.freeze
TEST_FORMATS = %w[webp jpg].freeze

RSpec.describe "Realworld Jekyll build — optimized image placement", :integration, :slow, :system do
  let(:test_site_dir) { create_test_dir("realworld-build") }
  let(:originals_dir) { File.join(test_site_dir, "assets/images/originals") }
  let(:source_optimized_dir) { File.join(test_site_dir, "assets/images/optimized") }
  let(:site_optimized_dir) { File.join(test_site_dir, "_site/assets/images/optimized") }
  let(:manifest_path) { File.join(test_site_dir, "_site/assets/images/imgflow-manifest.json") }
  let(:index_html_path) { File.join(test_site_dir, "_site/index.html") }

  # Check once whether any provider from the standard backend_priority list
  # is available. The test is skipped if none are installed — this keeps it
  # portable across machines and CI environments.
  before(:all) do
    @provider_available = begin
      config = JekyllImgFlow::Config.new(MockSite.new(TEST_CONFIG))
      registry = JekyllImgFlow::ProviderRegistry.new(config)
      !registry.current_provider.nil?
    rescue StandardError
      false
    end
  end

  before do
    unless @provider_available
      skip "No image provider available from backend_priority " \
           "(need sharp/imagemagick/libvips/etc.)"
    end

    scaffold_realworld_site(test_site_dir)
  end

  after do
    FileUtils.rm_rf(test_site_dir)
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  # Build a real Jekyll site: Gemfile, _config.yml (without keep_files:assets
  # so Jekyll fully resets _site on each build — this is what exposed the
  # 0.1.6 bug), nested originals from the 109th fixture dir, and an index
  # page with imgflow tags exercising the runtime path too.
  def scaffold_realworld_site(site_dir)
    FileUtils.mkdir_p(File.join(site_dir, "_layouts"))

    # Copy the 109th subdir preserving nested structure under originals/
    dest_nested = File.join(originals_dir_for(site_dir), "pictures", "109th")
    FileUtils.mkdir_p(dest_nested)
    Dir.glob(File.join(REALWORLD_FIXTURE_DIR, "*")).each do |src|
      FileUtils.cp(src, dest_nested) if File.file?(src)
    end

    # Gemfile — reference the plugin via path so `jekyll build` loads it
    project_root = File.expand_path("../..", __dir__)
    File.write(File.join(site_dir, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "jekyll"
      gem "jekyll-imgflow", path: "#{project_root}"
    GEMFILE

    # _config.yml — standard backend_priority from TEST_CONFIG, reduced
    # sizes/formats for speed. Crucially: NO keep_files so _site is fully
    # reset between builds (the condition that triggered the 0.1.6 bug).
    base_imgflow = TEST_CONFIG["imgflow"].dup
    imgflow_config = {
      "quality" => base_imgflow["quality"],
      "backend_priority" => base_imgflow["backend_priority"],
      "originals" => TEST_CONFIG["shared_images_configs"]["originals"],
      "output" => TEST_CONFIG["shared_images_configs"]["output"],
      "input_formats" => TEST_CONFIG["shared_images_configs"]["input_formats"],
      "sizes" => TEST_SIZES,
      "formats" => TEST_FORMATS
    }
    config = {
      "title" => "Realworld Build Test",
      "url" => "http://localhost:4000",
      "baseurl" => "",
      "source" => ".",
      "destination" => "_site",
      "plugins" => ["jekyll-imgflow"],
      "imgflow" => imgflow_config
    }
    File.write(File.join(site_dir, "_config.yml"), config.to_yaml)

    # Simple layout
    File.write(File.join(site_dir, "_layouts", "default.html"), <<~HTML)
      <!DOCTYPE html>
      <html>
      <head><title>{{ site.title }}</title></head>
      <body>{{ content }}</body>
      </html>
    HTML

    # index.md with imgflow tags referencing nested originals by full path.
    # Avoids the animated GIF (spaces in name + skipped by BuildTimeProcessor).
    File.write(File.join(site_dir, "index.md"), <<~MARKDOWN)
      ---
      layout: default
      ---

      # Realworld Build Test

      {% imgflow assets/images/originals/pictures/109th/raven_cheers.jpg width:800 format:webp %}

      {% imgflow assets/images/originals/pictures/109th/K_loader_SFJ.jpg width:400 format:jpg %}
    MARKDOWN

    # Install gems so `jekyll build` can load the plugin
    Dir.chdir(site_dir) do
      system("bundle install > /dev/null 2>&1")
    end
  end

  def originals_dir_for(site_dir)
    File.join(site_dir, TEST_CONFIG["shared_images_configs"]["originals"])
  end

  def run_jekyll_build(site_dir)
    Dir.chdir(site_dir) do
      system("bundle exec jekyll build --trace")
    end
  end

  def optimized_files_in(dir)
    return [] unless Dir.exist?(dir)

    Dir.glob(File.join(dir, "**", "*")).select { |f| File.file?(f) && !f.end_with?(".json") }
  end

  def all_original_images(site_dir)
    originals = originals_dir_for(site_dir)
    input_formats = TEST_CONFIG["shared_images_configs"]["input_formats"].join(",")
    Dir.glob(File.join(originals, "**", "*.{#{input_formats}}"))
       .reject { |p| JekyllImgFlow::AnimatedGifDetector.animated?(p) }
  end

  # ------------------------------------------------------------------
  # First build
  # ------------------------------------------------------------------

  describe "after the first build" do
    before do
      run_jekyll_build(test_site_dir)
    end

    it "writes optimized images to the SOURCE optimized directory" do
      files = optimized_files_in(source_optimized_dir)
      expect(files).not_to be_empty,
                           "No optimized images written to source #{source_optimized_dir}"
      # At least 2 versions per non-animated image (2 sizes × 2 formats = 4,
      # minus animated GIF which is skipped). 11 non-animated images × 4 = 44.
      expect(files.length).to be >= 4
    end

    it "copies optimized images into _site via Jekyll's write phase" do
      source_files = optimized_files_in(source_optimized_dir).map { |f| File.basename(f) }
      site_files = optimized_files_in(site_optimized_dir).map { |f| File.basename(f) }

      expect(site_files).not_to be_empty,
                                "No optimized images copied to _site #{site_optimized_dir}"
      # Every source-optimized file should also be in _site (Jekyll copied it)
      missing = source_files - site_files
      expect(missing).to be_empty,
                         "Optimized files missing from _site (would be wiped in 0.1.6): #{missing.first(5).join(', ')}"
    end

    it "generates HTML referencing paths that resolve to real files in _site" do
      expect(File.exist?(index_html_path)).to be(true)
      html = File.read(index_html_path)

      # Extract src="..." paths from generated <img> tags
      src_paths = html.scan(/src="([^"]+)"/).flatten
                      .select { |p| p.include?("assets/images/optimized") }

      expect(src_paths).not_to be_empty, "No optimized image src found in index.html"

      src_paths.each do |src|
        # src is relative like "assets/images/optimized/foo-800-xxx.webp"
        file_in_site = File.join(test_site_dir, "_site", src)
        expect(File.exist?(file_in_site)).to be(true),
                                             -> { "HTML references #{src} but file not found at #{file_in_site}" }
      end
    end

    it "saves a manifest listing generated versions" do
      expect(File.exist?(manifest_path)).to be(true)
      manifest = JSON.parse(File.read(manifest_path))
      expect(manifest).to have_key("images")
      expect(manifest["images"]).not_to be_empty

      # At least one image should have default versions registered
      has_default = manifest["images"].values.any? do |data|
        data.dig("versions", "default") && !data.dig("versions", "default").empty?
      end
      expect(has_default).to be(true), "Manifest has no default versions registered"
    end

    it "processes all non-animated originals" do
      originals = all_original_images(test_site_dir)
      # 12 total - 1 animated = 11 non-animated originals
      expect(originals.length).to eq(11)
    end
  end

  # ------------------------------------------------------------------
  # Rebuild — the core regression scenario for the 0.1.6 bug
  # ------------------------------------------------------------------

  describe "after a rebuild (regression for v0.1.6 wipe bug)" do
    before do
      # First build
      run_jekyll_build(test_site_dir)
      # Record what _site had after the first build
      @site_files_after_first = optimized_files_in(site_optimized_dir).map { |f| File.basename(f) }

      # Second build — in 0.1.6 this wiped the optimized images from _site
      run_jekyll_build(test_site_dir)
    end

    it "still has optimized images in _site after the second build" do
      site_files_after_second = optimized_files_in(site_optimized_dir).map { |f| File.basename(f) }

      expect(site_files_after_second).not_to be_empty,
                                             "Optimized images wiped from _site after rebuild (v0.1.6 bug present)"

      missing = @site_files_after_first - site_files_after_second
      expect(missing).to be_empty,
                         "Optimized files lost between builds: #{missing.first(5).join(', ')}"
    end

    it "preserves optimized images in the source directory across rebuilds" do
      source_files = optimized_files_in(source_optimized_dir)
      expect(source_files).not_to be_empty
      # Source files should survive (they're outside _site, never cleaned)
      expect(source_files.length).to be >= 4
    end

    it "HTML still references valid files after rebuild" do
      expect(File.exist?(index_html_path)).to be(true)
      html = File.read(index_html_path)
      src_paths = html.scan(/src="([^"]+)"/).flatten
                      .select { |p| p.include?("assets/images/optimized") }

      expect(src_paths).not_to be_empty
      src_paths.each do |src|
        file_in_site = File.join(test_site_dir, "_site", src)
        expect(File.exist?(file_in_site)).to be(true),
                                             -> { "After rebuild, HTML references #{src} but file missing at #{file_in_site}" }
      end
    end
  end
end
