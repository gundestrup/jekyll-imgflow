# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/jekyll-imgflow/providers/libvips"

RSpec.describe JekyllImgFlow::Providers::Libvips, :unit do
  let(:provider) { described_class.new }

  describe "#build_alpha_pipeline" do
    it "builds crop+resize base for alpha pipeline" do
      provider.instance_variable_set(:@operations, [
                                       { type: :crop, ratio: "1:1", options: { calculated_width: 200, calculated_height: 200,
                                                                               calculated_x: 0, calculated_y: 0 } },
                                       { type: :resize, width: 100, height: 100, options: { scale_x: 0.5, scale_y: 0.5 } },
                                       { type: :alpha_opacity, opacity: 0.5 }
                                     ])

      result = provider.build_alpha_pipeline("/input.jpg", "/output.jpg", true, true)
      expect(result).to include("extract_area")
      expect(result).to include("VipsResize")
      expect(result).to include("linear")
      expect(result).to include("rm -f")
    end

    it "builds crop-only base for alpha pipeline" do
      provider.instance_variable_set(:@operations, [
                                       { type: :crop, ratio: "1:1", options: { calculated_width: 200, calculated_height: 200,
                                                                               calculated_x: 0, calculated_y: 0 } },
                                       { type: :alpha_opacity, opacity: 0.5 }
                                     ])

      result = provider.build_alpha_pipeline("/input.jpg", "/output.jpg", true, false)
      expect(result).to include("extract_area")
      expect(result).to include("linear")
      expect(result).to include("rm -f")
    end
  end

  describe "#build_watermark_pipeline with crop only" do
    it "builds crop command as base for watermark" do
      provider.instance_variable_set(:@operations, [
                                       { type: :crop, ratio: "1:1", options: { calculated_width: 200, calculated_height: 200,
                                                                               calculated_x: 0, calculated_y: 0 } },
                                       { type: :watermark, watermark_path: "/wm.png", options: { position: "center", opacity: nil } }
                                     ])

      result = provider.build_watermark_pipeline("/input.jpg", "/output.jpg", true, false)
      expect(result).to include("extract_area")
      expect(result).to include("composite2")
      expect(result).to include("rm -f")
    end
  end

  describe "#build_watermark_pipeline with alpha" do
    it "applies alpha before watermark" do
      provider.instance_variable_set(:@operations, [
                                       { type: :watermark, watermark_path: "/wm.png", options: { position: "center", opacity: nil } },
                                       { type: :alpha_opacity, opacity: 0.5 }
                                     ])

      result = provider.build_watermark_pipeline("/input.jpg", "/output.jpg", false, false)
      expect(result).to include("linear")
      expect(result).to include("composite2")
      expect(result).to include("rm -f")
    end
  end

  describe "#position_to_vips_xy" do
    it "translates southwest position" do
      result = provider.position_to_vips_xy("southwest", "/base.jpg", "/wm.png")
      expect(result).to include("--x 0")
      expect(result).to include("--y $(vips header")
    end

    it "translates southeast position" do
      result = provider.position_to_vips_xy("southeast", "/base.jpg", "/wm.png")
      expect(result).to include("--x $(vips header")
      expect(result).to include("--y $(vips header")
    end
  end
end
