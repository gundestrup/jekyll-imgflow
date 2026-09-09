# frozen_string_literal: true

require "fileutils"

module JekyllImgFlow
  class GeneratedFileCleaner
    def initialize(site, config)
      @site = site
      @config = config
    end

    def delete(output_path)
      return false unless output_path

      unregister_static_file(output_path)
      deleted = false
      [@site.source, @site.dest].each do |base_path|
        path = safe_generated_path(base_path, output_path)
        next unless path && File.file?(path)

        File.delete(path)
        remove_empty_output_dirs(File.dirname(path), output_root(base_path))
        deleted = true
      end
      deleted
    end

    def clear
      roots = [@site.source, @site.dest].map { |base_path| output_root(base_path) }
      valid = roots.zip([@site.source, @site.dest]).all? do |directory, base_path|
        base = File.expand_path(base_path)
        directory.start_with?("#{base}#{File::SEPARATOR}")
      end
      raise "Refusing to delete optimized directory outside configured roots" unless valid

      unregister_output_tree(roots.first)
      files = roots.flat_map do |directory|
        Dir.glob(File.join(directory, "**", "*")).select { |path| File.file?(path) }
      end
      files = files.uniq
      files.each { |path| File.delete(path) }
      files.length
    end

    private

    def unregister_static_file(output_path)
      return unless @site.is_a?(Jekyll::Site)

      source_path = safe_generated_path(@site.source, output_path)
      @site.static_files.reject! do |static_file|
        source_path && File.expand_path(static_file.path) == source_path
      end
    end

    def unregister_output_tree(root)
      return unless @site.is_a?(Jekyll::Site)

      @site.static_files.reject! do |static_file|
        File.expand_path(static_file.path).start_with?("#{root}#{File::SEPARATOR}")
      end
    end

    def safe_generated_path(base_path, output_path)
      root = output_root(base_path)
      candidate = File.expand_path(output_path.delete_prefix("/"), base_path)
      candidate if candidate.start_with?("#{root}#{File::SEPARATOR}")
    end

    def output_root(base_path)
      File.expand_path(@config.output, base_path)
    end

    def remove_empty_output_dirs(directory, root)
      while directory.start_with?("#{root}#{File::SEPARATOR}") && Dir.empty?(directory)
        Dir.rmdir(directory)
        directory = File.dirname(directory)
      end
    end
  end
end
