# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Integration tests for watermark and alpha opacity operations
# Tests the full pipeline: Tag -> Provider -> Command building -> (mocked) execution
# Runs against all available providers to verify the agnostic operation flow
RSpec.describe "Watermark and Alpha Opacity Integration", :integration, :provider do
  before do
    WebMock.allow_net_connect!
    FileUtils.mkdir_p(output_dir)
  end

  let(:test_site_dir) { create_test_dir("watermark-alpha-integration") }
  let(:site) { create_mock_site(source: test_site_dir) }
  let(:components) { create_imgflow_components(site) }
  let(:config) { components[:config] }
  let(:registry) { components[:registry] }
  let(:test_image_name) { TestPictures.get(:default).first }
  let(:test_image_path) { TestPictures.path(test_image_name) }

  let(:watermark_image_name) { "file_example-small.png" }
  let(:watermark_image_path) { TestPictures.path(watermark_image_name) }

  let(:output_dir) { File.join(test_site_dir, "output") }
  let(:output_path) { File.join(output_dir, "test-output.png") }
  # Get all available providers from registry
  let(:available_providers) { registry.providers.select(&:available?) }
  # Get available CLI providers only (exclude HTTP-based providers)
  let(:cli_providers) do
    available_providers.reject do |p|
      p.respond_to?(:build_combined_weserv_url) ||
        p.respond_to?(:build_combined_flyimg_url) ||
        p.respond_to?(:build_combined_imgproxy_url)
    end
  end

  after do
    FileUtils.rm_rf(test_site_dir)
  end

  describe "Watermark Operation Through Tag Pipeline" do
    it "processes watermark through WatermarkTag for all CLI providers" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        tag = JekyllImgFlow::Tags::WatermarkTag.new(provider)
        allow(provider).to receive(:execute_command).and_return(true)

        result = tag.process(test_image_path, output_path,
                             watermark: watermark_image_path,
                             position: :bottom_right,
                             opacity: 0.5)

        expect(result).to eq(output_path),
                          "#{provider_name}: WatermarkTag should return output path"
        expect(provider.operations).to be_empty,
                                       "#{provider_name}: ops cleared after execute"
      end
    end

    it "builds correct watermark command for each CLI provider" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        provider.add_watermark(watermark_image_path,
                               position: "southeast",
                               opacity: 0.5)

        case provider_name
        when "Sharp"
          cmd = provider.build_sharp_command(test_image_path, output_path)
          expect(cmd).to include("composite"),
                         "#{provider_name}: should include composite"
          expect(cmd).to include("ensureAlpha"),
                         "#{provider_name}: should include ensureAlpha for opacity"
          expect(cmd).to include("--gravity"),
                         "#{provider_name}: should include --gravity"
          expect(cmd).to include("southeast"),
                         "#{provider_name}: should include position"
        when "Libvips"
          cmd = provider.build_vips_command(test_image_path, output_path)
          expect(cmd).to include("composite2"),
                         "#{provider_name}: should include composite2"
          expect(cmd).to include("linear"),
                         "#{provider_name}: should include linear for opacity"
          expect(cmd).to include("over"),
                         "#{provider_name}: should include over blend mode"
        when "Imagemagick"
          cmd = provider.build_combined_imagemagick_command(
            test_image_path, output_path
          )
          expect(cmd).to include("-composite"),
                         "#{provider_name}: should include -composite"
          expect(cmd).to include("SouthEast"),
                         "#{provider_name}: should include SouthEast gravity"
        end

        provider.reset_operations
      end
    end

    it "handles watermark without opacity for all CLI providers" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        tag = JekyllImgFlow::Tags::WatermarkTag.new(provider)
        allow(provider).to receive(:execute_command).and_return(true)

        result = tag.process(test_image_path, output_path,
                             watermark: watermark_image_path,
                             position: :center)

        expect(result).to eq(output_path),
                          "#{provider_name}: should process watermark without opacity"
        expect(provider.operations).to be_empty
      end
    end

    it "all available providers support watermark operation" do
      available_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        expect(provider.class.supports_operation?(:watermark)).to be(true),
                                                                  "#{provider_name} supports watermark"
      end
    end

    it "all available providers collect watermark operation correctly" do
      available_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        provider.add_watermark(watermark_image_path,
                               position: "northwest",
                               opacity: 0.7)
        op = provider.operations.last
        expect(op[:type]).to eq(:watermark),
                             "#{provider_name}: operation type should be :watermark"
        expect(op[:watermark_path]).to eq(watermark_image_path)
        expect(op[:options][:position]).to eq("northwest")
        expect(op[:options][:opacity]).to eq(0.7)

        provider.reset_operations
      end
    end
  end

  describe "Alpha Opacity Operation Through Tag Pipeline" do
    it "processes alpha opacity through OpacityTag for all CLI providers" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        tag = JekyllImgFlow::Tags::OpacityTag.new(provider)
        allow(provider).to receive(:execute_command).and_return(true)

        result = tag.process(test_image_path, output_path, opacity: 0.5)

        expect(result).to eq(output_path),
                          "#{provider_name}: OpacityTag should return output path"
        expect(provider.operations).to be_empty
      end
    end

    it "builds correct alpha opacity command for each CLI provider" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        provider.alpha_opacity = 0.5

        case provider_name
        when "Sharp"
          cmd = provider.build_sharp_command(test_image_path, output_path)
          expect(cmd).to include("alpha"),
                         "#{provider_name}: should include alpha"
          expect(cmd).to include("{alpha:128}")
        when "Libvips"
          cmd = provider.build_vips_command(test_image_path, output_path)
          expect(cmd).to include("linear"),
                         "#{provider_name}: should include linear"
          expect(cmd).to include("0.5")
        when "Imagemagick"
          cmd = provider.build_combined_imagemagick_command(
            test_image_path, output_path
          )
          expect(cmd).to include("-alpha"),
                         "#{provider_name}: should include -alpha"
          expect(cmd).to include("-channel A")
        end

        provider.reset_operations
      end
    end

    it "handles extreme opacity values for all CLI providers" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        tag = JekyllImgFlow::Tags::OpacityTag.new(provider)
        allow(provider).to receive(:execute_command).and_return(true)

        # Near transparent
        tag.process(test_image_path, output_path, opacity: 0.01)
        expect(provider.operations).to be_empty,
                                       "#{provider_name}: ops should clear after 0.01 opacity"

        # Near opaque
        tag.process(test_image_path, output_path, opacity: 0.99)
        expect(provider.operations).to be_empty,
                                       "#{provider_name}: ops should clear after 0.99 opacity"
      end
    end

    it "all available providers support alpha_opacity operation" do
      available_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        expect(provider.class.supports_operation?(:alpha_opacity)).to be(true),
                                                                      "#{provider_name} supports alpha_opacity"
      end
    end

    it "all available providers collect alpha_opacity correctly" do
      available_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        provider.alpha_opacity = 0.5
        op = provider.operations.last
        expect(op[:type]).to eq(:alpha_opacity),
                             "#{provider_name}: operation type should be :alpha_opacity"
        expect(op[:opacity]).to eq(0.5)

        provider.reset_operations
      end
    end
  end

  describe "Combined Operations Pipeline" do
    it "builds resize + watermark pipeline for all CLI providers" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        provider.resize(800, 600)
        provider.add_watermark(watermark_image_path,
                               position: "southeast",
                               opacity: 0.5)

        case provider_name
        when "Sharp"
          cmd = provider.build_sharp_command(test_image_path, output_path)
          expect(cmd).to include("resize")
          expect(cmd).to include("composite")
          expect(cmd).to include("&&")
          expect(cmd).to include("ensureAlpha")
        when "Libvips"
          cmd = provider.build_vips_command(test_image_path, output_path)
          expect(cmd).to include("VipsResize")
          expect(cmd).to include("composite2")
          expect(cmd).to include("&&")
        when "Imagemagick"
          cmd = provider.build_combined_imagemagick_command(
            test_image_path, output_path
          )
          expect(cmd).to include("-resize")
          expect(cmd).to include("-composite")
        end

        provider.reset_operations
      end
    end

    it "builds resize + alpha opacity pipeline for all CLI providers" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        provider.resize(800, 600)
        provider.alpha_opacity = 0.3

        case provider_name
        when "Sharp"
          cmd = provider.build_sharp_command(test_image_path, output_path)
          expect(cmd).to include("resize")
          expect(cmd).to include("alpha")
        when "Libvips"
          cmd = provider.build_vips_command(test_image_path, output_path)
          expect(cmd).to include("VipsResize")
          expect(cmd).to include("linear")
          expect(cmd).to include("0.3")
          expect(cmd).to include("&&")
        when "Imagemagick"
          cmd = provider.build_combined_imagemagick_command(
            test_image_path, output_path
          )
          expect(cmd).to include("-resize")
          expect(cmd).to include("-alpha")
        end

        provider.reset_operations
      end
    end

    it "builds crop + resize + watermark pipeline for all CLI providers" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800,
                              calculated_height: 450)
        provider.resize(400, 225, scale_x: 0.5, scale_y: 0.5)
        provider.add_watermark(watermark_image_path,
                               position: "center")

        case provider_name
        when "Sharp"
          cmd = provider.build_sharp_command(test_image_path, output_path)
          expect(cmd).to include("extract")
          expect(cmd).to include("resize")
          expect(cmd).to include("composite")
          expect(cmd).to include("&&")
        when "Libvips"
          cmd = provider.build_vips_command(test_image_path, output_path)
          expect(cmd).to include("extract_area")
          expect(cmd).to include("VipsResize")
          expect(cmd).to include("composite2")
          expect(cmd).to include("&&")
        when "Imagemagick"
          cmd = provider.build_combined_imagemagick_command(
            test_image_path, output_path
          )
          expect(cmd).to include("-crop")
          expect(cmd).to include("-resize")
          expect(cmd).to include("-composite")
        end

        provider.reset_operations
      end
    end
  end

  describe "Watermark with Format and Quality" do
    it "includes format and quality in watermark command for all CLI providers" do
      cli_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        provider.reset_operations

        provider.add_watermark(watermark_image_path, position: "northwest")
        provider.convert_format("webp")
        provider.quality = 80

        case provider_name
        when "Sharp"
          cmd = provider.build_sharp_command(test_image_path, output_path)
          expect(cmd).to include("composite")
          expect(cmd).to include("-f webp")
          expect(cmd).to include("-q80")
        when "Libvips"
          cmd = provider.build_vips_command(test_image_path, output_path)
          expect(cmd).to include("composite2")
          expect(cmd).to include(".webp")
          expect(cmd).to include("Q=80")
        when "Imagemagick"
          cmd = provider.build_combined_imagemagick_command(
            test_image_path, output_path
          )
          expect(cmd).to include("-composite")
          expect(cmd).to include("-quality")
          # ImageMagick handles format via output filename extension
        end

        provider.reset_operations
      end
    end
  end

  describe "Provider Capability Matrix for Watermark and Alpha" do
    it "no provider lists watermark or alpha_opacity as unsupported" do
      available_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        unsupported = provider.class.unsupported_operations
        expect(unsupported).not_to include(:watermark),
                                   "#{provider_name} should not list watermark as unsupported"
        expect(unsupported).not_to include(:alpha_opacity),
                                   "#{provider_name} should not list alpha_opacity as unsupported"
      end
    end

    it "all providers have empty unsupported_operations" do
      available_providers.each do |provider|
        provider_name = provider.class.name.split("::").last
        expect(provider.class.unsupported_operations).to eq([]),
                                                         "#{provider_name} has empty unsupported_ops"
      end
    end
  end
end
