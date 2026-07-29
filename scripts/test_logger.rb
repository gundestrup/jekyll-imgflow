#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"

class TestLogger
  class << self
    attr_accessor :current_session, :log_dir, :start_time

    def auto_start
      @log_dir = File.join(Dir.pwd, "test_logs")
      @start_time = Time.now

      ensure_log_directory
      start_test_session

      # Register at_exit hook to automatically save results
      at_exit { finish_session }
    end

    def start_test_session
      @current_session = {
        timestamp: @start_time.iso8601,
        start_time: @start_time.iso8601,
        test_files: [],
        environment: capture_environment
      }
    end

    def finish_session
      return unless @current_session

      end_time = Time.now
      @current_session[:end_time] = end_time.iso8601
      @current_session[:duration_seconds] = (end_time - @start_time).round(2)

      # Use RSpec built-in results instead of custom JSON parsing
      load_rspec_results_from_output

      # Save results
      save_results
      update_history

      # Display summary if running interactively
      display_summary if $stdout.tty?
    end

    def track_test_file(file_path)
      @current_session[:test_files] << file_path if @current_session
      @current_session[:test_files].uniq!
    end

    private

    def ensure_log_directory
      FileUtils.mkdir_p(@log_dir)
    end

    def capture_environment
      {
        ruby_version: RUBY_VERSION,
        jekyll_env: ENV.fetch("JEKYLL_ENV", nil),
        git_branch: `git branch --show-current 2>/dev/null`.strip,
        git_commit: `git rev-parse HEAD 2>/dev/null`.strip,
        working_directory: Dir.pwd
      }
    end

    def load_rspec_results_from_output
      # Parse results from our custom logging files instead of RSpec JSON formatter
      success_file = File.join(@log_dir, "latest_success.json")
      failure_file = File.join(@log_dir, "latest_failures.json")

      if File.exist?(success_file)
        @current_session[:rspec_results] = {
          "summary" => {
            "example_count" => JSON.parse(File.read(success_file))["total_examples"],
            "failure_count" => 0,
            "pending_count" => 0,
            "duration" => @current_session[:duration_seconds]
          },
          "status" => "passed"
        }
      elsif File.exist?(failure_file)
        failure_data = JSON.parse(File.read(failure_file))
        @current_session[:rspec_results] = {
          "summary" => {
            "example_count" => failure_data["total_examples"],
            "failure_count" => failure_data["total_failures"],
            "pending_count" => 0,
            "duration" => @current_session[:duration_seconds]
          },
          "status" => "failed",
          "failures" => failure_data["test_failures"]
        }
      else
        # Fallback: try to parse from terminal output or use defaults
        @current_session[:rspec_results] = {
          "summary" => {
            "example_count" => 0,
            "failure_count" => 0,
            "pending_count" => 0,
            "duration" => @current_session[:duration_seconds]
          },
          "status" => "unknown"
        }
      end
    end

    def save_results
      # Save latest run only (timestamp files are redundant with our new logging system)
      latest_file = File.join(@log_dir, "latest_test_run.json")
      File.write(latest_file, JSON.pretty_generate(@current_session))

      # Only create timestamp file if explicitly needed for debugging
      return unless ENV["DEBUG_TEST_LOGGING"] == "true"

      timestamp_file = File.join(@log_dir,
                                 "test_run_#{@current_session[:timestamp].tr(':', '-')}.json")
      File.write(timestamp_file, JSON.pretty_generate(@current_session))
    end

    def update_history
      history_file = File.join(@log_dir, "test_history.json")
      history = File.exist?(history_file) ? JSON.parse(File.read(history_file)) : []

      history_entry = {
        timestamp: @current_session[:timestamp],
        success: @current_session[:rspec_results]&.dig("summary",
                                                       "failure_count")&.zero?,
        duration_seconds: @current_session[:duration_seconds],
        total_tests: @current_session[:rspec_results]&.dig("summary", "example_count") || 0,
        failed_tests: @current_session[:rspec_results]&.dig("summary", "failure_count") || 0,
        test_files: @current_session[:test_files],
        git_commit: @current_session[:environment][:git_commit],
        git_branch: @current_session[:environment][:git_branch]
      }

      history << history_entry
      history = history.last(50) if history.length > 50

      File.write(history_file, JSON.pretty_generate(history))
    end

    def display_summary
      puts "\n#{'=' * 60}"
      puts "🧪 TEST RUN SUMMARY"
      puts "=" * 60

      if @current_session[:rspec_results]
        summary = @current_session[:rspec_results]["summary"] || {}
        total = summary["example_count"] || 0
        failed = summary["failure_count"] || 0
        pending = summary["pending_count"] || 0
        passed = total - failed - pending

        puts "✅ Status: #{failed.zero? ? 'PASSED' : 'FAILED'}"
        puts "⏰  Duration: #{@current_session[:duration_seconds]}s"
        puts "📅 Timestamp: #{@current_session[:timestamp]}"
        puts "🌿 Git Branch: #{@current_session[:environment][:git_branch]}"
        puts "🔢 Git Commit: #{@current_session[:environment][:git_commit][0..7]}"

        puts "\n📊 Test Results:"
        puts "   Total Tests: #{total}"
        puts "   ✅ Passed: #{passed}"
        puts "   ❌ Failed: #{failed}"
        puts "   ⏸️  Pending: #{pending}" if pending.positive?

        if failed.positive? && @current_session[:rspec_results]["examples"]
          puts "\n❌ Failed Tests:"
          @current_session[:rspec_results]["examples"]
            .select { |example| example["status"] == "failed" }
            .each do |example|
            puts "   - #{example['full_description']}"
            puts "     Location: #{example['file_path']}:#{example['line_number']}"
          end
        end
      else
        puts "ℹ️  Test completed (no RSpec results available)"
        puts "⏰  Duration: #{@current_session[:duration_seconds]}s"
        puts "📅 Timestamp: #{@current_session[:timestamp]}"
      end

      puts "\n📁 Log files saved in: #{@log_dir}"
      puts "=" * 60
    end

    def self.show_status
      log_dir = File.join(Dir.pwd, "test_logs")
      puts "\n#{'=' * 60}"
      puts "📊 TEST STATUS DASHBOARD"
      puts "=" * 60

      latest_file = File.join(log_dir, "latest_test_run.json")
      if File.exist?(latest_file)
        latest = JSON.parse(File.read(latest_file))
        puts "🕐 Latest Run: #{latest['timestamp']}"

        if latest["rspec_results"]
          summary = latest["rspec_results"]["summary"] || {}
          failed = summary["failure_count"] || 0
          total = summary["example_count"] || 0
          puts "📈 Status: #{failed.zero? ? '✅ PASSED' : '❌ FAILED'}"
          puts "📊 Results: #{total - failed}/#{total} passed"
        else
          puts "📈 Status: ℹ️  Completed"
        end

        puts "⏱️  Duration: #{latest['duration_seconds']}s"

        # Show recent history
        history_file = File.join(log_dir, "test_history.json")
        if File.exist?(history_file)
          history = JSON.parse(File.read(history_file))
          puts "\n📜 Recent History (last 10):"
          history.last(10).each_with_index do |entry, _index|
            status = entry["success"] ? "✅" : "❌"
            puts "   #{status} #{entry['timestamp']} - #{entry['total_tests'] - entry['failed_tests']}/#{entry['total_tests']} tests (#{entry['duration_seconds']}s)"
          end
        end
      else
        puts "📝 No test logs found. Run tests first to generate logs."
      end

      puts "\n📁 Log Directory: #{log_dir}"
      puts "=" * 60
    end
  end

  def self.show_status
    log_dir = File.join(Dir.pwd, "test_logs")
    puts "\n#{'=' * 60}"
    puts "📊 TEST STATUS DASHBOARD"
    puts "=" * 60

    latest_file = File.join(log_dir, "latest_test_run.json")
    if File.exist?(latest_file)
      latest = JSON.parse(File.read(latest_file))
      puts "🕐 Latest Run: #{latest['timestamp']}"

      if latest["rspec_results"]
        summary = latest["rspec_results"]["summary"] || {}
        failed = summary["failure_count"] || 0
        total = summary["example_count"] || 0
        puts "📈 Status: #{failed.zero? ? '✅ PASSED' : '❌ FAILED'}"
        puts "📊 Results: #{total - failed}/#{total} passed"
      else
        puts "📈 Status: ℹ️  Completed"
      end

      puts "⏱️  Duration: #{latest['duration_seconds']}s"

      # Show recent history
      history_file = File.join(log_dir, "test_history.json")
      if File.exist?(history_file)
        history = JSON.parse(File.read(history_file))
        puts "\n📜 Recent History (last 10):"
        history.last(10).each_with_index do |entry, _index|
          status = entry["success"] ? "✅" : "❌"
          puts "   #{status} #{entry['timestamp']} - #{entry['total_tests'] - entry['failed_tests']}/#{entry['total_tests']} tests (#{entry['duration_seconds']}s)"
        end
      end
    else
      puts "📝 No test logs found. Run tests first to generate logs."
    end

    puts "\n📁 Log Directory: #{log_dir}"
    puts "=" * 60
  end
end

# CLI interface for standalone usage
if __FILE__ == $PROGRAM_NAME
  case ARGV[0]
  when "status"
    TestLogger.show_status
  else
    puts "Test Logger is integrated into spec_helper.rb"
    puts "Run tests normally: bundle exec rspec"
    puts "Show status: rake test_status"
  end
end
