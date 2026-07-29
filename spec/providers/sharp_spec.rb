# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/jekyll-imgflow/providers/sharp"

RSpec.describe JekyllImgFlow::Providers::Sharp, :unit do
  let(:provider) { described_class.new }

  describe "#build_watermark_pipeline with crop only" do
    it "builds crop command as base for watermark" do
      provider.instance_variable_set(:@operations, [
                                       { type: :crop, ratio: "1:1", options: { calculated_width: 200, calculated_height: 200,
                                                                               calculated_x: 0, calculated_y: 0 } },
                                       { type: :watermark, watermark_path: "/wm.png", options: { position: "center", opacity: nil } }
                                     ])

      result = provider.build_watermark_pipeline("/input.jpg", "/output.jpg", true, false)
      expect(result).to include("extract")
      expect(result).to include("composite")
      expect(result).to include("rm -f")
    end
  end

  describe "#translate_position" do
    it "translates southwest" do
      expect(provider.translate_position("southwest")).to eq("southwest")
    end

    it "returns unknown positions as-is" do
      expect(provider.translate_position("custom")).to eq("custom")
    end
  end
end
