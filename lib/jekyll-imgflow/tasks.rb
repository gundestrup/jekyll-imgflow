# frozen_string_literal: true

require "fileutils"
require "rake"
require "rubygems"

module JekyllImgFlow
  # Rake tasks for listing and installing built-in presets.
  #
  # Tasks (defined in the host project's Rakefile):
  #   imgflow:presets       — list built-in presets and their install status
  #   imgflow:install_presets — copy built-in presets into the site's
  #     _data/imgflow/presets/ directory (use overwrite=true to replace)
  module Tasks
    extend Rake::DSL

    class << self
      # Path to built-in presets shipped with the gem
      # @return [String]
      def builtin_presets_dir
        File.expand_path("presets", __dir__)
      end

      # Names of built-in presets (without .yml extension)
      # @return [Array<String>]
      def builtin_preset_names
        return [] unless Dir.exist?(builtin_presets_dir)

        Dir.glob(File.join(builtin_presets_dir, "*.yml")).map do |f|
          File.basename(f, ".yml")
        end.sort
      end

      # Path where presets are installed in the consuming site
      # @return [String]
      def site_presets_dir
        File.join(Dir.pwd, "_data", "imgflow", "presets")
      end

      # List built-in presets and show their install status in the current site
      def list_presets
        puts "ImgFlow built-in presets:"
        puts
        builtin_preset_names.each do |name|
          gem_path = File.join(builtin_presets_dir, "#{name}.yml")
          site_path = File.join(site_presets_dir, "#{name}.yml")
          site_exists = File.exist?(site_path)

          status = if !site_exists
                     "not installed"
                   elsif same_content?(gem_path, site_path)
                     "up to date"
                   else
                     "modified or outdated"
                   end

          puts "  #{name}"
          puts "    gem:    #{gem_path}"
          puts "    site:   #{site_path}"
          puts "    status: #{status}"
          puts
        end
        puts "To install: bundle exec rake imgflow:install_presets"
        puts "To overwrite modified copies: bundle exec rake 'imgflow:install_presets[true]'"
      end

      # Copy built-in presets into the site's _data/imgflow/presets/ directory
      # @param overwrite [Boolean] If true, replace modified copies
      # @return [Hash] Summary with :installed and :skipped arrays
      def install_presets(overwrite: false)
        installed = []
        skipped = []

        FileUtils.mkdir_p(site_presets_dir)

        builtin_preset_names.each do |name|
          gem_path = File.join(builtin_presets_dir, "#{name}.yml")
          site_path = File.join(site_presets_dir, "#{name}.yml")

          if File.exist?(site_path) && !overwrite
            if same_content?(gem_path, site_path)
              puts "  #{name}.yml: already up to date (skip)"
            else
              puts "  #{name}.yml: exists and differs (skip — use overwrite: true to replace)"
              skipped << name
            end
          else
            existed = File.exist?(site_path)
            FileUtils.cp(gem_path, site_path)
            action = existed ? "updated" : "installed"
            puts "  #{name}.yml: #{action}"
            installed << name
          end
        end

        { installed: installed, skipped: skipped }
      end

      # Check if two files have identical content
      # @param path_a [String]
      # @param path_b [String]
      # @return [Boolean]
      def same_content?(path_a, path_b)
        File.read(path_a) == File.read(path_b)
      rescue Errno::ENOENT
        false
      end

      def install_rake_tasks
        return if Rake::Task.task_defined?("imgflow:presets")

        namespace :imgflow do
          desc "List built-in ImgFlow presets and their install status"
          task :presets do
            JekyllImgFlow::Tasks.list_presets
          end

          desc "Copy built-in ImgFlow presets into _data/imgflow/presets/"
          task :install_presets, [:overwrite] do |_task, args|
            overwrite = args[:overwrite] == "true"
            JekyllImgFlow::Tasks.install_presets(overwrite: overwrite)
          end
        end
      end
    end

    install_rake_tasks
  end
end
