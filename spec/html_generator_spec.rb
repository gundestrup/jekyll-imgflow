# frozen_string_literal: true

require "spec_helper"

RSpec.describe "JekyllImgFlow::HtmlGenerator", :unit do
  # Use TestPictures for realistic filename patterns with JPT hashes
  let(:test_image_name) { "mars-crater-large.jpg" }
  let(:test_results) do
    # Generate realistic optimized filenames using TestPictures (raster formats only)
    [
      "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :md, :webp)}",
      "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :md, :avif)}",
      "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :md, :jpg)}",
      "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :lg, :webp)}",
      "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :lg, :avif)}",
      "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :lg, :jpg)}",
      # Add PNG format for non-fallback testing
      "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :md, :png)}",
      "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :lg, :png)}"
    ]
  end

  # Use standardized RSpec helper for site creation with proper URL config
  let(:site) { create_mock_site(config: { "url" => "https://example.com" }) }
  let(:context) do
    double("context", registers: { site: site })
  end

  # Use proper config with TestPictures formats
  let(:config) do
    double("config", formats: %w[avif webp png jpg], fallback_format: "jpg")
  end

  let(:attributes) do
    {
      img: { "class" => "responsive", "alt" => "Test Image" },
      picture: { "class" => "picture-wrapper" }
    }
  end

  describe ".generate" do
    context "with img format" do
      it "generates img element with srcset" do
        html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "img", context,
                                                     config)

        expect(html).to include("<img")
        expect(html).to include('class="responsive"')
        expect(html).to include('alt="Test Image"')
        expect(html).to include("src=\"assets/images/optimized/#{TestPictures.expected_filename(
          test_image_name, :md, :webp
        )}\"")
        expect(html).to include("srcset=")
        expect(html).to include("loading=\"lazy\"")
      end
    end

    context "with picture format" do
      it "generates picture element with sources for all non-fallback formats" do
        html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "picture", context,
                                                     config)

        expect(html).to include("<picture")
        expect(html).to include('class="picture-wrapper"')
        expect(html).to include("<source")
        # Modern formats get <source> tags
        expect(html).to include("type=\"image/webp\"")
        expect(html).to include("type=\"image/avif\"")
        expect(html).to include("type=\"image/png\"")
        # jpg is the fallback format — should NOT get a <source> tag
        expect(html).not_to include("type=\"image/jpeg\"")
        expect(html).to include("<img")
        expect(html).to include('class="responsive"')
      end

      it "emits <source> tags in priority order: avif, webp, png" do
        html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "picture", context,
                                                     config)

        # The browser picks the first <source> it supports, so order matters:
        # avif (best compression) → webp (wide support) → png (transparency)
        avif_pos = html.index('type="image/avif"')
        webp_pos = html.index('type="image/webp"')
        png_pos = html.index('type="image/png"')

        expect(avif_pos).not_to be_nil, "avif <source> not found"
        expect(webp_pos).not_to be_nil, "webp <source> not found"
        expect(png_pos).not_to be_nil, "png <source> not found"
        expect(avif_pos).to be < webp_pos,
                            "avif <source> must come before webp (avif at #{avif_pos}, webp at #{webp_pos})"
        expect(webp_pos).to be < png_pos,
                            "webp <source> must come before png (webp at #{webp_pos}, png at #{png_pos})"
      end
    end

    context "without config" do
      it "uses default fallback formats" do
        html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "picture", context,
                                                     nil)

        expect(html).to include("<picture")
        expect(html).to include("<source")
        # Should skip .jpg, .jpeg, .png as fallback formats
        expect(html).not_to include("type=\"image/jpeg\"")
      end
    end

    context "with empty results" do
      it "returns empty string" do
        html = JekyllImgFlow::HtmlGenerator.generate([], attributes, "img", context, config)
        expect(html).to eq("")
      end
    end
  end

  describe "config integration" do
    context "with custom formats" do
      let(:custom_config) do
        double("config", formats: %w[avif webp png], fallback_format: "jpg")
      end

      it "uses fallback_format for <img> and other formats for <source>" do
        html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "picture", context,
                                                     custom_config)

        expect(html).to include("<picture")
        # Only jpg is the fallback format — all others get <source> tags
        expect(html).to include("type=\"image/webp\"")
        expect(html).to include("type=\"image/png\"")
        expect(html).to include("type=\"image/avif\"")
        # jpg should NOT get a <source> tag — it's the <img> fallback
        expect(html).not_to include("type=\"image/jpeg\"")
      end
    end

    context "with png as fallback_format" do
      let(:png_fallback_config) do
        double("config", formats: %w[avif webp jpg png], fallback_format: "png")
      end

      it "uses png for <img> fallback and serves webp/avif/jpg via <source>" do
        html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "picture", context,
                                                     png_fallback_config)

        expect(html).to include("<picture")
        # webp, avif, jpg all get <source> tags
        expect(html).to include("type=\"image/webp\"")
        expect(html).to include("type=\"image/avif\"")
        expect(html).to include("type=\"image/jpeg\"")
        # png should NOT get a <source> tag — it's the <img> fallback
        expect(html).not_to include("type=\"image/png\"")
        # <img> should use a png file
        expect(html).to include("src=\"assets/images/optimized/")
        # Find the img src and verify it ends with .png
        img_src = html.match(/<img src="([^"]+)"/)
        expect(img_src).not_to be_nil
        expect(img_src[1]).to end_with(".png")
      end
    end
  end

  describe "different markup formats" do
    it "handles data_img format" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "data_img", context,
                                                   config)

      expect(html).to include("<img")
      expect(html).to include("data-src=\"")
    end

    it "handles data_picture format" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "data_picture",
                                                   context, config)

      expect(html).to include("<picture")
      expect(html).to include("data-srcset=\"")
    end

    it "handles direct_url format" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, {}, "direct_url", context, config)

      expect(html).to eq("https://example.com/assets/images/optimized/#{TestPictures.expected_filename(
        test_image_name, :md, :webp
      )}")
    end

    it "handles naked_srcset format" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, {}, "naked_srcset", context,
                                                   config)

      expect(html).to include("https://example.com")
      expect(html).to include("800w")
      expect(html).to include("1200w")
      expect(html).not_to include("<")
      expect(html).not_to include(">")
    end
  end

  describe "attribute handling" do
    context "with link wrapping" do
      let(:link_attributes) do
        {
          img: { "alt" => "Linked Image" },
          a: { "href" => "/gallery", "class" => "gallery-link" },
          link: "/gallery"
        }
      end

      it "wraps img in link" do
        html = JekyllImgFlow::HtmlGenerator.generate(test_results, link_attributes, "img", context,
                                                     config)

        expect(html).to include("<a")
        expect(html).to include('href="/gallery"')
        expect(html).to include('class="gallery-link"')
        expect(html).to include("<img")
      end
    end

    context "with parent container" do
      let(:parent_attributes) do
        {
          img: { "alt" => "Container Image" },
          parent: { "class" => "image-wrapper", "data-component" => "image" }
        }
      end

      it "wraps in parent container" do
        html = JekyllImgFlow::HtmlGenerator.generate(test_results, parent_attributes, "img",
                                                     context, config)

        expect(html).to include("<div")
        expect(html).to include('class="image-wrapper"')
        expect(html).to include('data-component="image"')
        expect(html).to include("<img")
      end
    end
  end

  describe "fallback behavior" do
    let(:mixed_results) do
      [
        "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :md, :webp)}",
        "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :md, :jpg)}",
        "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :lg, :webp)}",
        "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :lg, :jpg)}",
        "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :md, :png)}", # Non-fallback for sources
        "/assets/images/optimized/#{TestPictures.expected_filename(test_image_name, :lg, :png)}" # Non-fallback for sources
      ]
    end

    it "finds appropriate fallback image and generates sources" do
      html = JekyllImgFlow::HtmlGenerator.generate(mixed_results, attributes, "picture", context,
                                                   config)

      expect(html).to include("<picture")
      expect(html).to include("<source")
      expect(html).to include("type=\"image/png\"")
      expect(html).to include("<img")
      # Should use jpg as fallback
      expect(html).to include("src=\"assets/images/optimized/#{TestPictures.expected_filename(
        test_image_name, :md, :jpg
      )}\"")
    end
  end

  describe "realistic filename patterns" do
    it "uses JPT hash patterns in generated HTML" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "img", context, config)

      # Should contain the actual JPT hash from TestPictures
      expected_webp = TestPictures.expected_filename(test_image_name, :md, :webp)
      expect(expected_webp).to include("f33ea0792") # JPT hash for mars-crater-large.jpg
      expect(html).to include(expected_webp)
    end

    it "generates correct srcset with multiple sizes and formats" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "img", context, config)

      # Should include both md and lg sizes with different formats
      md_webp = TestPictures.expected_filename(test_image_name, :md, :webp)
      lg_webp = TestPictures.expected_filename(test_image_name, :lg, :webp)

      expect(html).to include(md_webp)
      expect(html).to include(lg_webp)
      expect(html).to include("srcset=")
    end

    it "handles different image types with correct hashes" do
      # Test with a different image to verify hash uniqueness
      png_results = [
        "/assets/images/optimized/#{TestPictures.expected_filename('file_example-large.png', :md,
                                                                   :webp)}",
        "/assets/images/optimized/#{TestPictures.expected_filename('file_example-large.png', :md,
                                                                   :jpg)}"
      ]

      html = JekyllImgFlow::HtmlGenerator.generate(png_results, attributes, "img", context, config)

      # Should use the correct hash for file_example-large.png
      expected_png_webp = TestPictures.expected_filename("file_example-large.png", :md, :webp)
      expect(expected_png_webp).to include("aa4ec6a4c") # JPT hash for file_example-large.png
      expect(html).to include(expected_png_webp)
    end
  end

  describe "security and edge cases" do
    it "escapes HTML attributes properly" do
      malicious_attrs = {
        img: {
          "alt" => "<script>alert('xss')</script>",
          "class" => "img\" onerror=\"alert('xss')",
          "data-test" => "test&value"
        }
      }

      html = JekyllImgFlow::HtmlGenerator.generate(test_results, malicious_attrs, "img", context,
                                                   config)

      # Should escape dangerous characters
      expect(html).not_to include("<script>")
      # NOTE: onerror appears in escaped form within the attribute value
      expect(html).to include("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")
      expect(html).to include("img&quot; onerror=&quot;alert(&#39;xss&#39;)")
      expect(html).to include("test&amp;value")
    end

    it "escapes link attributes properly" do
      link_attrs = {
        img: { "alt" => "Safe Image" },
        link: "/path?param=<script>alert('xss')</script>",
        a: { "data-test" => "value\" onclick='alert()'" }
      }

      html = JekyllImgFlow::HtmlGenerator.generate(test_results, link_attrs, "img", context, config)

      # Should escape dangerous characters in link href and attributes
      expect(html).not_to include("<script>")
      expect(html).to include("/path?param=&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")
      expect(html).to include("value&quot; onclick=&#39;alert()")
      expect(html).to include("<a")
      expect(html).to include("</a>")
      # The onclick appears in escaped form within the attribute value, which is expected
    end

    it "handles invalid markup format gracefully" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "invalid_format",
                                                   context, config)

      # Should fallback to img element
      expect(html).to include("<img")
      expect(html).to include("src=")
      expect(html).to include('class="responsive"')
    end

    it "handles unknown markup format gracefully" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "unknown_format_xyz",
                                                   context, config)

      # Should fallback to img element
      expect(html).to include("<img")
      expect(html).not_to include("<picture")
      expect(html).not_to include("data-src")
    end

    it "handles nil context gracefully" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "direct_url", nil,
                                                   config)

      # Should return the path as-is when no context (includes leading slash)
      expected_filename = TestPictures.expected_filename(test_image_name, :md, :webp)
      expect(html).to eq("/assets/images/optimized/#{expected_filename}")
    end

    it "handles context without site gracefully" do
      bad_context = double("context", registers: {})
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "direct_url",
                                                   bad_context, config)

      # Should return the path as-is when no site in context (includes leading slash)
      expected_filename = TestPictures.expected_filename(test_image_name, :md, :webp)
      expect(html).to eq("/assets/images/optimized/#{expected_filename}")
    end

    it "handles empty attributes hash gracefully" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, {}, "img", context, config)

      # Should generate valid HTML with default attributes
      expect(html).to include("<img")
      expect(html).to include("src=")
      expect(html).to include("loading=\"lazy\"") # Default loading attribute
      expect(html).not_to include("alt=") # No alt when not provided
    end

    it "handles nil attributes gracefully" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, nil, "img", context, config)

      # Should generate valid HTML with default attributes
      expect(html).to include("<img")
      expect(html).to include("src=")
      expect(html).to include("loading=\"lazy\"")
    end

    it "handles malformed file extensions in MIME type detection" do
      # Test with unknown file extension
      malformed_results = ["/assets/images/optimized/test-image.unknown"]
      html = JekyllImgFlow::HtmlGenerator.generate(malformed_results, attributes, "picture",
                                                   context, config)

      # Should still generate HTML, MIME type might default to image/jpeg
      expect(html).to include("<picture")
      expect(html).to include("<img")
    end

    it "handles uppercase file extensions" do
      # Test with uppercase extensions - use config that allows webp as source
      uppercase_config = double("config", formats: %w[avif webp png jpg],
                                          fallback_format: "jpg")
      uppercase_results = [
        "/assets/images/optimized/test-image.WEBP",
        "/assets/images/optimized/test-image.AVIF",
        "/assets/images/optimized/test-image.JPG"
      ]
      html = JekyllImgFlow::HtmlGenerator.generate(uppercase_results, attributes, "picture",
                                                   context, uppercase_config)

      # Should handle uppercase extensions correctly
      expect(html).to include("<picture")
      expect(html).to include("type=\"image/webp\"")
      expect(html).to include("type=\"image/avif\"")
      expect(html).to include("<img")
    end

    it "handles special characters in filenames" do
      # Test with special characters in filenames (though unlikely in practice)
      special_results = ["/assets/images/optimized/test image-800.webp"]
      html = JekyllImgFlow::HtmlGenerator.generate(special_results, attributes, "img", context,
                                                   config)

      # Should still generate valid HTML
      expect(html).to include("<img")
      expect(html).to include("src=")
    end
  end

  describe "data_auto format" do
    it "generates data_img element for data_auto" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "data_auto",
                                                   context, config)
      expect(html).to include("<img")
      expect(html).to include("data-src=")
    end
  end

  describe "build_data_img_attributes" do
    it "adds lazy class to existing class" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attributes, "data_img",
                                                   context, config)
      expect(html).to include("class=\"responsive lazy\"")
    end

    it "adds lazy class when no existing class" do
      attrs = { img: { "alt" => "Test" } }
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attrs, "data_img",
                                                   context, config)
      expect(html).to include("class=\"lazy\"")
    end
  end

  describe "mime_type_for" do
    it "returns correct mime types" do
      generator = JekyllImgFlow::HtmlGenerator.new(test_results, attributes, "picture",
                                                   context, config)
      expect(generator.send(:mime_type_for, ".webp")).to eq("image/webp")
      expect(generator.send(:mime_type_for, ".avif")).to eq("image/avif")
      expect(generator.send(:mime_type_for, ".png")).to eq("image/png")
      expect(generator.send(:mime_type_for, ".jpg")).to eq("image/jpeg")
      expect(generator.send(:mime_type_for, ".jpeg")).to eq("image/jpeg")
      expect(generator.send(:mime_type_for, ".gif")).to eq("image/gif")
      expect(generator.send(:mime_type_for, ".svg")).to eq("image/svg+xml")
      expect(generator.send(:mime_type_for, ".jp2")).to eq("image/jp2")
      expect(generator.send(:mime_type_for, ".jxr")).to eq("image/jxr")
      expect(generator.send(:mime_type_for, ".unknown")).to eq("image/jpeg")
    end
  end

  describe "absolute_url with baseurl" do
    let(:site_with_baseurl) do
      create_mock_site(config: { "url" => "https://example.com", "baseurl" => "/blog" })
    end
    let(:context_with_baseurl) do
      double("context", registers: { site: site_with_baseurl })
    end

    it "includes baseurl in generated URLs" do
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, {}, "direct_url",
                                                   context_with_baseurl, config)
      expect(html).to start_with("https://example.com/blog/")
    end
  end

  describe "extract_width_from_filename" do
    it "extracts width from JPT hash filename" do
      generator = JekyllImgFlow::HtmlGenerator.new(test_results, attributes, "img",
                                                   context, config)
      filename = TestPictures.expected_filename(test_image_name, :md, :webp)
      width = generator.send(:extract_width_from_filename, filename)
      expect(width).to eq(800)
    end

    it "returns nil for filename without width pattern" do
      generator = JekyllImgFlow::HtmlGenerator.new(test_results, attributes, "img",
                                                   context, config)
      width = generator.send(:extract_width_from_filename, "simple-image.webp")
      expect(width).to be_nil
    end
  end

  describe "html_path" do
    it "removes leading slash" do
      generator = JekyllImgFlow::HtmlGenerator.new(test_results, attributes, "img",
                                                   context, config)
      expect(generator.send(:html_path, "/assets/img.webp")).to eq("assets/img.webp")
    end

    it "keeps relative path as-is" do
      generator = JekyllImgFlow::HtmlGenerator.new(test_results, attributes, "img",
                                                   context, config)
      expect(generator.send(:html_path, "assets/img.webp")).to eq("assets/img.webp")
    end
  end

  describe "build_attributes edge cases" do
    it "handles boolean true attributes" do
      attrs = { img: { "async" => true, "class" => "test" } }
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attrs, "img", context, config)
      expect(html).to include(" async")
    end

    it "skips false and nil attributes" do
      attrs = { img: { "hidden" => false, "data-nil" => nil, "class" => "test" } }
      html = JekyllImgFlow::HtmlGenerator.generate(test_results, attrs, "img", context, config)
      expect(html).not_to include("hidden")
      expect(html).not_to include("data-nil")
    end
  end
end
