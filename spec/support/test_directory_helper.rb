# frozen_string_literal: true

require "securerandom"

# Centralized test directory management
module TestDirectoryHelper
  # Base test directory in project root
  PROJECT_ROOT = File.expand_path("../..", __dir__)
  TEST_BASE_DIR = File.join(PROJECT_ROOT, "tmp", "tests")

  def self.setup_test_directories
    # Create base test directory if it doesn't exist
    FileUtils.mkdir_p(TEST_BASE_DIR)
  end

  def self.create_test_dir(name = nil)
    setup_test_directories

    # Create a timestamped test directory. Millisecond precision plus a random
    # suffix guarantee uniqueness even when many tests run within the same
    # second, preventing tests from unintentionally sharing (and deleting)
    # each other's directories.
    timestamp = Time.now.strftime("%Y%m%d-%H%M%S%L")
    unique = SecureRandom.hex(4)
    test_name = name || "test-#{timestamp}"
    test_dir = File.join(TEST_BASE_DIR, "#{test_name}-#{timestamp}-#{unique}")

    FileUtils.mkdir_p(test_dir)
    test_dir
  end

  def self.cleanup_test_directories
    return unless Dir.exist?(TEST_BASE_DIR)

    # Clean up test directories older than 1 hour
    Dir.glob(File.join(TEST_BASE_DIR, "*")).each do |dir|
      FileUtils.rm_rf(dir) if File.directory?(dir) && (Time.now - File.mtime(dir)) > 3600
    end
  end

  def self.cleanup_all_test_directories
    return unless Dir.exist?(TEST_BASE_DIR)

    FileUtils.rm_rf(TEST_BASE_DIR)
  end
end

# Auto-cleanup old test directories before running tests
TestDirectoryHelper.cleanup_test_directories
