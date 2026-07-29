# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe JekyllImgFlow::Helpers::HttpDownloader, :external, :unit do
  describe ".download" do
    let(:http_url) { "https://example.com/image.jpg" }
    let(:file_url) { "file:///tmp/local_image.jpg" }

    context "HTTP/HTTPS URLs" do
      it "downloads file from HTTP URL" do
        stub_request(:get, http_url)
          .to_return(status: 200, body: "fake image content")

        result = described_class.download(http_url)

        expect(result).to be_a(String)
        expect(result).to include(Dir.tmpdir)
        expect(result).to include("imgflow-")
        expect(result).to end_with(".jpg")
        expect(File.exist?(result)).to be true
        expect(File.read(result, mode: "rb")).to eq("fake image content")

        # Cleanup
        FileUtils.rm_f(result)
      end

      it "preserves file extension" do
        webp_url = "https://example.com/image.webp"
        stub_request(:get, webp_url)
          .to_return(status: 200, body: "webp content")

        result = described_class.download(webp_url)

        expect(result).to end_with(".webp")

        FileUtils.rm_f(result)
      end

      it "generates unique temporary filenames" do
        stub_request(:get, http_url)
          .to_return(status: 200, body: "content")

        result1 = described_class.download(http_url)
        result2 = described_class.download(http_url)

        expect(result1).not_to eq(result2)

        FileUtils.rm_f(result1)
        FileUtils.rm_f(result2)
      end

      it "handles HTTP redirects" do
        redirect_url = "https://example.com/redirect"
        final_url = "https://example.com/final.jpg"

        stub_request(:get, redirect_url)
          .to_return(status: 302, headers: { "Location" => final_url })

        stub_request(:get, final_url)
          .to_return(status: 200, body: "final content")

        result = described_class.download(redirect_url)

        expect(File.read(result, mode: "rb")).to eq("final content")

        FileUtils.rm_f(result)
      end

      it "handles relative redirects" do
        redirect_url = "https://example.com/redirect"

        stub_request(:get, redirect_url)
          .to_return(status: 302, headers: { "Location" => "/final.jpg" })

        stub_request(:get, "https://example.com/final.jpg")
          .to_return(status: 200, body: "final content")

        result = described_class.download(redirect_url)

        expect(File.read(result, mode: "rb")).to eq("final content")

        FileUtils.rm_f(result)
      end

      it "raises error on HTTP failure" do
        stub_request(:get, http_url)
          .to_return(status: 404, body: "Not Found")

        expect do
          described_class.download(http_url)
        end.to raise_error(/HTTP request failed/)
      end

      it "raises error on network failure" do
        stub_request(:get, http_url)
          .to_raise(SocketError.new("Network error"))

        expect do
          described_class.download(http_url)
        end.to raise_error(/Failed to download/)
      end

      it "cleans up temp file on error" do
        stub_request(:get, http_url)
          .to_return(status: 500)

        begin
          described_class.download(http_url)
        rescue StandardError
          # Expected to fail
        end

        # Check that no temp files were left behind
        temp_files = Dir.glob(File.join(Dir.tmpdir, "imgflow-*.jpg"))
        expect(temp_files).to be_empty
      end
    end

    context "file:// URLs" do
      let(:source_file) { File.join(Dir.tmpdir, "source_image.jpg") }

      before do
        File.write(source_file, "local file content")
      end

      after do
        FileUtils.rm_f(source_file)
      end

      it "copies local file to temp location" do
        file_url = "file://#{source_file}"
        result = described_class.download(file_url)

        expect(result).to be_a(String)
        expect(result).to include(Dir.tmpdir)
        expect(result).to include("imgflow-")
        expect(File.exist?(result)).to be true
        expect(File.read(result)).to eq("local file content")

        FileUtils.rm_f(result)
      end

      it "preserves file extension from local file" do
        png_file = File.join(Dir.tmpdir, "source.png")
        File.write(png_file, "png content")

        file_url = "file://#{png_file}"
        result = described_class.download(file_url)

        expect(result).to end_with(".png")

        FileUtils.rm_f(png_file)
        FileUtils.rm_f(result)
      end

      it "handles file:// URLs without extension" do
        no_ext_file = File.join(Dir.tmpdir, "noextension")
        File.write(no_ext_file, "content")

        file_url = "file://#{no_ext_file}"
        result = described_class.download(file_url)

        expect(File.exist?(result)).to be true

        FileUtils.rm_f(no_ext_file)
        FileUtils.rm_f(result)
      end
    end

    context "error handling" do
      it "raises error for invalid URL scheme" do
        expect do
          described_class.download("ftp://example.com/file.jpg")
        end.to raise_error
      end

      it "raises error for malformed URL" do
        expect do
          described_class.download("not a url")
        end.to raise_error
      end

      it "handles redirect without location header" do
        stub_request(:get, http_url)
          .to_return(status: 302, headers: {})

        expect do
          described_class.download(http_url)
        end.to raise_error(/Redirect without location/)
      end
    end

    context "binary content" do
      it "handles binary image data correctly" do
        # Simulate binary image data
        binary_data = (+"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR").force_encoding("BINARY")

        stub_request(:get, http_url)
          .to_return(status: 200, body: binary_data)

        result = described_class.download(http_url)

        downloaded_data = File.read(result, mode: "rb")
        expect(downloaded_data).to eq(binary_data)

        FileUtils.rm_f(result)
      end

      it "preserves binary encoding" do
        binary_content = (0..255).to_a.pack("C*")

        stub_request(:get, http_url)
          .to_return(status: 200, body: binary_content)

        result = described_class.download(http_url)

        downloaded = File.read(result, mode: "rb")
        expect(downloaded.encoding).to eq(Encoding::BINARY)
        expect(downloaded).to eq(binary_content)

        FileUtils.rm_f(result)
      end
    end

    context "performance" do
      it "downloads large files efficiently" do
        large_content = "x" * (1024 * 1024) # 1MB

        stub_request(:get, http_url)
          .to_return(status: 200, body: large_content)

        start_time = Time.now
        result = described_class.download(http_url)
        duration = Time.now - start_time

        expect(duration).to be < 5 # Should complete in under 5 seconds
        expect(File.size(result)).to eq(large_content.size)

        FileUtils.rm_f(result)
      end
    end

    context "concurrent downloads" do
      it "handles multiple simultaneous downloads" do
        stub_request(:get, http_url)
          .to_return(status: 200, body: "content")

        threads = Array.new(5) do |_i|
          Thread.new do
            described_class.download(http_url)
          end
        end

        results = threads.map(&:value)

        expect(results.length).to eq(5)
        expect(results.uniq.length).to eq(5) # All unique temp files

        results.each { |r| FileUtils.rm_f(r) }
      end
    end
  end
end
