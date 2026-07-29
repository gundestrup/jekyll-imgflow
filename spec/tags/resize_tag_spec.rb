# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::Tags::ResizeTag, :unit do
  let(:site) do
    double("site", config: TEST_CONFIG, source: "/tmp/test_site",
                   dest: "/tmp/test_site/_site")
  end
  let(:config) { JekyllImgFlow::Config.new(site) }
  let(:provider) { JekyllImgFlow::ProviderRegistry.new(config).current_provider }
  let(:tag) { described_class.new(provider) }

  describe "#process" do
    let(:test_image_dir) { create_test_dir("resize-tag-test") }
    let(:input_path) { File.join(test_image_dir, config.originals, "test.jpg") }
    let(:output_path) { File.join(test_image_dir, config.output, "test-800-a1b2c3d4e.jpg") }
    let(:original_image) do
      File.expand_path("../fixtures/originals/mars-crater-large.jpg", __dir__)
    end

    before do
      # Create test directories and copy test image
      FileUtils.mkdir_p(File.dirname(input_path))
      FileUtils.cp(original_image, input_path)
      FileUtils.mkdir_p(File.dirname(output_path))
    end

    after do
      FileUtils.rm_rf(test_image_dir)
    end

    context "with valid width and height" do
      let(:options) { { width: 800, height: 600 } }

      it "resizes image and verifies dimensions" do
        # Process the resize
        result = tag.process(input_path, output_path, options)

        # Verify output file exists
        expect(File.exist?(output_path)).to be true
        expect(File.size(output_path)).to be > 1000

        # Verify dimensions using helper method
        valid = validate_resize_operation(original_image, output_path, 800, 600,
                                          maintain_aspect: false)
        expect(valid).to be true

        # Verify format is still JPEG
        expect_file_signature(output_path, "jpeg")

        expect(result).to eq(output_path) # process method returns output path
      end

      context "with only width" do
        let(:options) { { width: 800 } }

        it "maintains aspect ratio automatically" do
          tag.process(input_path, output_path, options)

          # Verify output exists and has correct dimensions
          expect(File.exist?(output_path)).to be true

          # Use helper to validate aspect ratio is maintained
          valid = validate_resize_operation(original_image, output_path, 800, nil,
                                            maintain_aspect: true)
          expect(valid).to be true
        end

        context "with only height" do
          let(:options) { { height: 600 } }

          it "treats height as width constraint and maintains aspect ratio" do
            tag.process(input_path, output_path, options)

            # Verify output exists and has correct dimensions
            expect(File.exist?(output_path)).to be true

            # Debug: check actual dimensions
            get_image_dimensions(output_path)

            # Use helper to validate dimensions are calculated correctly
            # When height=600, width should be calculated to maintain aspect ratio
            original_width, original_height = get_image_dimensions(original_image)
            expected_width = (600 * original_width.to_f / original_height).round

            valid = validate_image_dimensions(output_path, expected_width, 600, tolerance: 2)
            expect(valid).to be true

            expect_file_signature(output_path, "jpeg")
          end
        end

        context "with invalid width" do
          let(:options) { { width: -100 } }

          it "raises validation error" do
            expect do
              tag.process(input_path, output_path, options)
            end.to raise_error(ArgumentError, /Invalid width/)
          end
        end

        context "with invalid height" do
          let(:options) { { width: 800, height: 0 } }

          it "raises validation error" do
            expect do
              tag.process(input_path, output_path, options)
            end.to raise_error(ArgumentError, /Invalid height/)
          end
        end

        context "with no dimensions" do
          let(:options) { {} }

          it "raises validation error" do
            expect do
              tag.process(input_path, output_path,
                          options)
            end.to raise_error(ArgumentError, /Either width or height must be specified/)
          end
        end
      end
    end

    describe "#validate_positive_integer" do
      it "accepts positive integers" do
        result = tag.send(:validate_positive_integer, 800, "width")
        expect(result).to eq(800)
      end

      it "accepts positive strings" do
        result = tag.send(:validate_positive_integer, "800", "width")
        expect(result).to eq(800)
      end

      it "rejects negative numbers" do
        expect do
          tag.send(:validate_positive_integer, -100,
                   "width")
        end.to raise_error(ArgumentError, /Invalid width/)
      end

      it "rejects zero" do
        expect do
          tag.send(:validate_positive_integer, 0, "width")
        end.to raise_error(ArgumentError, /Invalid width/)
      end

      it "rejects non-integer strings" do
        expect do
          tag.send(:validate_positive_integer, "abc",
                   "width")
        end.to raise_error(ArgumentError, /Invalid width/)
      end

      it "accepts nil" do
        result = tag.send(:validate_positive_integer, nil, "width")
        expect(result).to be_nil
      end
    end
  end
end
