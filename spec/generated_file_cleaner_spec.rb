# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::GeneratedFileCleaner, :unit do
  let(:root) { Dir.mktmpdir("imgflow-cleaner") }
  let(:source) { File.join(root, "source") }
  let(:destination) { File.join(root, "site") }
  let(:output) { "assets/images/optimized" }
  let(:site) { double("site", source: source, dest: destination) }
  let(:config) { double("config", output: output) }
  let(:cleaner) { described_class.new(site, config) }

  before do
    FileUtils.mkdir_p(source)
    FileUtils.mkdir_p(destination)
  end

  after do
    FileUtils.rm_rf(root)
  end

  describe "#delete" do
    it "deletes only the matching generated files from source and destination" do
      relative = "#{output}/nested/photo.webp"
      paths = [source, destination].map { |base| File.join(base, relative) }
      paths.each do |path|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "generated")
      end

      expect(cleaner.delete("/#{relative}")).to be true
      expect(paths).to all(satisfy { |path| !File.exist?(path) })
    end

    it "does not delete a path outside the configured output directory" do
      outside = File.join(source, "original.jpg")
      File.write(outside, "original")

      expect(cleaner.delete("/original.jpg")).to be false
      expect(File.read(outside)).to eq("original")
    end
  end

  describe "#clear" do
    it "refuses an output directory outside the site roots" do
      unsafe_config = double("config", output: "../outside")
      unsafe_cleaner = described_class.new(site, unsafe_config)

      expect { unsafe_cleaner.clear }
        .to raise_error(RuntimeError, /Refusing to delete optimized directory/)
    end
  end
end
