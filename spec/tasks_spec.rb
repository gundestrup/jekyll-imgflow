# frozen_string_literal: true

require "rspec"
require "fileutils"
require "tmpdir"
require "spec_helper"
require "jekyll-imgflow/tasks"

RSpec.describe JekyllImgFlow::Tasks, :unit do
  let(:tmpdir) { Dir.mktmpdir("imgflow-tasks-test") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "Rake task registration" do
    it "registers both preset tasks when the library is loaded" do
      expect(Rake::Task.task_defined?("imgflow:presets")).to be true
      expect(Rake::Task.task_defined?("imgflow:install_presets")).to be true
    end

    it "invokes the preset listing implementation" do
      allow(described_class).to receive(:list_presets)
      task = Rake::Task["imgflow:presets"]
      task.reenable

      task.invoke

      expect(described_class).to have_received(:list_presets)
    end
  end

  describe "builtin_presets_dir" do
    it "points to the lib/jekyll-imgflow/presets directory" do
      dir = described_class.builtin_presets_dir
      expect(File.exist?(dir)).to be true
      expect(dir).to match(%r{jekyll-imgflow/presets$})
    end
  end

  describe "builtin_preset_names" do
    it "includes thumbnail, hero, and gallery" do
      names = described_class.builtin_preset_names
      expect(names).to include("thumbnail")
      expect(names).to include("hero")
      expect(names).to include("gallery")
    end

    it "returns sorted names" do
      names = described_class.builtin_preset_names
      expect(names).to eq(names.sort)
    end
  end

  describe "install_presets" do
    around do |example|
      original_pwd = Dir.pwd
      Dir.chdir(tmpdir)
      example.run
      Dir.chdir(original_pwd)
    end

    it "creates _data/imgflow/presets/ directory" do
      described_class.install_presets
      expect(File.exist?(File.join(tmpdir, "_data", "imgflow", "presets"))).to be true
    end

    it "copies all built-in presets" do
      result = described_class.install_presets
      expect(result[:installed]).to include("thumbnail")
      expect(result[:installed]).to include("hero")
      expect(result[:installed]).to include("gallery")

      %w[thumbnail hero gallery].each do |name|
        path = File.join(tmpdir, "_data", "imgflow", "presets", "#{name}.yml")
        expect(File.exist?(path)).to be true
      end
    end

    it "skips up-to-date files on re-install" do
      described_class.install_presets
      result = described_class.install_presets
      # Already up-to-date files are not in installed or skipped
      expect(result[:installed]).to be_empty
      expect(result[:skipped]).to be_empty
    end

    it "skips modified files without overwrite" do
      described_class.install_presets
      # Modify the installed thumbnail
      thumb_path = File.join(tmpdir, "_data", "imgflow", "presets", "thumbnail.yml")
      File.write(thumb_path, "operations: []\n")

      result = described_class.install_presets
      expect(result[:skipped]).to include("thumbnail")
    end

    it "overwrites modified files with overwrite: true" do
      described_class.install_presets
      # Modify the installed thumbnail
      thumb_path = File.join(tmpdir, "_data", "imgflow", "presets", "thumbnail.yml")
      File.write(thumb_path, "operations: []\n")

      result = described_class.install_presets(overwrite: true)
      expect(result[:installed]).to include("thumbnail")
      # Content should be restored from gem
      gem_content = File.read(File.join(described_class.builtin_presets_dir, "thumbnail.yml"))
      expect(File.read(thumb_path)).to eq(gem_content)
    end
  end

  describe "same_content?" do
    it "returns true for identical files" do
      path_a = File.join(tmpdir, "a.txt")
      path_b = File.join(tmpdir, "b.txt")
      File.write(path_a, "hello")
      File.write(path_b, "hello")
      expect(described_class.same_content?(path_a, path_b)).to be true
    end

    it "returns false for different files" do
      path_a = File.join(tmpdir, "a.txt")
      path_b = File.join(tmpdir, "b.txt")
      File.write(path_a, "hello")
      File.write(path_b, "world")
      expect(described_class.same_content?(path_a, path_b)).to be false
    end

    it "returns false for non-existent file" do
      path_a = File.join(tmpdir, "a.txt")
      File.write(path_a, "hello")
      expect(described_class.same_content?(path_a, File.join(tmpdir, "nonexistent.txt"))).to be false
    end
  end
end
