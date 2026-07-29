# frozen_string_literal: true

require "spec_helper"
require "shellwords"

# Trigger provider discovery so classes are loaded
JekyllImgFlow::ProviderRegistry.discover_providers

RSpec.describe "Provider URL and Command Building", :provider do
  let(:site) do
    double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                   dest: "/tmp/test_site/_site")
  end
  let(:config) { JekyllImgFlow::Config.new(site) }

  # ============================================================
  # Weserv Provider
  # ============================================================
  describe JekyllImgFlow::Providers::Weserv do
    subject(:provider) { described_class.new(config) }

    describe "#build_combined_weserv_url" do
      it "builds URL with resize (width only)" do
        provider.resize(800, nil)
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to start_with("http://localhost:33007/?")
        expect(url).to include("w=800")
        expect(url).not_to include("h=")
      end

      it "builds URL with resize (width and height)" do
        provider.resize(800, 600)
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("w=800&h=600")
      end

      it "builds URL with quality" do
        provider.quality = 85
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("q=85")
      end

      it "builds URL with format" do
        provider.convert_format("webp")
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("output=webp")
      end

      it "builds URL with basic crop (no ratio)" do
        provider.crop(nil, x: 10, y: 20, width: 100, height: 80)
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("cx=10&cy=20&cw=100&ch=80")
      end

      it "builds URL with ratio crop (calculated)" do
        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800, calculated_height: 450)
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("cx=50&cy=0&cw=800&ch=450")
      end

      it "builds URL with smartcrop attention" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "attention")
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("crop=800x450")
        expect(url).to include("a=attention")
      end

      it "builds URL with smartcrop entropy" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "entropy")
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("a=entropy")
      end

      it "builds URL with smartcrop center" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "center")
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("a=center")
      end

      it "builds URL with watermark" do
        provider.add_watermark("/images/wm.png", position: "northwest", opacity: 0.5)
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("wm=")
        expect(url).to include("wmpos=tl")
        expect(url).to include("wmo=0.5")
      end

      it "builds URL with alpha opacity" do
        provider.alpha_opacity = 0.5
        url = provider.build_combined_weserv_url("/images/test.jpg")
        expect(url).to include("alpha=128")
      end

      it "raises when weserv_url not set" do
        cfg = TEST_CONFIG["imgflow"].dup.merge("weserv_url" => nil)
        site_no_url = double("site", config: TEST_CONFIG.merge("imgflow" => cfg),
                                     source: "/tmp/test_site", dest: "/tmp/test_site/_site")
        provider_no_url = described_class.new(JekyllImgFlow::Config.new(site_no_url))
        expect do
          provider_no_url.build_combined_weserv_url("/test.jpg")
        end.to raise_error(/weserv_url not set/)
      end
    end

    describe "#translate_weserv_position" do
      it "translates compass directions" do
        expect(provider.send(:translate_weserv_position, "northwest")).to eq("tl")
        expect(provider.send(:translate_weserv_position, "northeast")).to eq("tr")
        expect(provider.send(:translate_weserv_position, "southwest")).to eq("bl")
        expect(provider.send(:translate_weserv_position, "southeast")).to eq("br")
        expect(provider.send(:translate_weserv_position, "center")).to eq("c")
        expect(provider.send(:translate_weserv_position, "custom")).to eq("custom")
      end
    end

    describe "#fetch_and_save" do
      it "raises on empty response" do
        allow(provider).to receive(:fetch_with_timeout).and_return("")
        expect { provider.send(:fetch_and_save, "http://ex.com", "/tmp/out.jpg") }
          .to raise_error(/Weserv request failed/)
      end

      it "saves response to file" do
        allow(provider).to receive(:fetch_with_timeout).and_return("data")
        out = File.join(Dir.tmpdir, "imgflow-test-weserv-#{Time.now.to_i}.jpg")
        provider.send(:fetch_and_save, "http://ex.com", out)
        expect(File.read(out)).to eq("data")
        FileUtils.rm_f(out)
      end
    end

    describe "#fetch_with_timeout" do
      it "raises on HTTP error" do
        stub_request(:get, /localhost:33007/).to_return(status: 500)
        expect { provider.send(:fetch_with_timeout, "http://localhost:33007/?url=test") }
          .to raise_error(/Weserv request failed/)
      end

      it "returns body on success" do
        stub_request(:get, /localhost:33007/).to_return(status: 200, body: "bytes")
        expect(provider.send(:fetch_with_timeout,
                             "http://localhost:33007/?url=test")).to eq("bytes")
      end

      it "raises on connection error" do
        stub_request(:get, "http://localhost:99999/").to_raise(Errno::ECONNREFUSED)
        expect { provider.send(:fetch_with_timeout, "http://localhost:99999/") }
          .to raise_error(/Weserv request failed/)
      end
    end
  end

  # ============================================================
  # Flyimg Provider
  # ============================================================
  describe JekyllImgFlow::Providers::Flyimg do
    subject(:provider) { described_class.new(config) }

    describe "#build_combined_flyimg_url" do
      it "builds URL with resize (width only)" do
        provider.resize(800, nil)
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to start_with("http://localhost:33008/upload/")
        expect(url).to include("w_800")
      end

      it "builds URL with resize (width and height)" do
        provider.resize(800, 600)
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("w_800")
        expect(url).to include("h_600")
      end

      it "builds URL with quality" do
        provider.quality = 85
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("q_85")
      end

      it "builds URL with format" do
        provider.convert_format("webp")
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("o_webp")
      end

      it "builds URL with basic crop" do
        provider.crop(nil, x: 10, y: 20, width: 100, height: 80)
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("e_1")
        expect(url).to include("p1x_10")
        expect(url).to include("p1y_20")
        expect(url).to include("p2x_110")
        expect(url).to include("p2y_100")
      end

      it "builds URL with ratio crop" do
        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800, calculated_height: 450)
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("e_1")
        expect(url).to include("p1x_50")
        expect(url).to include("p1y_0")
        expect(url).to include("p2x_850")
        expect(url).to include("p2y_450")
      end

      it "builds URL with smartcrop attention" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "attention")
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("w_800")
        expect(url).to include("h_450")
        expect(url).to include("smc_1")
      end

      it "builds URL with smartcrop entropy" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "entropy")
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("smc_1")
      end

      it "builds URL with smartcrop center" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "center")
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("smc_1")
      end

      it "builds URL with watermark" do
        provider.add_watermark("/images/wm.png", position: "northwest", opacity: 0.5)
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("wm_")
        expect(url).to include("tl")
        expect(url).to include("50")
      end

      it "builds URL with alpha opacity" do
        provider.alpha_opacity = 0.5
        url = provider.build_combined_flyimg_url("/images/test.jpg")
        expect(url).to include("a_128")
      end

      it "raises when flyimg_url not set" do
        cfg = TEST_CONFIG["imgflow"].dup.merge("flyimg_url" => nil)
        site_no_url = double("site", config: TEST_CONFIG.merge("imgflow" => cfg),
                                     source: "/tmp/test_site", dest: "/tmp/test_site/_site")
        provider_no_url = described_class.new(JekyllImgFlow::Config.new(site_no_url))
        expect do
          provider_no_url.build_combined_flyimg_url("/test.jpg")
        end.to raise_error(/flyimg_url not set/)
      end
    end

    describe "#translate_flyimg_position" do
      it "translates compass directions" do
        expect(provider.send(:translate_flyimg_position, "northwest")).to eq("tl")
        expect(provider.send(:translate_flyimg_position, "northeast")).to eq("tr")
        expect(provider.send(:translate_flyimg_position, "southwest")).to eq("bl")
        expect(provider.send(:translate_flyimg_position, "southeast")).to eq("br")
        expect(provider.send(:translate_flyimg_position, "center")).to eq("c")
        expect(provider.send(:translate_flyimg_position, "custom")).to eq("custom")
      end
    end

    describe "#map_format" do
      it "maps format names" do
        expect(provider.send(:map_format, "jpeg")).to eq("jpg")
        expect(provider.send(:map_format, "jpg")).to eq("jpg")
        expect(provider.send(:map_format, "png")).to eq("png")
        expect(provider.send(:map_format, "webp")).to eq("webp")
        expect(provider.send(:map_format, "gif")).to eq("gif")
        expect(provider.send(:map_format, "AVIF")).to eq("avif")
        expect(provider.send(:map_format, nil)).to be_nil
      end
    end

    describe "#fetch_and_save" do
      it "raises on empty response" do
        allow(provider).to receive(:fetch_with_timeout).and_return("")
        expect { provider.send(:fetch_and_save, "http://ex.com", "/tmp/out.jpg") }
          .to raise_error(/Flyimg request failed/)
      end

      it "saves response to file" do
        allow(provider).to receive(:fetch_with_timeout).and_return("data")
        out = File.join(Dir.tmpdir, "imgflow-test-flyimg-#{Time.now.to_i}.jpg")
        provider.send(:fetch_and_save, "http://ex.com", out)
        expect(File.read(out)).to eq("data")
        FileUtils.rm_f(out)
      end
    end

    describe "#fetch_with_timeout" do
      it "raises on HTTP error" do
        stub_request(:get, /localhost:33008/).to_return(status: 500)
        expect { provider.send(:fetch_with_timeout, "http://localhost:33008/upload/test") }
          .to raise_error(/Flyimg request failed/)
      end

      it "returns body on success" do
        stub_request(:get, /localhost:33008/).to_return(status: 200, body: "bytes")
        expect(provider.send(:fetch_with_timeout,
                             "http://localhost:33008/upload/test")).to eq("bytes")
      end
    end
  end

  # ============================================================
  # Imgproxy Provider
  # ============================================================
  describe JekyllImgFlow::Providers::Imgproxy do
    subject(:provider) { described_class.new(config) }

    describe "#build_combined_imgproxy_url" do
      it "builds URL with resize (width and height)" do
        provider.resize(800, 600)
        url = provider.build_combined_imgproxy_url("/images/test.jpg")
        expect(url).to start_with("http://localhost:33001/insecure/")
        expect(url).to include("rs:fill:800:600")
      end

      it "builds URL with resize (width only)" do
        provider.resize(800, nil)
        url = provider.build_combined_imgproxy_url("/images/test.jpg")
        expect(url).to include("rs:fit:800:")
      end

      it "builds URL with quality" do
        provider.quality = 85
        url = provider.build_combined_imgproxy_url("/images/test.jpg")
        expect(url).to include("q:85")
      end

      it "builds URL with format" do
        provider.convert_format("webp")
        url = provider.build_combined_imgproxy_url("/images/test.jpg")
        expect(url).to include("f:webp")
      end

      it "builds URL with basic crop" do
        provider.crop(nil, x: 10, y: 20, width: 100, height: 80)
        url = provider.build_combined_imgproxy_url("/images/test.jpg")
        expect(url).to include("g:nowe:10:20")
        expect(url).to include("c:100:80")
      end

      it "builds URL with ratio crop" do
        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800, calculated_height: 450)
        url = provider.build_combined_imgproxy_url("/images/test.jpg")
        expect(url).to include("g:nowe:50:0")
        expect(url).to include("c:800:450")
      end

      it "builds URL with smartcrop" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "attention")
        url = provider.build_combined_imgproxy_url("/images/test.jpg")
        expect(url).to include("g:sm")
        expect(url).to include("c:800:450")
      end

      it "builds URL with watermark" do
        provider.add_watermark("/images/wm.png", position: "northwest", opacity: 0.5)
        url = provider.build_combined_imgproxy_url("/images/test.jpg")
        expect(url).to include("wm:")
        expect(url).to include("tl")
      end

      it "builds URL with alpha opacity" do
        provider.alpha_opacity = 0.5
        url = provider.build_combined_imgproxy_url("/images/test.jpg")
        expect(url).to include("a:128")
      end

      it "raises when imgproxy_url not set" do
        cfg = TEST_CONFIG["imgflow"].dup.merge("imgproxy_url" => nil)
        site_no_url = double("site", config: TEST_CONFIG.merge("imgflow" => cfg),
                                     source: "/tmp/test_site", dest: "/tmp/test_site/_site")
        provider_no_url = described_class.new(JekyllImgFlow::Config.new(site_no_url))
        expect do
          provider_no_url.build_combined_imgproxy_url("/test.jpg")
        end.to raise_error(/imgproxy_url not set/)
      end
    end

    describe "#translate_imgproxy_position" do
      it "translates compass directions" do
        expect(provider.send(:translate_imgproxy_position, "northwest")).to eq("tl")
        expect(provider.send(:translate_imgproxy_position, "northeast")).to eq("tr")
        expect(provider.send(:translate_imgproxy_position, "southwest")).to eq("bl")
        expect(provider.send(:translate_imgproxy_position, "southeast")).to eq("br")
        expect(provider.send(:translate_imgproxy_position, "center")).to eq("c")
        expect(provider.send(:translate_imgproxy_position, "custom")).to eq("custom")
      end
    end

    describe "#fetch_and_save" do
      it "raises on empty response" do
        allow(provider).to receive(:fetch_with_timeout).and_return("")
        expect { provider.send(:fetch_and_save, "http://ex.com", "/tmp/out.jpg") }
          .to raise_error(/Imgproxy request failed/)
      end

      it "saves response to file" do
        allow(provider).to receive(:fetch_with_timeout).and_return("data")
        out = File.join(Dir.tmpdir, "imgflow-test-imgproxy-#{Time.now.to_i}.jpg")
        provider.send(:fetch_and_save, "http://ex.com", out)
        expect(File.read(out)).to eq("data")
        FileUtils.rm_f(out)
      end
    end

    describe "#fetch_with_timeout" do
      it "raises on HTTP error" do
        stub_request(:get, /localhost:33001/).to_return(status: 500)
        expect { provider.send(:fetch_with_timeout, "http://localhost:33001/insecure/test") }
          .to raise_error(/Imgproxy request failed/)
      end

      it "returns body on success" do
        stub_request(:get, /localhost:33001/).to_return(status: 200, body: "bytes")
        expect(provider.send(:fetch_with_timeout,
                             "http://localhost:33001/insecure/test")).to eq("bytes")
      end
    end
  end

  # ============================================================
  # ImageMagick Provider
  # ============================================================
  describe JekyllImgFlow::Providers::Imagemagick do
    subject(:provider) { described_class.new(config) }

    describe "#build_combined_imagemagick_command" do
      it "builds command with resize (width only)" do
        provider.resize(800, nil)
        cmd = provider.build_combined_imagemagick_command("input.jpg", "output.jpg")
        expect(cmd).to include("magick")
        expect(cmd).to include("-resize")
        expect(cmd).to include("800")
      end

      it "builds command with resize (width and height)" do
        provider.resize(800, 600)
        cmd = provider.build_combined_imagemagick_command("input.jpg", "output.jpg")
        expect(cmd).to include("800x600!")
      end

      it "builds command with quality" do
        provider.quality = 85
        cmd = provider.build_combined_imagemagick_command("input.jpg", "output.jpg")
        expect(cmd).to include("-quality")
        expect(cmd).to include("85")
      end

      it "builds command with format (adds default quality)" do
        provider.convert_format("webp")
        cmd = provider.build_combined_imagemagick_command("input.jpg", "output.jpg")
        expect(cmd).to include("-quality")
      end

      it "builds command with basic crop" do
        provider.crop(nil, x: 10, y: 20, width: 100, height: 80)
        cmd = provider.build_combined_imagemagick_command("input.jpg", "output.jpg")
        expect(cmd).to include("-crop")
        expect(cmd).to include("100x80+10+20")
      end

      it "builds command with ratio crop" do
        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800, calculated_height: 450)
        cmd = provider.build_combined_imagemagick_command("input.jpg", "output.jpg")
        expect(cmd).to include("800x450+50+0")
      end

      it "builds command with smartcrop fallback (center gravity)" do
        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800, calculated_height: 450, keep: "attention")
        cmd = provider.build_combined_imagemagick_command("input.jpg", "output.jpg")
        expect(cmd).to include("-gravity")
        expect(cmd).to include("center")
      end

      it "builds command with watermark" do
        provider.add_watermark("watermark.png", position: "northwest")
        cmd = provider.build_combined_imagemagick_command("input.jpg", "output.jpg")
        expect(cmd).to include("watermark.png")
        expect(cmd).to include("NorthWest")
        expect(cmd).to include("-composite")
      end

      it "builds command with alpha opacity" do
        provider.alpha_opacity = 0.5
        cmd = provider.build_combined_imagemagick_command("input.jpg", "output.jpg")
        expect(cmd).to include("-alpha")
        expect(cmd).to include("set")
        expect(cmd).to include("-channel")
        expect(cmd).to include("A")
        expect(cmd).to include("multiply")
        expect(cmd).to include("50%")
      end

      it "escapes paths with spaces" do
        provider.resize(800, 600)
        cmd = provider.build_combined_imagemagick_command("my input.jpg", "my output.jpg")
        expect(cmd).to include("my\\ input.jpg")
      end
    end

    describe "#translate_position" do
      it "translates compass directions" do
        expect(provider.translate_position("northwest")).to eq("NorthWest")
        expect(provider.translate_position("northeast")).to eq("NorthEast")
        expect(provider.translate_position("southwest")).to eq("SouthWest")
        expect(provider.translate_position("southeast")).to eq("SouthEast")
        expect(provider.translate_position("center")).to eq("Center")
        expect(provider.translate_position("custom")).to eq("custom")
      end
    end

    describe "#available?" do
      it "returns true when magick is available" do
        allow(Open3).to receive(:capture3).with("which", "magick")
                                          .and_return(["", "", double(success?: true)])
        allow(Open3).to receive(:capture3).with("which", "convert")
                                          .and_return(["", "", double(success?: false)])
        expect(provider.available?).to be true
      end

      it "returns true when convert is available (no magick)" do
        allow(Open3).to receive(:capture3).with("which", "magick")
                                          .and_return(["", "", double(success?: false)])
        allow(Open3).to receive(:capture3).with("which", "convert")
                                          .and_return(["", "", double(success?: true)])
        expect(provider.available?).to be true
      end

      it "returns false when neither is available" do
        allow(Open3).to receive(:capture3).with("which", "magick")
                                          .and_return(["", "", double(success?: false)])
        allow(Open3).to receive(:capture3).with("which", "convert")
                                          .and_return(["", "", double(success?: false)])
        expect(provider.available?).to be false
      end
    end
  end

  # ============================================================
  # Libvips Provider
  # ============================================================
  describe JekyllImgFlow::Providers::Libvips do
    subject(:provider) { described_class.new(config) }

    describe "#build_vips_command" do
      it "builds sequential crop+resize command" do
        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800, calculated_height: 450)
        provider.resize(400, 225, scale_x: 0.5, scale_y: 0.5)
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("&&")
        expect(cmd).to include("extract_area")
        expect(cmd).to include("VipsResize")
        expect(cmd).to include("rm -f")
      end

      it "builds resize with both scale factors" do
        provider.resize(400, 225, scale_x: 0.5, scale_y: 0.5)
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("--vscale=0.5")
      end

      it "builds resize with fallback when scale_y missing" do
        provider.resize(400, 225, scale_x: 0.5)
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("0.5")
        expect(cmd).not_to include("--vscale")
      end

      it "builds resize with one dimension (default scale_x)" do
        provider.resize(400, nil, {})
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("1.0")
      end

      it "builds smartcrop (attention)" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "attention")
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("smartcrop")
        expect(cmd).to include("--interesting=attention")
      end

      it "builds smartcrop (entropy)" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "entropy")
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("--interesting=entropy")
      end

      it "builds smartcrop (centre)" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "centre")
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("--interesting=centre")
      end

      it "builds smartcrop (center maps to centre)" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "center")
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("--interesting=centre")
      end

      it "builds basic extract_area (ratio)" do
        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800, calculated_height: 450)
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("extract_area")
        expect(cmd).to include("50 0 800 450")
      end

      it "builds basic extract_area (no ratio)" do
        provider.crop(nil, x: 10, y: 20, width: 100, height: 80)
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("extract_area")
        expect(cmd).to include("10 20 100 80")
      end

      it "builds extract_area with default x/y=0 when not specified" do
        provider.crop(nil, width: 100, height: 80)
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("0 0 100 80")
      end

      it "builds copy command when no crop or resize" do
        provider.convert_format("webp")
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("vips copy")
      end

      it "builds watermark composite2 command" do
        provider.add_watermark("watermark.png", position: "northwest")
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("composite2")
        expect(cmd).to include("watermark.png")
        expect(cmd).to include("over")
        expect(cmd).to include("--x 0 --y 0")
      end

      it "builds watermark with opacity preprocessing" do
        provider.add_watermark("watermark.png", position: "southeast",
                                                opacity: 0.5)
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("linear")
        expect(cmd).to include("composite2")
        expect(cmd).to include("0.5")
      end

      it "builds watermark with resize pipeline" do
        provider.resize(800, 600, scale_x: 0.5, scale_y: 0.5)
        provider.add_watermark("watermark.png", position: "center")
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("VipsResize")
        expect(cmd).to include("composite2")
        expect(cmd).to include("&&")
      end

      it "builds standalone alpha opacity command" do
        provider.alpha_opacity = 0.5
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("linear")
        expect(cmd).to include("0.5")
      end

      it "builds alpha opacity with resize pipeline" do
        provider.resize(800, 600, scale_x: 0.5, scale_y: 0.5)
        provider.alpha_opacity = 0.3
        cmd = provider.build_vips_command("input.jpg", "output.jpg")
        expect(cmd).to include("VipsResize")
        expect(cmd).to include("linear")
        expect(cmd).to include("0.3")
        expect(cmd).to include("&&")
      end
    end

    describe "#build_format_spec" do
      it "returns plain path when no format or quality ops" do
        expect(provider.build_format_spec("output.jpg")).to eq("output.jpg".shellescape)
      end

      it "builds spec with format" do
        provider.convert_format("webp")
        spec = provider.build_format_spec("/path/to/output.jpg")
        expect(spec).to include(".webp")
      end

      it "builds spec with quality" do
        provider.quality = 85
        spec = provider.build_format_spec("/path/to/output.jpg")
        expect(spec).to include("Q=85")
      end

      it "builds spec with both format and quality" do
        provider.convert_format("webp")
        provider.quality = 85
        spec = provider.build_format_spec("/path/to/output.jpg")
        expect(spec).to include(".webp")
        expect(spec).to include("Q=85")
      end
    end

    describe "#position_to_vips_xy" do
      it "translates compass directions to vips composite2 x/y args" do
        expect(provider.position_to_vips_xy("northwest", "/base.jpg",
                                            "/wm.png")).to eq("--x 0 --y 0")
        expect(provider.position_to_vips_xy("center", "/base.jpg",
                                            "/wm.png")).to eq("--x 0 --y 0")
        expect(provider.position_to_vips_xy("custom", "/base.jpg",
                                            "/wm.png")).to eq("--x 0 --y 0")
      end
    end

    describe "#execute_command" do
      it "raises on command failure" do
        expect { provider.execute_command("echo 'real error'; false") }
          .to raise_error(/LibVips command failed/)
      end

      it "continues on 'same file' warning" do
        expect(provider.execute_command("echo 'same file'; false")).to eq("same file")
      end

      it "continues on VipsForeignSave warning" do
        expect(provider.execute_command("echo 'VipsForeignSave'; false")).to eq("VipsForeignSave")
      end

      it "returns output on success" do
        expect(provider.execute_command("true")).to eq("")
      end
    end

    describe "#available?" do
      it "returns true when vips is available" do
        allow(Open3).to receive(:capture3).with("which", "vips")
                                          .and_return(["", "", double(success?: true)])
        expect(provider.available?).to be true
      end

      it "returns false when vips is not available" do
        allow(Open3).to receive(:capture3).with("which", "vips")
                                          .and_return(["", "", double(success?: false)])
        expect(provider.available?).to be false
      end
    end
  end

  # ============================================================
  # Sharp Provider
  # ============================================================
  describe JekyllImgFlow::Providers::Sharp do
    subject(:provider) { described_class.new(config) }

    describe "#build_sharp_command" do
      it "builds sequential crop+resize" do
        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800, calculated_height: 450)
        provider.resize(400, 225, scale_x: 0.5, scale_y: 0.5)
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("&&")
        expect(cmd).to include("extract")
        expect(cmd).to include("resize")
        expect(cmd).to include("rm -f")
      end

      it "builds resize with both dimensions" do
        provider.resize(400, 225)
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("resize")
        expect(cmd).to include("400")
        expect(cmd).to include("225")
      end

      it "builds resize with width only" do
        provider.resize(400, nil)
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("400")
      end

      it "builds resize with format and quality" do
        provider.resize(400, 225)
        provider.convert_format("webp")
        provider.quality = 80
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("-f webp")
        expect(cmd).to include("-q80")
      end

      it "builds resize with alpha opacity" do
        provider.resize(400, 225)
        provider.alpha_opacity = 0.5
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("alpha")
        expect(cmd).to include("{alpha:128}")
      end

      it "builds watermark composite command" do
        provider.add_watermark("watermark.png", position: "northwest")
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("composite")
        expect(cmd).to include("watermark.png")
        expect(cmd).to include("--gravity")
        expect(cmd).to include("northwest")
        expect(cmd).to include("--blend")
        expect(cmd).to include("over")
      end

      it "builds watermark with opacity preprocessing" do
        provider.add_watermark("watermark.png", position: "southeast",
                                                opacity: 0.5)
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("ensureAlpha")
        expect(cmd).to include("composite")
        expect(cmd).to include("--gravity")
        expect(cmd).to include("southeast")
      end

      it "builds watermark with resize pipeline" do
        provider.resize(800, 600)
        provider.add_watermark("watermark.png", position: "center")
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("resize")
        expect(cmd).to include("composite")
        expect(cmd).to include("&&")
      end

      it "builds watermark with format and quality" do
        provider.add_watermark("watermark.png", position: "northwest")
        provider.convert_format("webp")
        provider.quality = 80
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("composite")
        expect(cmd).to include("-f webp")
        expect(cmd).to include("-q80")
      end

      it "builds smartcrop (attention)" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "attention")
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("smartcrop")
        expect(cmd).to include("--interesting=attention")
      end

      it "builds smartcrop (entropy)" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "entropy")
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("--interesting=entropy")
      end

      it "builds smartcrop (centre)" do
        provider.crop("16:9", calculated_width: 800, calculated_height: 450,
                              keep: "centre")
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("--interesting=centre")
      end

      it "builds basic extract (ratio)" do
        provider.crop("16:9", calculated_x: 50, calculated_y: 0,
                              calculated_width: 800, calculated_height: 450)
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("extract")
        expect(cmd).to include("0 50 800 450")
      end

      it "builds basic extract (no ratio)" do
        provider.crop(nil, x: 10, y: 20, width: 100, height: 80)
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("extract")
        expect(cmd).to include("20 10 100 80")
      end

      it "builds extract with default x/y=0" do
        provider.crop(nil, width: 100, height: 80)
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("0 0 100 80")
      end

      it "builds copy command with format" do
        provider.convert_format("webp")
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("-f webp")
      end

      it "builds copy command with quality" do
        provider.quality = 80
        cmd = provider.build_sharp_command("input.jpg", "output.jpg")
        expect(cmd).to include("-q80")
      end
    end

    describe "#available?" do
      it "returns true when sharp is available" do
        allow(Open3).to receive(:capture3).with("which", "sharp")
                                          .and_return(["", "", double(success?: true)])
        expect(provider.available?).to be true
      end

      it "returns false when sharp is not available" do
        allow(Open3).to receive(:capture3).with("which", "sharp")
                                          .and_return(["", "", double(success?: false)])
        expect(provider.available?).to be false
      end
    end
  end

  # ============================================================
  # BaseProvider shared methods
  # ============================================================
  describe JekyllImgFlow::Providers::BaseProvider do
    subject(:provider) { described_class.new(config) }

    describe "#check_http_service" do
      it "returns false for nil url" do
        expect(provider.check_http_service(nil)).to be false
      end

      it "returns true when service responds" do
        stub_request(:get, "http://localhost:33001/").to_return(status: 200)
        expect(provider.check_http_service("http://localhost:33001")).to be true
      end

      it "returns false on connection failure" do
        stub_request(:get, "http://localhost:99999/").to_raise(Errno::ECONNREFUSED)
        expect(provider.check_http_service("http://localhost:99999")).to be false
      end
    end

    describe "#encode_file_url" do
      it "returns HTTP URLs as-is" do
        expect(provider.encode_file_url("http://example.com/image.jpg"))
          .to eq("http://example.com/image.jpg")
      end

      it "returns HTTPS URLs as-is" do
        expect(provider.encode_file_url("https://example.com/image.jpg"))
          .to eq("https://example.com/image.jpg")
      end

      it "constructs URL from absolute path" do
        url = provider.encode_file_url("/tmp/test_site/assets/images/test.jpg")
        expect(url).to include("assets/images/test.jpg")
      end

      it "constructs URL from relative path" do
        url = provider.encode_file_url("assets/images/test.jpg")
        expect(url).to include("assets/images/test.jpg")
      end

      it "constructs URL from root-relative path" do
        url = provider.encode_file_url("/assets/images/test.jpg")
        expect(url).to include("assets/images/test.jpg")
      end

      it "URL-encodes path segments with spaces" do
        url = provider.encode_file_url("assets/images/my test.jpg")
        expect(url).to include("my+test.jpg")
      end
    end

    describe "#get_image_dimensions" do
      it "raises ArgumentError for non-existent file" do
        expect { provider.send(:get_image_dimensions, "/nonexistent.jpg") }
          .to raise_error(ArgumentError, /Unable to read image dimensions/)
      end
    end

    describe "#execute" do
      it "raises NotImplementedError" do
        expect { provider.execute("in.jpg", "out.jpg") }.to raise_error(NotImplementedError)
      end
    end

    describe "#supports_operation?" do
      it "returns true for supported operations" do
        expect(described_class.supports_operation?(:resize)).to be true
      end

      it "returns false for unsupported operations" do
        allow(described_class).to receive(:unsupported_operations).and_return([:crop])
        expect(described_class.supports_operation?(:crop)).to be false
      end
    end

    describe "operation collection" do
      it "collects resize with options" do
        provider.resize(800, 600, gravity: "center")
        op = provider.operations.last
        expect(op[:type]).to eq(:resize)
        expect(op[:width]).to eq(800)
        expect(op[:height]).to eq(600)
        expect(op[:options]).to eq(gravity: "center")
      end

      it "collects crop with ratio and options hash" do
        provider.crop("16:9", calculated_width: 800)
        op = provider.operations.last
        expect(op[:type]).to eq(:crop)
        expect(op[:ratio]).to eq("16:9")
      end

      it "collects crop with pixel dimensions" do
        provider.crop(100, 80, 10, 20)
        op = provider.operations.last
        expect(op[:type]).to eq(:crop)
        expect(op[:ratio]).to be_nil
        expect(op[:options][:width]).to eq(100)
        expect(op[:options][:height]).to eq(80)
      end

      it "collects crop with ratio only (no options)" do
        provider.crop("16:9")
        op = provider.operations.last
        expect(op[:type]).to eq(:crop)
        expect(op[:ratio]).to eq("16:9")
        expect(op[:options]).to eq({})
      end

      it "collects quality via setter" do
        provider.quality = 85
        op = provider.operations.last
        expect(op[:type]).to eq(:quality)
        expect(op[:quality]).to eq(85)
      end

      it "collects quality via method" do
        provider.quality(90)
        op = provider.operations.last
        expect(op[:type]).to eq(:quality)
        expect(op[:quality]).to eq(90)
      end

      it "collects format via convert_format" do
        provider.convert_format("webp")
        op = provider.operations.last
        expect(op[:type]).to eq(:format)
        expect(op[:format]).to eq("webp")
      end

      it "collects format via format method" do
        provider.format("avif")
        op = provider.operations.last
        expect(op[:type]).to eq(:format)
        expect(op[:format]).to eq("avif")
      end

      it "collects optimize" do
        provider.optimize(:high)
        op = provider.operations.last
        expect(op[:type]).to eq(:optimize)
        expect(op[:level]).to eq(:high)
      end

      it "collects opacity via method" do
        provider.opacity(0.5)
        op = provider.operations.last
        expect(op[:type]).to eq(:alpha_opacity)
        expect(op[:opacity]).to eq(0.5)
      end

      it "collects watermark via add_watermark" do
        provider.add_watermark("wm.png", opacity: 0.5)
        op = provider.operations.last
        expect(op[:type]).to eq(:watermark)
        expect(op[:watermark_path]).to eq("wm.png")
      end

      it "collects watermark via watermark method" do
        provider.watermark("wm.png", position: "center")
        op = provider.operations.last
        expect(op[:type]).to eq(:watermark)
      end

      it "collects alpha_opacity via setter" do
        provider.alpha_opacity = 0.8
        op = provider.operations.last
        expect(op[:type]).to eq(:alpha_opacity)
        expect(op[:opacity]).to eq(0.8)
      end

      it "supports_operation? delegates to class" do
        expect(provider.supports_operation?(:resize)).to be true
      end

      it "reset_operations clears operations" do
        provider.resize(800, 600)
        provider.reset_operations
        expect(provider.operations).to be_empty
      end

      it "operations returns a dup" do
        provider.resize(800, 600)
        ops = provider.operations
        ops.clear
        expect(provider.operations).not_to be_empty
      end
    end
  end
end
