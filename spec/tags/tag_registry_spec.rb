# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::Tags::TagRegistry, :unit do
  describe ".register_tag" do
    it "registers a new tag" do
      described_class.register_tag(:test_tag, JekyllImgFlow::Tags::ResizeTag)

      expect(described_class.get_tag(:test_tag)).to eq(JekyllImgFlow::Tags::ResizeTag)
    end
  end

  describe ".get_tag" do
    it "returns registered tag class" do
      expect(described_class.get_tag(:resize)).to eq(JekyllImgFlow::Tags::ResizeTag)
    end

    it "returns nil for unregistered tag" do
      expect(described_class.get_tag(:nonexistent)).to be_nil
    end
  end

  describe ".available_tags" do
    it "returns list of registered tag names" do
      tags = described_class.available_tags

      expect(tags).to include(:resize, :crop, :quality, :format, :optimize, :watermark, :opacity)
    end
  end

  describe "standard tag registrations" do
    it "registers all standard tags" do
      expected_tags = {
        resize: JekyllImgFlow::Tags::ResizeTag,
        crop: JekyllImgFlow::Tags::CropTag,
        quality: JekyllImgFlow::Tags::QualityTag,
        format: JekyllImgFlow::Tags::FormatTag,
        optimize: JekyllImgFlow::Tags::OptimizeTag,
        watermark: JekyllImgFlow::Tags::WatermarkTag,
        opacity: JekyllImgFlow::Tags::OpacityTag
      }

      expected_tags.each do |name, expected_class|
        expect(described_class.get_tag(name)).to eq(expected_class),
                                                 "Tag #{name} not registered correctly"
      end
    end
  end

  describe "error handling during tag discovery" do
    before do
      allow(Jekyll.logger).to receive(:debug)
      allow(Jekyll.logger).to receive(:warn)
    end

    it "logs warning on NameError when loading tag" do
      described_class.reset!

      tags_dir = File.join(File.dirname(__FILE__), "..", "..", "lib", "jekyll-imgflow", "tags")
      temp_file = File.join(tags_dir, "nonexistent_tag.rb")
      File.write(temp_file, "# frozen_string_literal: true\n# Intentionally empty for test\n")

      begin
        described_class.discover_tags
        expect(Jekyll.logger).to have_received(:warn).with(
          "ImgFlow:", /Failed to load tag nonexistent/
        ).at_least(:once)
      ensure
        FileUtils.rm_f(temp_file)
        described_class.reset!
      end
    end

    it "logs warning on LoadError when requiring tag file" do
      described_class.reset!

      tags_dir = File.join(File.dirname(__FILE__), "..", "..", "lib", "jekyll-imgflow", "tags")
      temp_file = File.join(tags_dir, "loaderror_tag.rb")
      File.write(temp_file, "require 'nonexistent_gem_for_test'\n")

      begin
        described_class.discover_tags
        expect(Jekyll.logger).to have_received(:warn).with(
          "ImgFlow:", /Failed to require tag loaderror/
        ).at_least(:once)
      ensure
        FileUtils.rm_f(temp_file)
        described_class.reset!
      end
    end
  end
end
