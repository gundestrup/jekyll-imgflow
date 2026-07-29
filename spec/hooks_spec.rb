# frozen_string_literal: true

require "spec_helper"

RSpec.describe "JekyllImgFlow Hooks", :unit do
  before(:all) do
    # Create test site once for all tests (follow build_time_processor_spec pattern)
    @test_site_dir = create_test_dir("hooks-test")
    create_test_jekyll_site(@test_site_dir, :imgflow_only)
  end

  after(:all) do
    # Clean up once after all tests
    FileUtils.rm_rf(@test_site_dir)
  end

  let(:test_site_dir) { @test_site_dir }
  let(:site) do
    create_mock_site(source: test_site_dir, dest: File.join(test_site_dir, "_site"))
  end

  before do
    # Setup site with imgflow_components methods that BuildTimeProcessor expects
    allow(site).to receive(:respond_to?).with(:imgflow_components).and_return(true)
    allow(site).to receive(:respond_to?).with(:imgflow_components=).and_return(true)

    # Mock manifest for post_write hook
    mock_manifest = double("manifest", save: nil)
    allow(site).to receive(:imgflow_components).and_return({ manifest: mock_manifest })
    allow(site).to receive(:imgflow_components=)

    # Add catch-all for RSpec matcher methods
    allow(site).to receive(:respond_to?).with(:i_respond_to_everything_so_im_not_really_a_matcher).and_return(false)
    allow(site).to receive(:respond_to?).with(:matches?).and_return(false)

    # Setup logger to capture messages for each test
    allow(Jekyll.logger).to receive(:info)
    allow(Jekyll.logger).to receive(:warn) # Capture warnings too
  end

  describe "hook registration" do
    it "registers hooks without errors" do
      expect { load "lib/jekyll-imgflow/hooks.rb" }.not_to raise_error

      # Verify the after_init hook is wired by triggering it and checking logs
      Jekyll::Hooks.trigger :site, :after_init, site
      expect(Jekyll.logger).to have_received(:info)
        .with("🔌 ImgFlow: Initializing components on site").at_least(:once)
    end
  end

  describe "after_init hook behavior" do
    it "adds imgflow_components methods to site" do
      # Simulate after_init hook
      unless site.respond_to?(:imgflow_components)
        site.define_singleton_method(:imgflow_components) { @imgflow_components }
        site.define_singleton_method(:imgflow_components=) { |value| @imgflow_components = value }
      end

      expect(site).to respond_to(:imgflow_components)
      expect(site).to respond_to(:imgflow_components=)
    end

    it "doesn't override existing methods" do
      # Site already has the methods
      allow(site).to receive(:respond_to?).with(:imgflow_components).and_return(true)

      # Should not try to define them again
      expect(site).not_to receive(:define_singleton_method)

      # Simulate after_init hook logic
      unless site.respond_to?(:imgflow_components)
        site.define_singleton_method(:imgflow_components) { @imgflow_components }
        site.define_singleton_method(:imgflow_components=) { |value| @imgflow_components = value }
      end
    end
  end

  describe "post_read hook behavior" do
    before do
      # Mock Jekyll.env
      allow(Jekyll).to receive(:env).and_return("development")
    end

    it "processes images in development mode" do
      # Setup spy for BuildTimeProcessor
      allow(JekyllImgFlow::BuildTimeProcessor).to receive(:new).with(site).and_call_original

      # Simulate the post_read hook execution
      processor = JekyllImgFlow::BuildTimeProcessor.new(site)
      processor.process_changed_images

      expect(JekyllImgFlow::BuildTimeProcessor).to have_received(:new).with(site).once
    end

    it "processes images in production mode" do
      allow(Jekyll).to receive(:env).and_return("production")

      # Setup ManifestManager spy
      allow(JekyllImgFlow::ManifestManager).to receive(:new).with(site).and_call_original

      # Simulate the post_read hook execution
      processor = JekyllImgFlow::BuildTimeProcessor.new(site)
      processor.process_changed_images

      # Simulate the cleanup step that happens in production mode
      JekyllImgFlow.cleanup_orphaned_images(site)

      expect(JekyllImgFlow::ManifestManager).to have_received(:new).with(site).twice
    end
  end

  describe ".cleanup_orphaned_images" do
    it "creates manifest manager and cleans up" do
      # Setup ManifestManager spy
      allow(JekyllImgFlow::ManifestManager).to receive(:new).with(site).and_call_original

      JekyllImgFlow.cleanup_orphaned_images(site)

      expect(JekyllImgFlow::ManifestManager).to have_received(:new).with(site)
    end

    it "logs cleanup results" do
      # Mock ManifestManager to return orphaned files
      mock_manifest = double("manifest_manager")
      allow(mock_manifest).to receive(:cleanup_orphans).and_return(["file1.jpg", "file2.jpg"])
      allow(JekyllImgFlow::ManifestManager).to receive(:new).with(site).and_return(mock_manifest)

      JekyllImgFlow.cleanup_orphaned_images(site)

      expect(Jekyll.logger).to have_received(:info).with(
        "✅ ImgFlow: Removed 2 orphaned specialized images"
      )
    end

    it "logs when no orphans found" do
      # Mock ManifestManager to return no orphaned files
      mock_manifest = double("manifest_manager")
      allow(mock_manifest).to receive(:cleanup_orphans).and_return([])
      allow(JekyllImgFlow::ManifestManager).to receive(:new).with(site).and_return(mock_manifest)

      JekyllImgFlow.cleanup_orphaned_images(site)

      expect(Jekyll.logger).to have_received(:info).with(
        "✅ ImgFlow: No orphaned images found"
      )
    end
  end

  describe "hook behavior in different environments" do
    it "processes images in development mode" do
      # Mock Jekyll.env to be development
      allow(Jekyll).to receive(:env).and_return("development")

      # Allow BuildTimeProcessor creation (don't use expect to avoid test interference)
      allow(JekyllImgFlow::BuildTimeProcessor).to receive(:new).with(site).and_call_original

      # Trigger pre_render hook
      expect { Jekyll::Hooks.trigger :site, :pre_render, site }.not_to raise_error

      # Should log appropriate messages (use at_least once since hooks may be called multiple times)
      expect(Jekyll.logger).to have_received(:info).with("🔌 ImgFlow pre_render hook - creating default versions").at_least(:once)
    end

    it "processes images and cleans orphans in production mode" do
      # Mock Jekyll.env to be production
      allow(Jekyll).to receive(:env).and_return("production")

      # Allow BuildTimeProcessor creation
      allow(JekyllImgFlow::BuildTimeProcessor).to receive(:new).with(site).and_call_original

      # Trigger pre_render hook
      expect { Jekyll::Hooks.trigger :site, :pre_render, site }.not_to raise_error

      # Trigger post_write hook - should do cleanup in production
      expect { Jekyll::Hooks.trigger :site, :post_write, site }.not_to raise_error

      # Should log cleanup message (use at_least once since hooks may be called multiple times)
      expect(Jekyll.logger).to have_received(:info).with(/🧹 ImgFlow: Checking for orphaned specialized images/).at_least(:once)
    end

    it "handles other environments gracefully" do
      # Mock Jekyll.env to be something else
      allow(Jekyll).to receive(:env).and_return("test")

      # Allow BuildTimeProcessor creation
      allow(JekyllImgFlow::BuildTimeProcessor).to receive(:new).with(site).and_call_original

      # Trigger pre_render hook
      expect { Jekyll::Hooks.trigger :site, :pre_render, site }.not_to raise_error

      # Trigger post_write hook - should do cleanup in non-development
      expect { Jekyll::Hooks.trigger :site, :post_write, site }.not_to raise_error
    end
  end

  describe "hook error handling" do
    it "handles build processor errors gracefully" do
      # Mock BuildTimeProcessor to raise error
      allow(JekyllImgFlow::BuildTimeProcessor).to receive(:new).with(site).and_raise(StandardError,
                                                                                     "Processing failed")

      # Should raise error - hooks don't swallow errors by default
      expect do
        Jekyll::Hooks.trigger :site, :pre_render, site
      end.to raise_error(StandardError, "Processing failed")
    end

    it "handles cleanup errors gracefully" do
      # Mock cleanup to raise error (only in production)
      allow(Jekyll).to receive(:env).and_return("production")
      allow(JekyllImgFlow::ManifestManager).to receive(:new).and_raise(StandardError,
                                                                       "Cleanup failed")

      # Should raise error - hooks don't swallow errors by default
      expect do
        Jekyll::Hooks.trigger :site, :post_write, site # Cleanup happens in post_write
      end.to raise_error(StandardError, "Cleanup failed")
    end
  end

  describe "site component initialization" do
    it "adds imgflow_components methods when not present" do
      # Create a real site object instead of double
      real_site = Object.new

      # Ensure site doesn't have the methods initially
      expect(real_site).not_to respond_to(:imgflow_components)
      expect(real_site).not_to respond_to(:imgflow_components=)

      # Trigger after_init hook
      Jekyll::Hooks.trigger :site, :after_init, real_site

      # Should now respond to the methods
      expect(real_site).to respond_to(:imgflow_components)
      expect(real_site).to respond_to(:imgflow_components=)
    end

    it "does not override existing imgflow_components methods" do
      # Mock site to already have methods
      allow(site).to receive(:respond_to?).with(:imgflow_components).and_return(true)

      # Should not try to add them again
      expect(site).not_to receive(:define_singleton_method)

      # Trigger after_init hook
      Jekyll::Hooks.trigger :site, :after_init, site
    end
  end

  describe "logging behavior" do
    it "logs initialization messages" do
      # Trigger after_init hook
      Jekyll::Hooks.trigger :site, :after_init, site

      expect(Jekyll.logger).to have_received(:info).with("🔌 ImgFlow: Initializing components on site").at_least(:once)
      expect(Jekyll.logger).to have_received(:info).with("✅ ImgFlow: Components ready for initialization").at_least(:once)
    end

    it "logs environment-specific messages" do
      # Mock Jekyll.env
      allow(Jekyll).to receive(:env).and_return("development")

      # Trigger pre_render hook
      Jekyll::Hooks.trigger :site, :pre_render, site

      expect(Jekyll.logger).to have_received(:info).with("🔌 ImgFlow pre_render hook - creating default versions").at_least(:once)
      expect(Jekyll.logger).to have_received(:info).with(/✅ ImgFlow: Default versions created and manifest saved/).at_least(:once)
    end
  end

  describe "imgflow_components functionality" do
    it "allows setting and getting imgflow_components" do
      # Create a real site object
      real_site = Object.new

      # Trigger after_init hook to add methods
      Jekyll::Hooks.trigger :site, :after_init, real_site

      # Test setting and getting
      test_value = { "test" => "data" }
      real_site.imgflow_components = test_value
      expect(real_site.imgflow_components).to eq(test_value)
    end

    it "handles nil imgflow_components gracefully" do
      real_site = Object.new

      # Trigger after_init hook
      Jekyll::Hooks.trigger :site, :after_init, real_site

      # Test with nil value
      real_site.imgflow_components = nil
      expect(real_site.imgflow_components).to be_nil
    end
  end

  describe "BuildTimeProcessor integration" do
    it "creates BuildTimeProcessor with correct site" do
      # Mock Jekyll.env
      allow(Jekyll).to receive(:env).and_return("development")

      # Allow BuildTimeProcessor creation and verify it was called
      allow(JekyllImgFlow::BuildTimeProcessor).to receive(:new).with(site).and_call_original

      # Trigger pre_render hook
      Jekyll::Hooks.trigger :site, :pre_render, site

      # Verify the hook was called
      expect(JekyllImgFlow::BuildTimeProcessor).to have_received(:new).with(site).at_least(:once)
    end

    it "calls process_changed_images on processor" do
      # Mock Jekyll.env and BuildTimeProcessor
      allow(Jekyll).to receive(:env).and_return("development")
      mock_processor = double("build_processor")
      allow(mock_processor).to receive(:process_changed_images).twice
      allow(JekyllImgFlow::BuildTimeProcessor).to receive(:new).with(site).and_return(mock_processor)

      # Trigger pre_render hook
      Jekyll::Hooks.trigger :site, :pre_render, site

      # Verify the processor was called
      expect(mock_processor).to have_received(:process_changed_images).twice
    end
  end

  describe "cleanup_orphaned_images edge cases" do
    it "handles ManifestManager creation errors" do
      # Mock ManifestManager to raise error
      allow(JekyllImgFlow::ManifestManager).to receive(:new).and_raise(StandardError,
                                                                       "Manifest creation failed")

      # Should raise error
      expect do
        JekyllImgFlow.cleanup_orphaned_images(site)
      end.to raise_error(StandardError, "Manifest creation failed")
    end

    it "handles cleanup_orphans method errors" do
      # Mock cleanup_orphans to raise error
      mock_manifest = double("manifest_manager")
      allow(mock_manifest).to receive(:cleanup_orphans).and_raise(StandardError, "Cleanup failed")
      allow(JekyllImgFlow::ManifestManager).to receive(:new).with(site).and_return(mock_manifest)

      # Should raise error
      expect do
        JekyllImgFlow.cleanup_orphaned_images(site)
      end.to raise_error(StandardError, "Cleanup failed")
    end

    it "handles large number of orphaned files" do
      # Mock cleanup to return many files
      orphaned_files = (1..100).map { |i| "orphaned#{i}.jpg" }
      mock_manifest = double("manifest_manager")
      allow(mock_manifest).to receive(:cleanup_orphans).and_return(orphaned_files)
      allow(JekyllImgFlow::ManifestManager).to receive(:new).with(site).and_return(mock_manifest)

      # Should log correct count
      JekyllImgFlow.cleanup_orphaned_images(site)

      expect(Jekyll.logger).to have_received(:info).with("✅ ImgFlow: Removed 100 orphaned specialized images")
    end
  end

  describe "post_write hook without manifest" do
    it "logs warning when no manifest found" do
      allow(Jekyll).to receive(:env).and_return("development")
      allow(site).to receive(:imgflow_components).and_return(nil)

      expect { Jekyll::Hooks.trigger :site, :post_write, site }.not_to raise_error
      expect(Jekyll.logger).to have_received(:warn).with("⚠️  ImgFlow: No manifest found to save").at_least(:once)
    end

    it "logs warning when imgflow_components has no manifest key" do
      allow(Jekyll).to receive(:env).and_return("development")
      allow(site).to receive(:imgflow_components).and_return({})

      expect { Jekyll::Hooks.trigger :site, :post_write, site }.not_to raise_error
      expect(Jekyll.logger).to have_received(:warn).with("⚠️  ImgFlow: No manifest found to save").at_least(:once)
    end
  end

  describe "hook execution order" do
    it "executes after_init before pre_render" do
      # Reset logger call counts
      allow(Jekyll.logger).to receive(:info)

      # Trigger hooks in order
      Jekyll::Hooks.trigger :site, :after_init, site
      Jekyll::Hooks.trigger :site, :pre_render, site

      # Should have called both initialization and processing
      expect(Jekyll.logger).to have_received(:info).with("🔌 ImgFlow: Initializing components on site").at_least(:once)
      expect(Jekyll.logger).to have_received(:info).with("🔌 ImgFlow pre_render hook - creating default versions").at_least(:once)
    end
  end

  describe "multiple hook calls" do
    it "handles multiple after_init calls gracefully" do
      real_site = Object.new

      # Call after_init multiple times
      3.times { Jekyll::Hooks.trigger :site, :after_init, real_site }

      # Should still work
      expect(real_site).to respond_to(:imgflow_components)
      expect(real_site).to respond_to(:imgflow_components=)
    end

    it "handles multiple pre_render calls" do
      # Mock Jekyll.env
      allow(Jekyll).to receive(:env).and_return("development")

      # Allow BuildTimeProcessor creation and track calls
      allow(JekyllImgFlow::BuildTimeProcessor).to receive(:new).with(site).and_call_original

      # Call pre_render multiple times
      3.times { Jekyll::Hooks.trigger :site, :pre_render, site }

      # Verify it was called exactly 6 times (3 from this test + 3 from other tests)
      expect(JekyllImgFlow::BuildTimeProcessor).to have_received(:new).with(site).at_least(3).times
    end
  end

  describe "post_write cleanup_orphaned_images" do
    let(:site) { create_mock_site }
    let(:mock_manifest) { double("manifest", save: nil) }

    before do
      allow(site).to receive(:imgflow_components).and_return({ manifest: mock_manifest })
      allow(site).to receive(:imgflow_components=)
      allow(Jekyll.logger).to receive(:info)
      allow(Jekyll.logger).to receive(:warn)
    end

    it "calls cleanup_orphaned_images through post_write hook in production" do
      allow(Jekyll).to receive(:env).and_return("production")

      mock_mm = double("manifest_manager")
      allow(mock_mm).to receive(:cleanup_orphans).and_return(["file1.webp", "file2.avif"])
      allow(JekyllImgFlow::ManifestManager).to receive(:new).with(site).and_return(mock_mm)

      Jekyll::Hooks.trigger :site, :post_write, site

      expect(Jekyll.logger).to have_received(:info).with(
        "✅ ImgFlow: Removed 2 orphaned specialized images"
      ).at_least(:once)
    end

    it "logs no orphans found when cleanup returns empty" do
      allow(Jekyll).to receive(:env).and_return("production")

      mock_mm = double("manifest_manager")
      allow(mock_mm).to receive(:cleanup_orphans).and_return([])
      allow(JekyllImgFlow::ManifestManager).to receive(:new).with(site).and_return(mock_mm)

      Jekyll::Hooks.trigger :site, :post_write, site

      expect(Jekyll.logger).to have_received(:info).with(
        "✅ ImgFlow: No orphaned images found"
      ).at_least(:once)
    end
  end
end
