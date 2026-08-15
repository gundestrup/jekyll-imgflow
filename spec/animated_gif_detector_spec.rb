# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::AnimatedGifDetector, :unit do
  let(:fixtures_dir) { File.expand_path("fixtures/originals", __dir__) }
  let(:animated_gif) { File.join(fixtures_dir, "ang-head-animation.gif") }
  let(:static_gif) { File.join(fixtures_dir, "static-single-frame.gif") }
  let(:jpg_image) { File.join(fixtures_dir, "mars-crater-large.jpg") }

  describe ".animated?" do
    it "returns true for an animated GIF (multiple frames)" do
      expect(described_class.animated?(animated_gif)).to be true
    end

    it "returns false for a static GIF (single frame)" do
      expect(described_class.animated?(static_gif)).to be false
    end

    it "returns false for a non-GIF image" do
      expect(described_class.animated?(jpg_image)).to be false
    end

    it "returns false for a non-existent file" do
      expect(described_class.animated?("/nonexistent/path.gif")).to be false
    end
  end

  describe "#animated?" do
    it "returns true for an animated GIF via instance" do
      expect(described_class.new(animated_gif).animated?).to be true
    end

    it "returns false for a static GIF via instance" do
      expect(described_class.new(static_gif).animated?).to be false
    end
  end

  describe "GIF87a vs GIF89a support" do
    let(:temp_dir) { create_test_dir("animated_gif_detector") }

    after do
      FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end

    it "detects animated GIF89a" do
      path = File.join(temp_dir, "animated89a.gif")
      write_animated_gif(path, version: "GIF89a", frames: 3)
      expect(described_class.animated?(path)).to be true
    end

    it "detects animated GIF87a" do
      path = File.join(temp_dir, "animated87a.gif")
      write_animated_gif(path, version: "GIF87a", frames: 2)
      expect(described_class.animated?(path)).to be true
    end

    it "returns false for single-frame GIF89a" do
      path = File.join(temp_dir, "static89a.gif")
      write_animated_gif(path, version: "GIF89a", frames: 1)
      expect(described_class.animated?(path)).to be false
    end
  end

  # Helper: write a minimal valid GIF with N frames (no Global Color Table)
  # Each frame is a 1x1 pixel with a Local Color Table and LZW data.
  def write_animated_gif(path, version:, frames:)
    header = version
    # Logical Screen Descriptor: width=1, height=1, packed=0 (no GCT), bg=0, aspect=0
    lsd = [1, 0, 1, 0, 0, 0, 0].pack("C7")
    body = Array.new(frames) { write_frame }.join
    trailer = [0x3B].pack("C")
    File.binwrite(path, header + lsd + body + trailer)
  end

  def write_frame
    # Image Descriptor: 0x2C, left=0, top=0, width=1, height=1,
    # packed=0x80 (LCT present, 1 color)
    id = [0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0x80].pack("C10")
    # Local Color Table: 2 entries (black, white)
    lct = [0, 0, 0, 255, 255, 255].pack("C6")
    # LZW Minimum Code Size
    lzw_min = [2].pack("C")
    # Sub-block: clear(4) + pixel(0) + EOI(5) packed into 2 bytes
    sub_block = [2, 0x04, 0x01].pack("C3")
    terminator = [0].pack("C")
    id + lct + lzw_min + sub_block + terminator
  end
end
