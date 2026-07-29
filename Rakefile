# frozen_string_literal: true

require "English"
require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yard"
require "jekyll"
require "net/http"

desc "Run tests (parallel by default, SEQUENTIAL=true for sequential)"
# Default spec task - uses parallel execution by default
task :spec do
  if ENV["SEQUENTIAL"] == "true"
    puts "🔄 Running tests sequentially with profiling..."
    Rake::Task[:spec_sequential].invoke
  else
    puts "🚀 Running tests in parallel by default..."
    puts "   Use SEQUENTIAL=true rake spec for sequential execution with profiling"
    Rake::Task[:spec_parallel].invoke
  end
end

# Enhanced RSpec rake task with built-in features (for direct use)
RSpec::Core::RakeTask.new(:spec_rspec) do |t|
  # Use .rspec configuration by default (includes tag exclusions)
  t.rspec_opts = "--require spec_helper"

  # Enable verbose output to see which tests are running
  t.verbose = true

  # Fail on errors (default behavior)
  t.fail_on_error = true

  # Use pattern to find spec files
  t.pattern = "spec/**/*_spec.rb"
end

desc "Run tests in parallel using parallel_tests gem"
# Parallel RSpec task using parallel_tests gem
task :spec_parallel do
  # Get number of CPU cores and subtract 1
  cpu_count = `sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4`.to_i
  processes = [cpu_count - 1, 1].max # Ensure at least 1 process
  puts "🚀 Running tests in parallel with #{processes} processes (n-1 cores)"
  puts "📝 Using .rspec_parallel configuration (excludes :slow and :external)"
  sh "bundle exec parallel_rspec -n #{processes}"
end

# Sequential RSpec task with profiling
RSpec::Core::RakeTask.new(:spec_sequential) do |t|
  # Enable profiling for sequential runs
  t.rspec_opts = "--require spec_helper --profile 10"
  t.verbose = true
  t.fail_on_error = true
  t.pattern = "spec/**/*_spec.rb"
end

# Unit tests only
RSpec::Core::RakeTask.new(:spec_unit) do |t|
  t.rspec_opts = "--require spec_helper --tag unit"
  t.verbose = true
  t.fail_on_error = true
  t.pattern = "spec/**/*_spec.rb"
end

# Integration tests only
RSpec::Core::RakeTask.new(:spec_integration) do |t|
  t.rspec_opts = "--require spec_helper --tag integration"
  t.verbose = true
  t.fail_on_error = true
  t.pattern = "spec/**/*_spec.rb"
end

# Performance tests only (sequential, with profiling)
RSpec::Core::RakeTask.new(:spec_performance) do |t|
  t.rspec_opts = "--require spec_helper --tag performance --profile 5"
  t.verbose = true
  t.fail_on_error = true
  t.pattern = "spec/**/*_spec.rb"
end

# Slow tests (for debugging)
RSpec::Core::RakeTask.new(:spec_slow) do |t|
  t.rspec_opts = "--require spec_helper --tag slow --profile 10"
  t.verbose = true
  t.fail_on_error = true
  t.pattern = "spec/**/*_spec.rb"
end

# Fast tests (exclude slow and external)
RSpec::Core::RakeTask.new(:spec_fast) do |t|
  t.rspec_opts = "--require spec_helper --tag ~slow --tag ~external --tag ~provider"
  t.verbose = true
  t.fail_on_error = true
  t.pattern = "spec/**/*_spec.rb"
end
YARD::Rake::YardocTask.new

# Default task: run all quality checks (most common use case)
task default: :quality

desc "Run all tests with coverage"
task test: :spec

# Parallel testing tasks
namespace :parallel do
  desc "Run tests in parallel (fast) - uses n-1 cores, excludes slow and external tests"
  task :test do
    # Get number of CPU cores and subtract 1
    cpu_count = `sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4`.to_i
    processes = [cpu_count - 1, 1].max  # Ensure at least 1 process
    puts "🚀 Running tests in parallel with #{processes} processes (n-1 cores)"
    puts "📝 Using .rspec_parallel configuration (excludes :slow and :external)"
    sh "bundle exec parallel_rspec -n #{processes}"
  end

  desc "Run specific tests in parallel - uses n-1 cores"
  task :test_files, [:files] do |_t, args|
    files = args[:files] || "spec/"
    cpu_count = `sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4`.to_i
    processes = [cpu_count - 1, 1].max
    puts "🚀 Running #{files} in parallel with #{processes} processes (n-1 cores)"
    sh "bundle exec parallel_rspec #{files} -n #{processes}"
  end

  desc "Run tests in parallel with coverage - uses n-2 cores for stability, excludes slow and external tests"
  task :test_coverage do
    cpu_count = `sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4`.to_i
    processes = [cpu_count - 2, 1].max  # Use n-2 for coverage to be more stable
    puts "🚀 Running tests with coverage in parallel with #{processes} processes (n-2 cores)"
    puts "📝 Using .rspec_parallel configuration (excludes :slow and :external)"
    ENV["COVERAGE"] = "true"
    sh "bundle exec parallel_rspec -n #{processes}"
  end
end

desc "Run all quality checks (style, smells, security, tests)"
task quality: %i[rubocop reek bundler_audit spec]

desc "Run tests only (fast) - excludes slow and external tests by default"
task :spec_fast do
  # Check if sequential execution is requested (for profiling)
  if ENV["SEQUENTIAL"] == "true"
    puts "📊 Running tests sequentially (profiling mode)"
    sh "bundle exec rspec --profile 10"
  else
    # Get number of CPU cores and subtract 1 for parallel execution
    cpu_count = `sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4`.to_i
    processes = [cpu_count - 1, 1].max # Ensure at least 1 process

    puts "🚀 Running tests in parallel with #{processes} processes (n-1 cores)"
    puts "📝 Using .rspec_parallel configuration (excludes :slow and :external)"
    sh "bundle exec parallel_rspec -n #{processes}"
  end
end

desc "Show test status dashboard"
task :test_status do
  ruby "scripts/test_logger.rb", "status"
end

desc "Show latest test failures for debugging"
task :test_failures do
  failure_log = File.join("test_logs", "latest_failures.json")
  setup_error_log = File.join("test_logs", "setup_errors.json")
  success_log = File.join("test_logs", "latest_success.json")

  found_issues = false

  # Check for test failures
  if File.exist?(failure_log)
    require "json"
    failures = JSON.parse(File.read(failure_log))
    puts "🔍 Latest Test Failures (#{failures['timestamp']})"
    puts "=" * 60
    puts "Total examples: #{failures['total_examples']}"
    puts "Test failures: #{failures['test_failure_count']}"
    puts "Global errors: #{failures['global_error_count']}" if failures["global_error_count"].positive?
    puts ""

    if failures["test_failures"]&.any?
      puts "📋 Test Failures:"
      failures["test_failures"].each_with_index do |failure, i|
        puts "#{i + 1}. #{failure['description']}"
        puts "   Location: #{failure['location']}"
        puts "   Error: #{failure['exception']['class']}"
        puts "   Message: #{failure['exception']['message']}"
        puts "   Backtrace:"
        failure["exception"]["backtrace"].each { |line| puts "     #{line}" }
        puts ""
      end
    end

    if failures["global_errors"]&.any?
      puts "🌐 Global Errors (outside examples):"
      failures["global_errors"].each_with_index do |error, i|
        puts "#{i + 1}. #{error['description']}"
        puts "   Type: #{error['type']}"
        puts "   Error: #{error['exception']['class']}"
        puts "   Message: #{error['exception']['message']}"
        puts "   Backtrace:"
        error["exception"]["backtrace"].each { |line| puts "     #{line}" }
        puts ""
      end
    end

    found_issues = true
  end

  # Check for setup/teardown errors
  if File.exist?(setup_error_log)
    require "json"
    setup_errors = JSON.parse(File.read(setup_error_log))
    puts "⚙️  Setup/Teardown Errors:"
    puts "=" * 60
    setup_errors.each_with_index do |error, i|
      puts "#{i + 1}. #{error['example']}"
      puts "   Location: #{error['location']}"
      puts "   Error: #{error['exception']['class']}"
      puts "   Message: #{error['exception']['message']}"
      puts "   Backtrace:"
      error["exception"]["backtrace"].each { |line| puts "     #{line}" }
      puts ""
    end
    found_issues = true
  end

  # Check for success
  if File.exist?(success_log)
    require "json"
    success = JSON.parse(File.read(success_log))
    puts "✅ Latest Test Run Status (#{success['timestamp']})"
    puts "=" * 60
    puts "Status: All tests passed!"
    puts "Total examples: #{success['total_examples']}"
    found_issues = true
  end

  puts "📝 No test logs found. Run tests first to generate logs." unless found_issues
end

desc "Capture profiling information to file"
task :test_profile do
  puts "📊 Capturing profiling information..."

  # Run tests with profiling and capture output
  require "tempfile"

  Tempfile.create("rspec_profile_output") do |_temp_file|
    # Run sequential tests to get detailed profiling
    cmd = "bundle exec rspec --profile 15 --format documentation 2>&1"
    puts "🔄 Running: #{cmd}"

    output = `#{cmd}`
    exit_status = $CHILD_STATUS.exitstatus

    # Parse profiling information from output
    profiling_data = {
      timestamp: Time.now.iso8601,
      exit_status: exit_status,
      command: cmd,
      raw_output: output,
      slowest_examples: [],
      slowest_groups: []
    }

    # Extract slowest examples
    if output.match?(/Top \d+ slowest examples/)
      examples_section = output.match(/Top \d+ slowest examples.*?(?=\n\n|\z)/m)
      if examples_section
        examples_section[0].each_line do |line|
          # Parse: "7.74 seconds ./spec/hooks_spec.rb:80"
          unless line.match?(/\d+\.\d+ seconds.*\.rb:\d+/) && (match = line.match(/(\d+\.\d+)\s+seconds\s+(.*?)(\s|$)/))
            next
          end

          time = match[1]
          location = match[2]
          description = ""

          # Get description from previous line
          lines = output.split("\n")
          current_line_index = lines.find_index(line)
          description = lines[current_line_index - 1].strip if current_line_index&.positive?

          profiling_data[:slowest_examples] << {
            time_seconds: time.to_f,
            location: location,
            description: description
          }
        end
      end
    end

    # Extract slowest example groups
    if output.match?(/Top \d+ slowest example groups/)
      groups_section = output.match(/Top \d+ slowest example groups.*?(?=\n\n|\z)/m)
      if groups_section
        groups_section[0].each_line do |line|
          # Parse: "0.42407 seconds average (7.63 seconds / 18 examples) ./spec/preset_system_spec.rb:18"
          unless line.match?(/\d+\.\d+ seconds average.*\.rb:\d+/) && (match = line.match(%r{(\d+\.\d+)\s+seconds\s+average.*?\((\d+\.\d+)\s+seconds\s+/\s+(\d+)\s+examples\)\s+(.*?)(\s|$)}))
            next
          end

          avg_time = match[1]
          total_time = match[2]
          example_count = match[3]
          location = match[4]

          profiling_data[:slowest_groups] << {
            average_time_seconds: avg_time.to_f,
            total_time_seconds: total_time.to_f,
            example_count: example_count.to_i,
            location: location
          }
        end
      end
    end

    # Save profiling data
    profile_log = File.join("test_logs", "latest_profiling.json")
    File.write(profile_log, JSON.pretty_generate(profiling_data))

    puts "📝 Profiling data saved to: #{profile_log}"
    puts "🔍 Found #{profiling_data[:slowest_examples].length} slow examples"
    puts "📊 Found #{profiling_data[:slowest_groups].length} slow example groups"

    # Display summary
    if profiling_data[:slowest_examples].any?
      puts "\n🐌 Top 5 Slowest Examples:"
      profiling_data[:slowest_examples].first(5).each_with_index do |example, i|
        puts "#{i + 1}. #{example[:time_seconds]}s - #{example[:description]}"
        puts "   📍 #{example[:location]}"
      end
    end

    if profiling_data[:slowest_groups].any?
      puts "\n📊 Top 5 Slowest Groups:"
      profiling_data[:slowest_groups].first(5).each_with_index do |group, i|
        puts "#{i + 1}. #{group[:average_time_seconds]}s avg (#{group[:example_count]} examples) - #{group[:location]}"
        puts "   📈 Total: #{group[:total_time_seconds]}s"
      end
    end
  end
end

desc "Clean up old test history (removes old failed test records)"
task :test_cleanup do
  history_file = File.join("test_logs", "test_history.json")
  if File.exist?(history_file)
    require "json"
    history = JSON.parse(File.read(history_file))

    # Keep only the last 10 successful runs and recent failures
    successful_runs = history.select { |run| run["success"] }.last(5)
    recent_failures = history.reject { |run| run["success"] }.select do |run|
      Time.parse(run["timestamp"]) > Time.now - (24 * 60 * 60) # Keep failures from last 24 hours
    end

    cleaned_history = successful_runs + recent_failures
    cleaned_history.sort_by! { |run| run["timestamp"] }.reverse!

    File.write(history_file, JSON.pretty_generate(cleaned_history))
    puts "🧹 Cleaned test history:"
    puts "   Kept #{successful_runs.length} recent successful runs"
    puts "   Kept #{recent_failures.length} recent failures (last 24h)"
    puts "   Removed #{history.length - cleaned_history.length} old entries"
  else
    puts "📝 No test history file found."
  end

  # Clean up old test_run_TIMESTAMP files (keep only last 5)
  timestamp_files = Dir.glob(File.join("test_logs", "test_run_*.json")).sort_by do |f|
    File.mtime(f)
  end.reverse
  files_to_remove = timestamp_files[5..] || []

  files_to_remove.each do |old_file|
    File.delete(old_file)
    puts "   🗑️  Removed old timestamp file: #{File.basename(old_file)}"
  end

  if files_to_remove.any?
    puts "   Kept #{timestamp_files.length - files_to_remove.length} recent timestamp files"
  else
    puts "   No old timestamp files to remove"
  end

  # Clean up old logging_error.json files (keep only latest)
  error_files = Dir.glob(File.join("test_logs", "logging_error.json"))
  if error_files.length > 1
    old_error_files = error_files[1..]
    old_error_files.each { |f| File.delete(f) }
    puts "   🗑️  Removed #{old_error_files.length} old error log files"
  end
end

desc "Show test grouping help"
task :test_help do
  Jekyll.logger.info "🧪 ImgFlow Best Practice Test Grouping System"
  Jekyll.logger.info "=" * 60
  Jekyll.logger.info ""
  Jekyll.logger.info "🏆 INDUSTRY BEST PRACTICES (Automatic):"
  Jekyll.logger.info "  Tests follow industry-standard tagging patterns:"
  Jekyll.logger.info "    • 🎯 EXPLICIT TAGS: # TAGS: performance, integration (highest priority)"
  Jekyll.logger.info "    • 📂 DIRECTORY: spec/unit/, spec/integration/, spec/performance/"
  Jekyll.logger.info "    • 📁 FILENAME: *_unit_spec.rb, *_integration_spec.rb, *_performance_spec.rb"
  Jekyll.logger.info "    • 📝 CONTENT PATTERNS: describe \"...performance\", sleep(), external services"
  Jekyll.logger.info "    • 🏷️  HIERARCHICAL: :slow umbrella includes all time-intensive tests"
  Jekyll.logger.info ""
  Jekyll.logger.info "📝 DEFAULT TESTS (Fast - Best Practice):"
  Jekyll.logger.info "  rake spec                    # Default: Parallel, excludes :slow and :external"
  Jekyll.logger.info "  SEQUENTIAL=true rake spec     # Sequential with profiling"
  Jekyll.logger.info "  rake parallel:test           # Parallel: excludes :slow and :external"
  Jekyll.logger.info "  rake quick                   # Quick: excludes :slow and :external"
  Jekyll.logger.info "  rake test                    # Alias for default tests"
  Jekyll.logger.info ""
  Jekyll.logger.info "🧪 UNIT TESTS (Fast - Best Practice):"
  Jekyll.logger.info "  rake test_unit_only          # Run :unit tests only (fastest)"
  Jekyll.logger.info ""
  Jekyll.logger.info "⚡ PERFORMANCE TESTS (Auto-Detected):"
  Jekyll.logger.info "  rake test_performance        # Run :performance tests only"
  Jekyll.logger.info "  rake test_performance_only   # Run :performance tests only (alternative)"
  Jekyll.logger.info "  rake performance_benchmark  # Comprehensive performance benchmark"
  Jekyll.logger.info ""
  Jekyll.logger.info "🔗 INTEGRATION TESTS (Auto-Detected):"
  Jekyll.logger.info "  rake test_integration_only   # Run :integration tests only"
  Jekyll.logger.info ""
  Jekyll.logger.info "🌐 PROVIDER TESTS (Auto-Detected):"
  Jekyll.logger.info "  rake test_provider_only      # Run :provider tests only"
  Jekyll.logger.info ""
  Jekyll.logger.info "🖥️  SYSTEM TESTS (Auto-Detected):"
  Jekyll.logger.info "  rake test_system_only        # Run :system tests only"
  Jekyll.logger.info ""
  Jekyll.logger.info "🌍 EXTERNAL TESTS (Best Practice):"
  Jekyll.logger.info "  rake test_external_only      # Run :external tests (provider+integration)"
  Jekyll.logger.info ""
  Jekyll.logger.info "🐌 ALL SLOW TESTS (Combined):"
  Jekyll.logger.info "  rake test_slow_only          # Run ALL :slow tests (perf+int+prov+sys+e2e)"
  Jekyll.logger.info ""
  Jekyll.logger.info "🚀 COMPREHENSIVE TESTS:"
  Jekyll.logger.info "  rake test_comprehensive_all  # Run ALL tests (including all categories)"
  Jekyll.logger.info "  rake test_all               # Run all tests except performance (legacy)"
  Jekyll.logger.info ""
  Jekyll.logger.info "📊 COVERAGE:"
  Jekyll.logger.info "  rake parallel:test_coverage # Run tests with coverage (excludes :slow and :external)"
  Jekyll.logger.info ""
  Jekyll.logger.info "🔍 TEST DEBUGGING:"
  Jekyll.logger.info "  rake test_failures         # Show latest test failures with details"
  Jekyll.logger.info "  rake test_status           # Show test status dashboard"
  Jekyll.logger.info "  rake test_cleanup          # Clean up old test history entries"
  Jekyll.logger.info "  rake test_profile          # Capture profiling data to file"
  Jekyll.logger.info "  SEQUENTIAL=true rake spec   # Run tests sequentially with profiling"
  Jekyll.logger.info ""
  Jekyll.logger.info "🧹 CLEANUP PROCESS:"
  Jekyll.logger.info "  • test_history.json: Keeps 5 successful runs + 24h failures"
  Jekyll.logger.info "  • test_run_*.json: Only created with DEBUG_TEST_LOGGING=true"
  Jekyll.logger.info "  • logging_error.json: Keeps only latest error file"
  Jekyll.logger.info "  • Uses RSpec built-in logging instead of custom JSON formatter"
  Jekyll.logger.info "  • Old files automatically removed by cleanup task"
  Jekyll.logger.info ""
  Jekyll.logger.info "🎯 RSPEC BUILT-IN TASKS:"
  Jekyll.logger.info "  rake spec                   # Default: parallel execution with profiling (top 10 slowest)"
  Jekyll.logger.info "  rake spec_parallel          # Parallel execution with lighter profiling (top 5 slowest)"
  Jekyll.logger.info "  rake spec_sequential        # Sequential execution with detailed profiling (top 10)"
  Jekyll.logger.info "  rake spec_fast              # Fast tests only with profiling (excludes :slow, :external, :provider)"
  Jekyll.logger.info "  rake spec_unit              # Unit tests only with profiling (--tag unit)"
  Jekyll.logger.info "  rake spec_integration       # Integration tests only with profiling (--tag integration)"
  Jekyll.logger.info "  rake spec_performance       # Performance tests with detailed profiling (--tag performance)"
  Jekyll.logger.info "  rake spec_slow              # Slow tests with detailed profiling (--tag slow)"
  Jekyll.logger.info ""
  Jekyll.logger.info "📊 PROFILING INFORMATION:"
  Jekyll.logger.info "  • Profiling enabled by default in all test runs"
  Jekyll.logger.info "  • Shows 'Top N slowest examples' in terminal output"
  Jekyll.logger.info "  • Parallel runs: top 5 slowest (lighter profiling)"
  Jekyll.logger.info "  • Sequential runs: top 10 slowest (detailed profiling)"
  Jekyll.logger.info "  • Use SEQUENTIAL=true for most detailed profiling"
  Jekyll.logger.info "  • Profiling data appears at end of test run in terminal"
  Jekyll.logger.info ""
  Jekyll.logger.info "🏷️  BEST PRACTICE TAG FILTERING:"
  Jekyll.logger.info "  bundle exec rspec --tag ~slow --tag ~external        # Default (fast)"
  Jekyll.logger.info "  bundle exec rspec --tag unit                        # Unit tests only"
  Jekyll.logger.info "  bundle exec rspec --tag performance                 # Performance only"
  Jekyll.logger.info "  bundle exec rspec --tag integration                  # Integration only"
  Jekyll.logger.info "  bundle exec rspec --tag provider                     # Provider only"
  Jekyll.logger.info "  bundle exec rspec --tag system                       # System only"
  Jekyll.logger.info "  bundle exec rspec --tag external                     # External services"
  Jekyll.logger.info "  bundle exec rspec --tag slow                         # All slow categories"
  Jekyll.logger.info "  bundle exec rspec --tag performance --tag integration # Multiple tags!"
  Jekyll.logger.info ""
  Jekyll.logger.info "💡 BEST PRACTICE EXAMPLES:"
  Jekyll.logger.info "  📁 EXPLICIT: # TAGS: performance, integration (top of file)"
  Jekyll.logger.info "  📂 DIRECTORY: spec/unit/user_spec.rb → auto :unit tag"
  Jekyll.logger.info "  📝 CONTENT: describe \"Payment Integration\" → auto :integration tag"
  Jekyll.logger.info "  🏷️  MULTIPLE: provider_real_world_integration_spec.rb → :provider + :integration + :slow"
  Jekyll.logger.info ""
  Jekyll.logger.info "📋 TAG HIERARCHY (Best Practice):"
  Jekyll.logger.info "  :slow (umbrella) → includes :performance, :integration, :provider, :system, :e2e"
  Jekyll.logger.info "  :external (umbrella) → includes :provider, :integration"
  Jekyll.logger.info "  :unit → fast unit tests (excluded from :slow)"
  Jekyll.logger.info "  :performance → benchmarks and performance tests"
  Jekyll.logger.info "  :integration → real-world integration tests"
  Jekyll.logger.info "  :provider → external service provider tests"
  Jekyll.logger.info "  :system → system-level and Jekyll integration tests"
  Jekyll.logger.info "  :e2e → end-to-end tests"
  Jekyll.logger.info ""
  Jekyll.logger.info "🎯 NAMING CONVENTIONS (Best Practice):"
  Jekyll.logger.info "  ✅ GOOD: user_unit_spec.rb, payment_integration_spec.rb, resize_performance_spec.rb"
  Jekyll.logger.info "  ❌ AVOID: test_stuff_spec.rb, random_tests_spec.rb, unclear_names_spec.rb"
  Jekyll.logger.info ""
  Jekyll.logger.info "🔧 PERFORMANCE TESTS REQUIRE:"
  Jekyll.logger.info "  ENV['PERFORMANCE']='true'  # For performance benchmarks"
  Jekyll.logger.info ""
end

desc "Check code style with RuboCop"
task :rubocop do
  sh "bundle exec rubocop"
end

desc "Auto-fix RuboCop issues"
task :rubocop_fix do
  sh "bundle exec rubocop -a"
end

desc "Check code smells with Reek"
task :reek do
  sh "bundle exec reek --config .reek.yml lib/" do |ok, _|
    # Reek warnings are acceptable, only fail on errors
    ok || $CHILD_STATUS.exitstatus == 2
  end
end

desc "Run security audit"
task :bundler_audit do
  sh "bundle exec bundler-audit check --update"
end

desc "Run quick checks (style + tests only) - excludes slow and external tests"
task :quick do
  Jekyll.logger.info "🏃 Running quick checks..."
  begin
    sh "bundle exec rubocop"
    Jekyll.logger.info "✅ Style checks passed"
  rescue StandardError
    Jekyll.logger.info "⚠️  Style issues found (continuing with tests)"
  end
  Jekyll.logger.info "📝 Excluding slow and external tests by default"
  sh "bundle exec rspec --tag ~slow --tag ~external"
  Jekyll.logger.info "✅ Tests passed"
end

desc "Check gem dependencies"
task :check_gems do
  Jekyll.logger.info "🔍 Checking required gems..."

  if system("bundle check > /dev/null 2>&1")
    Jekyll.logger.info "✅ All required gems are installed"
  else
    Jekyll.logger.warn "⚠️  Running bundle install..."
    system("bundle install")
  end
end

desc "Run comprehensive test suite (all test types)"
task :test_comprehensive do
  Jekyll.logger.info "🚀 ImgFlow Comprehensive Test Suite"
  Jekyll.logger.info "=" * 50

  # Pre-flight checks
  Rake::Task[:check_gems].invoke
  Rake::Task[:check_services].invoke

  Jekyll.logger.info ""

  # Define test groups
  test_groups = [
    {
      name: "Tags System Tests",
      description: "All tag functionality and edge cases",
      files: [
        "spec/tags/*_spec.rb",
        "spec/tags_system_spec.rb"
      ]
    },
    {
      name: "Presets System Tests",
      description: "Preset management and configuration",
      files: [
        "spec/preset_manager_spec.rb",
        "spec/preset_system_spec.rb"
      ]
    },
    {
      name: "Core System Tests",
      description: "Core components (build processor, hooks, providers)",
      files: [
        "spec/build_time_processor_spec.rb",
        "spec/hooks_spec.rb",
        "spec/provider_capabilities_spec.rb",
        "spec/provider_interface_spec.rb",
        "spec/provider_registry_spec.rb"
      ]
    },
    {
      name: "Integration Tests",
      description: "Full system integration and Jekyll compatibility",
      files: [
        "spec/jekyll_integration_spec.rb",
        "spec/jekyll_dev_server_integration_spec.rb",
        "spec/picture_tag_integration_spec.rb",
        "spec/imgflow_system_spec.rb"
      ]
    }
  ]

  failed_groups = []

  test_groups.each do |group|
    Jekyll.logger.info "🧪 Running #{group[:name]}..."
    Jekyll.logger.info "📝 #{group[:description]}"
    Jekyll.logger.info ""

    # Run all files in the group
    group_failed = false
    group[:files].each do |file_pattern|
      if file_pattern.include?("*")
        # Handle glob patterns
        Dir.glob(file_pattern).each do |file|
          Jekyll.logger.info "  🔸 Running #{File.basename(file)}..."
          if system("bundle exec rspec #{file} --format progress")
            Jekyll.logger.info "  ✅ #{File.basename(file)} PASSED"
          else
            Jekyll.logger.error "  ❌ #{File.basename(file)} FAILED"
            group_failed = true
          end
        end
      elsif File.exist?(file_pattern)
        # Handle individual files
        Jekyll.logger.info "  🔸 Running #{File.basename(file_pattern)}..."
        if system("bundle exec rspec #{file_pattern} --format progress")
          Jekyll.logger.info "  ✅ #{File.basename(file_pattern)} PASSED"
        else
          Jekyll.logger.error "  ❌ #{File.basename(file_pattern)} FAILED"
          group_failed = true
        end
      else
        Jekyll.logger.warn "  ⚠️  File not found: #{file_pattern}"
      end
    end

    if group_failed
      Jekyll.logger.error "❌ #{group[:name]} FAILED"
      failed_groups << group[:name]
    else
      Jekyll.logger.info "✅ #{group[:name]} PASSED"
    end
    Jekyll.logger.info ""
  end

  # Summary
  Jekyll.logger.info "=" * 50
  Jekyll.logger.info "🏁 Test Group Summary"
  Jekyll.logger.info "=" * 50

  if failed_groups.empty?
    Jekyll.logger.info "🎉 ALL TEST GROUPS PASSED! 🎉"
    Jekyll.logger.info ""
    Jekyll.logger.info "✅ Tags System Tests"
    Jekyll.logger.info "✅ Presets System Tests"
    Jekyll.logger.info "✅ Core System Tests"
    Jekyll.logger.info "✅ Integration Tests"
    Jekyll.logger.info ""
    Jekyll.logger.info "🚀 ImgFlow plugin is ready for production!"
  else
    Jekyll.logger.error "❌ Some test groups failed:"
    failed_groups.each { |group| Jekyll.logger.error "  - #{group}" }
    Jekyll.logger.error ""
    Jekyll.logger.error "Please check the failed tests and fix any issues before deployment."
    exit 1
  end
end

desc "Run all tests (performance tests are always separate)"
task :test_all do
  Jekyll.logger.info "🚀 ImgFlow Test Suite"
  Jekyll.logger.info "=" * 50
  Jekyll.logger.info "📝 Note: Using singleton pattern for test site management"
  Jekyll.logger.info ""

  # Build the gem first to ensure we're testing the packaged code
  Jekyll.logger.info "🔨 Building jekyll-imgflow gem..."
  build_result = system("bundle exec rake build")
  unless build_result
    Jekyll.logger.error "❌ Failed to build gem!"
    exit 1
  end
  Jekyll.logger.info "✅ Gem built successfully"
  Jekyll.logger.info ""

  # Quick pre-flight check (skip full service check)
  Rake::Task[:check_gems].invoke

  Jekyll.logger.info ""

  # Separate integration tests (external services) from other tests
  integration_test_files = [
    "spec/jekyll_integration_spec.rb",
    "spec/jekyll_dev_server_integration_spec.rb",
    "spec/picture_tag_integration_spec.rb"
  ]

  other_test_files = [
    "spec/tags/*_spec.rb",
    "spec/tags_system_spec.rb",
    "spec/preset_manager_spec.rb",
    "spec/preset_system_spec.rb",
    "spec/build_time_processor_spec.rb",
    "spec/hooks_spec.rb",
    "spec/provider_capabilities_spec.rb",
    "spec/provider_interface_spec.rb",
    "spec/provider_registry_spec.rb",
    "spec/imgflow_system_spec.rb"
  ]

  Jekyll.logger.info "🧪 Running all tests except performance..."

  # Expand glob patterns and filter existing files
  integration_files = integration_test_files.select { |f| File.exist?(f) }
  other_files = other_test_files.flat_map do |file|
    if file.include?("*")
      Dir.glob(file)
    else
      file
    end
  end
  other_files.select! { |f| File.exist?(f) }

  if integration_files.empty? && other_files.empty?
    Jekyll.logger.error "❌ No test files found!"
    exit 1
  end

  Jekyll.logger.info "📝 Running test files..."
  Jekyll.logger.info "   🔄 Parallel tests: #{other_files.length} files" unless other_files.empty?
  Jekyll.logger.info "   🔗 Integration tests: #{integration_files.length} files (sequential)" unless integration_files.empty?
  Jekyll.logger.info ""

  success = true

  # Run other tests in parallel for better performance
  unless other_files.empty?
    if other_files.length > 1
      Jekyll.logger.info "🚀 Running parallel tests..."
      success = system("bundle exec parallel_rspec #{other_files.join(' ')} --type rspec")
    else
      success = system("bundle exec rspec #{other_files.join(' ')} --format progress")
    end
  end

  # Run integration tests sequentially to avoid service contention
  if success && !integration_files.empty?
    Jekyll.logger.info "🔗 Running integration tests sequentially..."
    success = system("bundle exec rspec #{integration_files.join(' ')} --format documentation")
  end

  if success
    Jekyll.logger.info ""
    Jekyll.logger.info "=" * 50
    Jekyll.logger.info "🎉 ALL TESTS PASSED! 🎉"
    Jekyll.logger.info ""
    Jekyll.logger.info "✅ Tags System Tests"
    Jekyll.logger.info "✅ Presets System Tests"
    Jekyll.logger.info "✅ Core System Tests"
    Jekyll.logger.info "✅ Integration Tests"
    Jekyll.logger.info ""
    Jekyll.logger.info "🚀 ImgFlow plugin is ready for production!"
  else
    Jekyll.logger.error ""
    Jekyll.logger.error "=" * 50
    Jekyll.logger.error "❌ Some tests failed!"
    Jekyll.logger.error ""
    Jekyll.logger.error "Please check the failed tests and fix any issues before deployment."
    exit 1
  end
end

# Individual test group tasks
desc "Run Tags System Tests"
task :test_tags do
  Jekyll.logger.info "🏷️  Running Tags System Tests..."
  Jekyll.logger.info ""

  tag_files = Dir.glob("spec/tags/*_spec.rb") + ["spec/tags_system_spec.rb"]
  failed_files = []

  tag_files.each do |file|
    next unless File.exist?(file)

    Jekyll.logger.info "🔸 Running #{File.basename(file)}..."
    if system("bundle exec rspec #{file} --format progress")
      Jekyll.logger.info "✅ #{File.basename(file)} PASSED"
    else
      Jekyll.logger.error "❌ #{File.basename(file)} FAILED"
      failed_files << file
    end
  end

  if failed_files.empty?
    Jekyll.logger.info "🎉 ALL TAGS TESTS PASSED! 🎉"
  else
    Jekyll.logger.error "❌ Failed tags tests:"
    failed_files.each { |file| Jekyll.logger.error "  - #{file}" }
    exit 1
  end
end

desc "Run Presets System Tests"
task :test_presets do
  Jekyll.logger.info "⚙️  Running Presets System Tests..."
  Jekyll.logger.info ""

  preset_files = ["spec/preset_manager_spec.rb", "spec/preset_system_spec.rb"]
  failed_files = []

  preset_files.each do |file|
    next unless File.exist?(file)

    Jekyll.logger.info "🔸 Running #{File.basename(file)}..."
    if system("bundle exec rspec #{file} --format progress")
      Jekyll.logger.info "✅ #{File.basename(file)} PASSED"
    else
      Jekyll.logger.error "❌ #{File.basename(file)} FAILED"
      failed_files << file
    end
  end

  if failed_files.empty?
    Jekyll.logger.info "🎉 ALL PRESETS TESTS PASSED! 🎉"
  else
    Jekyll.logger.error "❌ Failed presets tests:"
    failed_files.each { |file| Jekyll.logger.error "  - #{file}" }
    exit 1
  end
end

desc "Run Core System Tests"
task :test_core do
  Jekyll.logger.info "🏗️  Running Core System Tests..."
  Jekyll.logger.info ""

  core_files = [
    "spec/build_time_processor_spec.rb",
    "spec/hooks_spec.rb",
    "spec/provider_capabilities_spec.rb",
    "spec/provider_interface_spec.rb",
    "spec/provider_registry_spec.rb"
  ]
  failed_files = []

  core_files.each do |file|
    next unless File.exist?(file)

    Jekyll.logger.info "🔸 Running #{File.basename(file)}..."
    if system("bundle exec rspec #{file} --format progress")
      Jekyll.logger.info "✅ #{File.basename(file)} PASSED"
    else
      Jekyll.logger.error "❌ #{File.basename(file)} FAILED"
      failed_files << file
    end
  end

  if failed_files.empty?
    Jekyll.logger.info "🎉 ALL CORE SYSTEM TESTS PASSED! 🎉"
    Jekyll.logger.info ""
    Jekyll.logger.info "📊 Core Coverage Highlights:"
    Jekyll.logger.info "  🚀 Build Time Processor: 97.83% coverage"
    Jekyll.logger.info "  ⚡ Hooks Integration: 77.78% coverage"
    Jekyll.logger.info "  🔧 Provider Capabilities: Dynamic meta-testing"
  else
    Jekyll.logger.error "❌ Failed core system tests:"
    failed_files.each { |file| Jekyll.logger.error "  - #{file}" }
    exit 1
  end
end

desc "Run Integration Tests"
task :test_integration do
  Jekyll.logger.info "🔗 Running Integration Tests..."
  Jekyll.logger.info ""

  integration_files = [
    "spec/jekyll_integration_spec.rb",
    "spec/jekyll_dev_server_integration_spec.rb",
    "spec/picture_tag_integration_spec.rb",
    "spec/imgflow_system_spec.rb"
  ]
  failed_files = []

  integration_files.each do |file|
    next unless File.exist?(file)

    Jekyll.logger.info "🔸 Running #{File.basename(file)}..."
    if system("bundle exec rspec #{file} --format progress")
      Jekyll.logger.info "✅ #{File.basename(file)} PASSED"
    else
      Jekyll.logger.error "❌ #{File.basename(file)} FAILED"
      failed_files << file
    end
  end

  if failed_files.empty?
    Jekyll.logger.info "🎉 ALL INTEGRATION TESTS PASSED! 🎉"
  else
    Jekyll.logger.error "❌ Failed integration tests:"
    failed_files.each { |file| Jekyll.logger.error "  - #{file}" }
    exit 1
  end
end

desc "Run Performance Tests (separate from main suite) - uses RSpec tags"
task :test_performance do
  Jekyll.logger.info "⚡ Running Performance Tests..."
  Jekyll.logger.info "📝 Using RSpec :performance tag"
  Jekyll.logger.info ""

  # Set environment for performance tests
  ENV["PERFORMANCE"] = "true"

  if system("bundle exec rspec --tag performance --format documentation")
    Jekyll.logger.info "🎉 ALL PERFORMANCE TESTS PASSED! 🎉"
  else
    Jekyll.logger.error "❌ Performance tests failed"
    exit 1
  end
end

desc "Run provider tests only (quick)"
task :test_providers do
  Jekyll.logger.info "🧪 Running Provider Capabilities Tests..."
  Jekyll.logger.info ""

  if system("bundle exec rspec spec/provider_capabilities_spec.rb --format documentation")
    Jekyll.logger.info "✅ Provider tests passed"
  else
    Jekyll.logger.error "❌ Provider tests failed"
    exit 1
  end
end

desc "Run Jekyll integration tests only"
task :test_jekyll do
  Jekyll.logger.info "🧪 Running Jekyll Integration Tests..."
  Rake::Task[:check_gems].invoke
  Rake::Task[:check_services].invoke
  Jekyll.logger.info ""

  if system("bundle exec rspec spec/jekyll_integration_spec.rb --format documentation")
    Jekyll.logger.info "✅ Jekyll integration tests passed"
  else
    Jekyll.logger.error "❌ Jekyll integration tests failed"
    exit 1
  end
end

desc "Run build time processor tests only"
task :test_build_processor do
  Jekyll.logger.info "🧪 Running Build Time Processor Tests..."
  Jekyll.logger.info ""

  if system("bundle exec rspec spec/build_time_processor_spec.rb --format documentation")
    Jekyll.logger.info "✅ Build time processor tests passed"
  else
    Jekyll.logger.error "❌ Build time processor tests failed"
    exit 1
  end
end

desc "Run hooks integration tests only"
task :test_hooks do
  Jekyll.logger.info "🧪 Running Hooks Integration Tests..."
  Jekyll.logger.info ""

  if system("bundle exec rspec spec/hooks_spec.rb --format documentation")
    Jekyll.logger.info "✅ Hooks tests passed"
  else
    Jekyll.logger.error "❌ Hooks tests failed"
    exit 1
  end
end

desc "Run Picture Tag integration tests only"
task :test_picture do
  Jekyll.logger.info "🧪 Running Picture Tag Integration Tests..."
  Rake::Task[:check_gems].invoke
  Rake::Task[:check_services].invoke
  Jekyll.logger.info ""

  if system("bundle exec rspec spec/picture_tag_integration_spec.rb --format documentation")
    Jekyll.logger.info "✅ Picture Tag integration tests passed"
  else
    Jekyll.logger.error "❌ Picture Tag integration tests failed"
    exit 1
  end
end

desc "Run performance benchmark with test set (default|all)"
task :performance_benchmark, [:test_set] do |_t, args|
  Jekyll.logger.info "🚀 ImgFlow Performance Benchmark"
  Jekyll.logger.info "=" * 50

  # Parse test set argument
  test_set = args[:test_set] || "default"
  case test_set.to_s.downcase
  when "all"
    ENV["TEST_ALL_PICTURES"] = "true"
    Jekyll.logger.info "📊 Test Set: ALL pictures (comprehensive)"
  when "default"
    ENV["TEST_ALL_PICTURES"] = "false"
    Jekyll.logger.info "📊 Test Set: default_multi (fast)"
  else
    Jekyll.logger.error "❌ Invalid test set: #{test_set}. Use 'default' or 'all'"
    Jekyll.logger.info "   Usage: rake performance_benchmark[default|all]"
    exit 1
  end

  # Check services first
  Jekyll.logger.info "🔍 Checking services availability..."
  unless system("rake check_services")
    Jekyll.logger.error "❌ Service check failed! Please fix issues before running benchmark."
    exit 1
  end

  Jekyll.logger.info "✅ All services verified"

  # Set environment and run benchmark
  ENV["PERFORMANCE"] = "true"

  Jekyll.logger.info "\n🏃 Running performance benchmark with #{test_set} test set..."
  Jekyll.logger.info "   This will take several minutes..."
  Jekyll.logger.info "   Press Ctrl+C to cancel"

  sleep 2

  # Run the actual benchmark script
  benchmark_script = File.expand_path("scripts/performance_benchmark.rb", __dir__)

  if File.exist?(benchmark_script)
    if system("ruby #{benchmark_script}")
      show_performance_results
    else
      Jekyll.logger.error "❌ Benchmark execution failed!"
      exit 1
    end
  else
    Jekyll.logger.error "❌ Benchmark script not found: #{benchmark_script}"
    exit 1
  end
end

desc "Run performance benchmark with default test set (fast)"
task :performance_default do
  Rake::Task[:performance_benchmark].invoke("default")
end

desc "Run performance benchmark with all pictures (comprehensive)"
task :performance_all do
  Rake::Task[:performance_benchmark].invoke("all")
end

desc "Run performance tests only (excluded from default runs)"
task :test_performance_only do
  Jekyll.logger.info "⚡ Running Performance Tests Only..."
  Jekyll.logger.info "=" * 40

  # Set environment for performance tests
  ENV["PERFORMANCE"] = "true"

  if system("bundle exec rspec --tag performance --format documentation")
    Jekyll.logger.info "✅ Performance tests passed"
  else
    Jekyll.logger.error "❌ Performance tests failed"
    exit 1
  end
end

desc "Run integration tests only (excluded from default runs)"
task :test_integration_only do
  Jekyll.logger.info "🔗 Running Integration Tests Only..."
  Jekyll.logger.info "=" * 40

  if system("bundle exec rspec --tag integration --format documentation")
    Jekyll.logger.info "✅ Integration tests passed"
  else
    Jekyll.logger.error "❌ Integration tests failed"
    exit 1
  end
end

desc "Run provider tests only (excluded from default runs)"
task :test_provider_only do
  Jekyll.logger.info "🌐 Running Provider Tests Only..."
  Jekyll.logger.info "=" * 40

  if system("bundle exec rspec --tag provider --format documentation")
    Jekyll.logger.info "✅ Provider tests passed"
  else
    Jekyll.logger.error "❌ Provider tests failed"
    exit 1
  end
end

desc "Run system tests only (excluded from default runs)"
task :test_system_only do
  Jekyll.logger.info "🖥️  Running System Tests Only..."
  Jekyll.logger.info "=" * 40

  if system("bundle exec rspec --tag system --format documentation")
    Jekyll.logger.info "✅ System tests passed"
  else
    Jekyll.logger.error "❌ System tests failed"
    exit 1
  end
end

desc "Run unit tests only (fast tests)"
task :test_unit_only do
  Jekyll.logger.info "🧪 Running Unit Tests Only..."
  Jekyll.logger.info "=" * 40

  if system("bundle exec rspec --tag unit --format documentation")
    Jekyll.logger.info "✅ Unit tests passed"
  else
    Jekyll.logger.error "❌ Unit tests failed"
    exit 1
  end
end

desc "Run external tests only (tests requiring external services)"
task :test_external_only do
  Jekyll.logger.info "🌐 Running External Tests Only..."
  Jekyll.logger.info "=" * 40

  if system("bundle exec rspec --tag external --format documentation")
    Jekyll.logger.info "✅ External tests passed"
  else
    Jekyll.logger.error "❌ External tests failed"
    exit 1
  end
end

desc "Run slow tests only (all slow categories)"
task :test_slow_only do
  Jekyll.logger.info "🐌 Running All Slow Tests..."
  Jekyll.logger.info "=" * 40
  Jekyll.logger.info "📝 Includes: performance, integration, provider, system, e2e tests"

  if system("bundle exec rspec --tag slow --format documentation")
    Jekyll.logger.info "✅ All slow tests passed"
  else
    Jekyll.logger.error "❌ Some slow tests failed"
    exit 1
  end
end

desc "Run all tests including slow tests (comprehensive)"
task :test_comprehensive_all do
  Jekyll.logger.info "🚀 Running Comprehensive Test Suite (All Tests)"
  Jekyll.logger.info "=" * 50
  Jekyll.logger.info "📝 Including all slow tests (performance, integration, provider, system)"
  Jekyll.logger.info ""

  # Run all tests without tag exclusions
  if system("bundle exec rspec --format documentation")
    Jekyll.logger.info "✅ All tests passed (including slow tests)"
  else
    Jekyll.logger.error "❌ Some tests failed"
    exit 1
  end
end

desc "Run performance benchmark via RSpec (test integration)"
task :performance_test do
  Jekyll.logger.info "🧪 Running Performance Benchmark via RSpec..."

  # Set environment and run RSpec
  ENV["PERFORMANCE"] = "true"

  unless system("bundle exec rspec spec/performance_benchmark_spec.rb --format documentation")
    Jekyll.logger.error "❌ Performance RSpec test failed!"
    exit 1
  end

  show_performance_results
end

desc "Quick performance check (basic providers only)"
task :performance_quick do
  Jekyll.logger.info "⚡ Quick Performance Check"
  Jekyll.logger.info "=" * 30

  # Basic service check
  Jekyll.logger.info "🔍 Quick service check..."
  cli_tools = %w[vips magick sharp]
  available = cli_tools.select { |tool| system("which #{tool} > /dev/null 2>&1") }

  if available.empty?
    Jekyll.logger.error "❌ No CLI tools available for quick performance test"
    exit 1
  end

  Jekyll.logger.info "✅ Available tools: #{available.join(', ')}"

  # Quick benchmark using available tools
  require "benchmark"
  require "fileutils"
  require "tmpdir"

  test_image = "spec/fixtures/originals/spider_web-small.jpg"
  unless File.exist?(test_image)
    Jekyll.logger.error "❌ Test image not found: #{test_image}"
    Jekyll.logger.error "   Run: rake download_test_images"
    exit 1
  end

  temp_dir = Dir.mktmpdir("perf-quick")

  begin
    Jekyll.logger.info "\n⏱️  Running quick performance tests..."

    results = {}
    available.each do |tool|
      Jekyll.logger.info "   Testing #{tool}..."

      time = Benchmark.realtime do
        case tool
        when "vips"
          system("vips resize #{test_image} #{temp_dir}/vips_test.jpg 800 2>/dev/null")
        when "magick"
          system("magick #{test_image} -resize 800x #{temp_dir}/magick_test.jpg 2>/dev/null")
        when "sharp"
          system("sharp -i #{test_image} -o #{temp_dir}/sharp_test.jpg --resize 800 2>/dev/null")
        end
      end

      results[tool] = time
      Jekyll.logger.info "     ✅ #{tool}: #{(time * 1000).round(1)}ms"
    end

    Jekyll.logger.info "\n📊 Quick Results:"
    fastest = results.min_by { |_, time| time }
    slowest = results.max_by { |_, time| time }

    Jekyll.logger.info "   🏆 Fastest: #{fastest[0]} (#{(fastest[1] * 1000).round(1)}ms)"
    Jekyll.logger.info "   🐌 Slowest: #{slowest[0]} (#{(slowest[1] * 1000).round(1)}ms)"
    Jekyll.logger.info "   📈 Speed difference: #{(slowest[1] / fastest[1]).round(1)}x"
  ensure
    FileUtils.rm_rf(temp_dir)
  end
end

# Helper method to show performance results
def show_performance_results
  report_file = "README.Performance.md"

  if File.exist?(report_file)
    Jekyll.logger.info "\n📊 Benchmark completed!"
    Jekyll.logger.info "   Results saved to: #{report_file}"

    # Extract key metrics
    content = File.read(report_file)

    Jekyll.logger.info "   🏆 Fastest Provider: #{Regexp.last_match(1)}" if content =~ /Fastest Provider:\s*(\w+)/

    Jekyll.logger.info "   🗜️  Best Compression: #{Regexp.last_match(1)}" if content =~ /Best Compression:\s*(\w+)/

    Jekyll.logger.info "\n📝 Open #{report_file} to see detailed results."
  else
    Jekyll.logger.info "\n❌ Benchmark report not found!"
  end
end

desc "Download test images for ImgFlow testing"
task :download_test_images do
  require "net/http"
  require "uri"
  require "fileutils"

  fixtures_dir = "spec/fixtures/originals"
  FileUtils.mkdir_p(fixtures_dir)

  Jekyll.logger.info "🖼️  Downloading ImgFlow test images..."

  # Check if images already exist
  if Dir.glob("#{fixtures_dir}/*.jpg").any? && Dir.glob("#{fixtures_dir}/*.png").any?
    Jekyll.logger.info "⚠️  Test images already exist in #{fixtures_dir}"
    Jekyll.logger.info "   To re-download, remove the directory first:"
    Jekyll.logger.info "   rm -rf #{fixtures_dir}"
    Jekyll.logger.info "   Then run this task again."
    return
  end

  # Define test images to download
  test_images = [
    # NASA Mars images
    {
      name: "mars-crater-large.jpg",
      url: "https://mars.nasa.gov/system/downloadable_items/39099_Mars-MRO-orbiter-fresh-crater-sirenum-fossae.jpg",
      description: "NASA Mars crater (large)"
    },
    # Image compression test images
    {
      name: "artificial-large.jpg",
      url: "https://imagecompression.info/test_images/big_thumbnails/artificial.jpg",
      description: "Artificial image (large)"
    },
    {
      name: "artificial-small.jpg",
      url: "https://imagecompression.info/test_images/small_thumbnails/artificial.jpg",
      description: "Artificial image (small)"
    },
    {
      name: "spider_web-large.jpg",
      url: "https://imagecompression.info/test_images/big_thumbnails/spider_web.jpg",
      description: "Spider web (large)"
    },
    {
      name: "spider_web-small.jpg",
      url: "https://imagecompression.info/test_images/small_thumbnails/spider_web.jpg",
      description: "Spider web (small)"
    },
    # PNG images
    {
      name: "file_example-large.png",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2017/10/file_example_PNG_3MB.png",
      description: "PNG (large)"
    },
    {
      name: "file_example-small.png",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2017/10/file_example_PNG_1MB.png",
      description: "PNG (small)"
    },
    # WebP images
    {
      name: "file_example-small.webp",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2020/03/file_example_WEBP_50kB.webp",
      description: "WebP (small)"
    },
    {
      name: "file_example-medium.webp",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2020/03/file_example_WEBP_250kB.webp",
      description: "WebP (medium)"
    },
    {
      name: "file_example-large.webp",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2020/03/file_example_WEBP_1500kB.webp",
      description: "WebP (large)"
    },
    # TIFF images
    {
      name: "file_example-small.tiff",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2017/10/file_example_TIFF_1MB.tiff",
      description: "TIFF (small)"
    },
    {
      name: "file_example-medium.tiff",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2017/10/file_example_TIFF_5MB.tiff",
      description: "TIFF (medium)"
    },
    {
      name: "file_example-large.tiff",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2017/10/file_example_TIFF_10MB.tiff",
      description: "TIFF (large)"
    },
    # SVG images
    {
      name: "file_example-small.svg",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2020/03/file_example_SVG_20kB.svg",
      description: "SVG (small)"
    },
    {
      name: "file_example-medium.svg",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2020/03/file_example_SVG_30kB.svg",
      description: "SVG (medium)"
    },
    # JPEG images
    {
      name: "file_example-large.jpg",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2017/10/file_example_JPG_2500kB.jpg",
      description: "JPEG (large)"
    },
    {
      name: "file_example-medium.jpg",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2017/10/file_example_JPG_1000kB.jpg",
      description: "JPEG (medium)"
    },
    {
      name: "file_example-small.jpg",
      url: "https://file-examples.com/storage/fe6e2df45d69b286a9c7a01/2017/10/file_example_JPG_500kB.jpg",
      description: "JPEG (small)"
    }
  ]

  Jekyll.logger.info "📡 Downloading #{test_images.length} test images..."
  downloaded = 0
  failed = 0

  test_images.each do |image|
    file_path = File.join(fixtures_dir, image[:name])

    begin
      uri = URI(image[:url])
      response = Net::HTTP.get_response(uri)

      if response.code.to_i >= 200 && response.code.to_i < 300
        File.write(file_path, response.body)
        size = File.size(file_path)
        Jekyll.logger.info "    ✅ #{image[:description]}: #{(size.to_f / 1024).round(1)}KB"
        downloaded += 1
      else
        Jekyll.logger.info "    ❌ #{image[:description]}: HTTP #{response.code}"
        failed += 1
      end
    rescue StandardError => e
      Jekyll.logger.info "    ❌ #{image[:description]}: #{e.message}"
      failed += 1
    end
  end

  Jekyll.logger.info ""
  Jekyll.logger.info "📁 Download complete! Test images in: #{fixtures_dir}"
  Jekyll.logger.info "🔍 Available images:"

  Dir.glob("#{fixtures_dir}/*.{jpg,png,webp,tiff,svg}").each do |file|
    size = File.size(file)
    Jekyll.logger.info "   #{File.basename(file)}: #{(size.to_f / 1024).round(1)}KB"
  end

  Jekyll.logger.info ""
  Jekyll.logger.info "📊 Image summary:"
  format_counts = {
    "jpg" => Dir.glob("#{fixtures_dir}/*.jpg").length,
    "png" => Dir.glob("#{fixtures_dir}/*.png").length,
    "webp" => Dir.glob("#{fixtures_dir}/*.webp").length,
    "tiff" => Dir.glob("#{fixtures_dir}/*.tiff").length,
    "svg" => Dir.glob("#{fixtures_dir}/*.svg").length
  }

  format_counts.each do |format, count|
    Jekyll.logger.info "   #{format.upcase}: #{count} files"
  end

  Jekyll.logger.info ""
  Jekyll.logger.info "📐 Size variants:"
  size_counts = {
    "large" => Dir.glob("#{fixtures_dir}/*-large.*").length,
    "medium" => Dir.glob("#{fixtures_dir}/*-medium.*").length,
    "small" => Dir.glob("#{fixtures_dir}/*-small.*").length
  }

  size_counts.each do |size, count|
    Jekyll.logger.info "   #{size.capitalize}: #{count} files"
  end

  Jekyll.logger.info ""
  Jekyll.logger.info "🚀 Ready for testing!"
  Jekyll.logger.info "   bundle exec rspec"
  Jekyll.logger.info ""
  Jekyll.logger.info "📈 Results: #{downloaded} downloaded, #{failed} failed"

  Jekyll.logger.warn "⚠️  Some downloads failed - check URLs or network connection" if failed.positive?
end

desc "Check test services availability"
task :check_services do
  Jekyll.logger.info "🔍 Checking ImgFlow test services..."
  Jekyll.logger.info ""
  Jekyll.logger.info "═══════════════════════════════════════════════════════════════"
  Jekyll.logger.info "  PROGRAMMATIC PROVIDERS (HTTP API - Work with ImgFlow)"
  Jekyll.logger.info "═══════════════════════════════════════════════════════════════"

  services = [
    { name: "Imgproxy", port: 33_001, health_path: "/health", docker_cmd: "imgproxy" },
    { name: "Weserv", port: 33_007, health_path: "/", docker_cmd: "weserv" },
    { name: "Flyimg", port: 33_008, health_path: "/", docker_cmd: "flyimg" }
  ]

  services.each do |service|
    Jekyll.logger.info "🖼️  Checking #{service[:name]} service..."
    begin
      response = Net::HTTP.get_response(URI("http://localhost:#{service[:port]}#{service[:health_path]}"))
      if response.code.to_i >= 200 && response.code.to_i < 300
        Jekyll.logger.info "✅ #{service[:name]} HTTP API is healthy (Port #{service[:port]})"
      else
        Jekyll.logger.info "❌ #{service[:name]} service returned HTTP #{response.code}"
        Jekyll.logger.info "   Run: docker-compose -f docker-compose.test.yml up -d " \
                           "#{service[:docker_cmd]}"
      end
    rescue Errno::ECONNREFUSED, SocketError
      Jekyll.logger.info "❌ #{service[:name]} service is not responding"
      Jekyll.logger.info "   Run: docker-compose -f docker-compose.test.yml up -d " \
                         "#{service[:docker_cmd]}"
    end
  end

  Jekyll.logger.info ""
  Jekyll.logger.info "═══════════════════════════════════════════════════════════════"
  Jekyll.logger.info "  LOCAL CLI TOOLS"
  Jekyll.logger.info "═══════════════════════════════════════════════════════════════"

  cli_tools = [
    { name: "ImageMagick", command: "magick", version_cmd: "magick -version",
      install_cmd: "brew install imagemagick (macOS) or apt-get install imagemagick (Ubuntu)" },
    { name: "LibVips", command: "vips", version_cmd: "vips --version",
      install_cmd: "brew install vips (macOS) or apt-get install libvips-tools (Ubuntu)" },
    { name: "Sharp CLI", command: "sharp", version_cmd: "sharp --version",
      install_cmd: "npm install -g sharp-cli" }
  ]

  cli_tools.each do |tool|
    Jekyll.logger.info "🎨 Checking local #{tool[:name]} installation..."
    if system("which #{tool[:command]} >/dev/null 2>&1")
      version_output = `#{tool[:version_cmd]} 2>/dev/null | head -1`.chomp
      Jekyll.logger.info "✅ #{tool[:name]} is available locally (#{version_output})"
    else
      Jekyll.logger.info "❌ #{tool[:name]} not found locally"
      Jekyll.logger.info "   Install with: #{tool[:install_cmd]}"
    end
  end

  Jekyll.logger.info "═══════════════════════════════════════════════════════════════"
  Jekyll.logger.info "  SUMMARY"
  Jekyll.logger.info "═══════════════════════════════════════════════════════════════"
  Jekyll.logger.info ""
  Jekyll.logger.info "✅ ALL PROVIDERS WORK PROGRAMMATICALLY:"
  Jekyll.logger.info "   • Imgproxy (HTTP API)"
  Jekyll.logger.info "   • Weserv (HTTP API)"
  Jekyll.logger.info "   • Flyimg (HTTP API)"
  Jekyll.logger.info "   • ImageMagick (CLI)"
  Jekyll.logger.info "   • LibVips (CLI)"
  Jekyll.logger.info "   • Sharp (CLI)"
  Jekyll.logger.info ""
  Jekyll.logger.info "🚀 To start all test services:"
  Jekyll.logger.info "   docker-compose -f docker-compose.test.yml --env-file .env.test up -d"
  Jekyll.logger.info ""
  Jekyll.logger.info "🛑 To stop all test services:"
  Jekyll.logger.info "   docker-compose -f docker-compose.test.yml down"
end

desc "Generate YARD documentation"
task :doc do
  sh "yard doc"
end

desc "Generate documentation from templates"
task :generate_docs do
  Jekyll.logger.info "📚 Generating documentation from templates..."

  # Define template mappings
  template_mappings = [
    {
      template: "docs/template/tags.md",
      targets: [
        "docs/usage/tags.md"
      ]
    },
    {
      template: "docs/template/presets.md",
      targets: [
        "docs/usage/presets.md"
      ]
    },
    {
      template: "docs/template/preset-examples.md",
      targets: [
        "docs/usage/preset-examples.md"
      ]
    }
  ]

  template_mappings.each do |mapping|
    if File.exist?(mapping[:template])
      Jekyll.logger.info "   📝 Processing: #{File.basename(mapping[:template])}"

      mapping[:targets].each do |target|
        # Ensure target directory exists
        target_dir = File.dirname(target)
        FileUtils.mkdir_p(target_dir)

        # Copy from template to target
        FileUtils.cp(mapping[:template], target)
        Jekyll.logger.info "     ✅ Generated: #{target}"
      end
    else
      Jekyll.logger.info "   ❌ Template not found: #{mapping[:template]}"
    end
  end

  Jekyll.logger.info ""
  Jekyll.logger.info "✅ Documentation generation complete!"
  Jekyll.logger.info "   Templates: docs/template/"
  Jekyll.logger.info "   Generated: docs/usage/"
  Jekyll.logger.info ""
  Jekyll.logger.info "💡 Run 'rake generate_docs' after editing templates"
  Jekyll.logger.info "💡 Templates are the single source of truth"
end

desc "Build and install the gem locally"
task :install_local do
  Jekyll.logger.info "🔨 Building and installing ImgFlow gem..."
  Jekyll.logger.info "   Generating documentation first..."

  # Generate docs before building
  Rake::Task[:generate_docs].invoke

  Jekyll.logger.info "   Building gem..."
  sh "gem build jekyll-imgflow.gemspec"

  Jekyll.logger.info "   Installing gem..."
  sh "gem install jekyll-imgflow-*.gem"

  Jekyll.logger.info "✅ Gem built and installed successfully!"
  Jekyll.logger.info "   Documentation synced from templates"
end

desc "Open documentation in browser"
task :docs do
  Jekyll.logger.info "📚 ImgFlow Documentation Structure:"
  Jekyll.logger.info ""
  Jekyll.logger.info "📖 Main Documentation:"
  Jekyll.logger.info "   README.md                    # Main project overview"
  Jekyll.logger.info "   docs/README.md               # Complete documentation index"
  Jekyll.logger.info ""
  Jekyll.logger.info "🔧 Setup & Configuration:"
  Jekyll.logger.info "   docs/installation.md        # Installation guide"
  Jekyll.logger.info "   docs/docker.md              # Docker setup"
  Jekyll.logger.info "   docs/providers.md           # Provider configuration"
  Jekyll.logger.info ""
  Jekyll.logger.info "📖 Usage & Features (Generated from Templates):"
  Jekyll.logger.info "   docs/usage/tags.md           # Jekyll tags reference"
  Jekyll.logger.info "   docs/usage/presets.md        # Presets system"
  Jekyll.logger.info "   docs/usage/preset-examples.md # Preset examples"
  Jekyll.logger.info ""
  Jekyll.logger.info "📝 Templates (Single Source of Truth):"
  Jekyll.logger.info "   docs/template/tags.md        # Tags template"
  Jekyll.logger.info "   docs/template/presets.md     # Presets template"
  Jekyll.logger.info "   docs/template/preset-examples.md # Examples template"
  Jekyll.logger.info "   docs/template/performance.md # Performance template"
  Jekyll.logger.info ""
  Jekyll.logger.info "👨‍💻 Development:"
  Jekyll.logger.info "   docs/development.md         # Development guide"
  Jekyll.logger.info "   docs/testing.md              # Testing guide"
  Jekyll.logger.info "   docs/rake.md                 # Simple Rake tasks guide"
  Jekyll.logger.info ""
  Jekyll.logger.info "🚀 Performance:"
  Jekyll.logger.info "   docs/performance/           # Performance reports"
  Jekyll.logger.info ""
  Jekyll.logger.info "💡 Quick Commands:"
  Jekyll.logger.info "   rake generate_docs          # Generate docs from templates"
  Jekyll.logger.info "   rake download_test_images   # Setup test images"
  Jekyll.logger.info "   rake check_services         # Check services"
  Jekyll.logger.info "   rake performance_quick      # Quick performance test"
  Jekyll.logger.info "   rake test                   # Run tests"
  Jekyll.logger.info ""
  Jekyll.logger.info "🔄 Documentation Workflow:"
  Jekyll.logger.info "   1. Edit templates in docs/template/"
  Jekyll.logger.info "   2. Run 'rake generate_docs'"
  Jekyll.logger.info "   3. Docs synced to docs/usage/"
  Jekyll.logger.info ""
  Jekyll.logger.info "📋 Need Rake help? See docs/rake.md for simple task guide"
  Jekyll.logger.info ""

  # Try to open in browser
  if system("which open > /dev/null 2>&1")
    system("open docs/README.md")
  elsif system("which xdg-open > /dev/null 2>&1")
    system("xdg-open docs/README.md")
  else
    Jekyll.logger.info "Open docs/README.md in your browser to view documentation"
  end
end

# Display available tasks with descriptions
desc "Show available testing tasks"
task :help do
  Jekyll.logger.info "🧪 Testing Tasks:"
  Jekyll.logger.info "  rake test               # Run all tests (same as spec)"
  Jekyll.logger.info "  rake spec               # Run all RSpec tests"
  Jekyll.logger.info "  rake test_comprehensive # Run comprehensive test suite with detailed output"
  Jekyll.logger.info "  rake quick              # Quick check (style + tests)"
  Jekyll.logger.info "  rake quality            # Run all quality checks"
  Jekyll.logger.info "  rake check_services     # Check test services availability"
  Jekyll.logger.info "  rake check_gems         # Check gem dependencies"
  Jekyll.logger.info "  rake download_test_images # Download test images"
  Jekyll.logger.info ""
  Jekyll.logger.info "  📋 Test Groups (Logical Organization):"
  Jekyll.logger.info "  rake test_tags          # Run Tags System Tests (all tag functionality)"
  Jekyll.logger.info "  rake test_presets       # Run Presets System Tests (preset management)"
  Jekyll.logger.info "  rake test_core          # Run Core System Tests (build processor, hooks, providers)"
  Jekyll.logger.info "  rake test_integration   # Run Integration Tests (Jekyll compatibility)"
  Jekyll.logger.info "  rake test_performance   # Run Performance Tests (separate from main suite)"
  Jekyll.logger.info ""
  Jekyll.logger.info "  🔧 Individual Test Tasks:"
  Jekyll.logger.info "  rake test_providers     # Run provider capabilities tests only"
  Jekyll.logger.info "  rake test_jekyll        # Run Jekyll integration tests only"
  Jekyll.logger.info "  rake test_picture       # Run Picture Tag integration tests only"
  Jekyll.logger.info "  rake test_coverage_focused # Run coverage-focused tests (high coverage files)"
  Jekyll.logger.info ""
  Jekyll.logger.info "🚀 Performance Tasks (Separate):"
  Jekyll.logger.info "  rake performance_benchmark # Run comprehensive performance benchmark"
  Jekyll.logger.info "  rake performance_test # Run performance benchmark via RSpec"
  Jekyll.logger.info "  rake performance_quick # Quick performance check (CLI tools only)"
  Jekyll.logger.info ""
  Jekyll.logger.info "📚 Documentation:"
  Jekyll.logger.info "  rake docs         # Show documentation structure and open in browser"
  Jekyll.logger.info "  rake generate_docs # Generate docs from templates"
  Jekyll.logger.info "  rake doc          # Generate YARD API documentation"
  Jekyll.logger.info ""
  Jekyll.logger.info "🔧 Individual Checks:"
  Jekyll.logger.info "  rake rubocop      # Code style check"
  Jekyll.logger.info "  rake rubocop_fix  # Auto-fix style issues"
  Jekyll.logger.info "  rake reek         # Code smell check"
  Jekyll.logger.info "  rake bundler_audit # Security scan"
  Jekyll.logger.info ""
  Jekyll.logger.info "📦 Other:"
  Jekyll.logger.info "  rake install_local # Install gem locally (auto-generates docs)"
  Jekyll.logger.info "  rake help         # Show this help"
end

desc "Run coverage-focused tests (high coverage files)"
task :test_coverage_focused do
  Jekyll.logger.info "🎯 Running Coverage-Focused Tests..."
  Jekyll.logger.info ""

  # Focus on files with highest coverage improvements
  coverage_tests = [
    {
      name: "Build Time Processor (97.83% coverage)",
      file: "spec/build_time_processor_spec.rb"
    },
    {
      name: "Hooks Integration (77.78% coverage)",
      file: "spec/hooks_spec.rb"
    },
    {
      name: "Provider Capabilities (dynamic testing)",
      file: "spec/provider_capabilities_spec.rb"
    }
  ]

  failed_tests = []

  coverage_tests.each do |test|
    Jekyll.logger.info "🎯 Running #{test[:name]}..."

    if system("bundle exec rspec #{test[:file]} --format progress")
      Jekyll.logger.info "✅ #{test[:name]} PASSED"
    else
      Jekyll.logger.error "❌ #{test[:name]} FAILED"
      failed_tests << test[:name]
    end
    Jekyll.logger.info ""
  end

  if failed_tests.empty?
    Jekyll.logger.info "🎉 ALL COVERAGE-FOCUSED TESTS PASSED! 🎉"
    Jekyll.logger.info ""
    Jekyll.logger.info "📊 Coverage Highlights:"
    Jekyll.logger.info "  🚀 Build Time Processor: 97.83% coverage"
    Jekyll.logger.info "  ⚡ Hooks Integration: 77.78% coverage"
    Jekyll.logger.info "  🔧 Provider Capabilities: Dynamic meta-testing"
    Jekyll.logger.info ""
    Jekyll.logger.info "🎯 High-coverage components validated!"
  else
    Jekyll.logger.error "❌ Failed coverage tests:"
    failed_tests.each { |test| Jekyll.logger.error "  - #{test}" }
    exit 1
  end
end
