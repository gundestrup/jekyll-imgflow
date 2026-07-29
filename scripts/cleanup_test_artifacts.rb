#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual cleanup script for ImgFlow test artifacts
# Run this to clean up orphaned test files and servers

require "fileutils"
require "tmpdir"

puts "🧹 ImgFlow Test Artifacts Cleanup"
puts "=" * 50

# Configuration
SINGLE_TEST_PORT = 4000
PARALLEL_PORT_BASE = 4010
MAX_PARALLEL_PROCESSES = 8

# 1. Kill orphaned Jekyll servers
puts "\n1️⃣  Checking for orphaned Jekyll servers..."
ports_to_check = [SINGLE_TEST_PORT] + (PARALLEL_PORT_BASE..(PARALLEL_PORT_BASE + MAX_PARALLEL_PROCESSES - 1)).to_a

killed_count = 0
ports_to_check.each do |port|
  output = `lsof -ti:#{port} 2>/dev/null`.strip
  next if output.empty?

  puts "  🔍 Found process on port #{port}, killing..."
  system("lsof -ti:#{port} | xargs kill -9 2>/dev/null")
  killed_count += 1
end

if killed_count.positive?
  puts "  ✅ Killed #{killed_count} orphaned server(s)"
else
  puts "  ✅ No orphaned servers found"
end

# 2. Clean up pre-built test sites (local tmp/ folder)
puts "\n2️⃣  Cleaning up pre-built test sites..."
project_root = File.expand_path("..", __dir__)
local_tmp_dir = File.join(project_root, "tmp")

if File.exist?(local_tmp_dir)
  size = `du -sh "#{local_tmp_dir}" 2>/dev/null`.split.first
  FileUtils.rm_rf(local_tmp_dir)
  puts "  ✅ Removed tmp/ directory (#{size})"
else
  puts "  ✅ No tmp/ directory found"
end

# 3. Clean up temporary test directories
puts "\n3️⃣  Cleaning up temporary test directories..."
temp_dir = Dir.tmpdir
patterns = [
  "imgflow-picture-test*",
  "imgflow-enhanced-benchmark*",
  "imgflow-performance-test*",
  "d[0-9]*-*-*"
]

removed_count = 0
total_size = 0

patterns.each do |pattern|
  Dir.glob(File.join(temp_dir, pattern)).each do |dir|
    next unless File.directory?(dir)

    # Get size before removing
    size_output = `du -sk "#{dir}" 2>/dev/null`.split.first.to_i
    total_size += size_output

    begin
      FileUtils.rm_rf(dir)
      removed_count += 1
      puts "  🗑️  Removed: #{File.basename(dir)}"
    rescue StandardError => e
      puts "  ⚠️  Could not remove #{File.basename(dir)}: #{e.message}"
    end
  end
end

if removed_count.positive?
  size_mb = (total_size / 1024.0).round(1)
  puts "  ✅ Removed #{removed_count} test directory(ies) (#{size_mb} MB)"
else
  puts "  ✅ No temporary test directories found"
end

# 4. Summary
puts "\n#{'=' * 50}"
puts "✅ Cleanup complete!"
puts "   - Servers killed: #{killed_count}"
puts "   - Temp dirs removed: #{removed_count}"
puts "   - Space freed: ~#{(total_size / 1024.0).round(1)} MB"
puts "=" * 50
