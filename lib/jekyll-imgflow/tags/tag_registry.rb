# frozen_string_literal: true

require_relative "base_tag"

module JekyllImgFlow
  module Tags
    # Registry for managing tags
    class TagRegistry
      def self.register_tag(name, tag_class)
        @tags ||= {}
        @tags[name.to_sym] = tag_class
      end

      def self.get_tag(name)
        @tags ||= {}
        discover_tags unless @tags_discovered
        @tags[name.to_sym]
      end

      def self.available_tags
        @tags ||= {}
        discover_tags unless @tags_discovered
        @tags.keys
      end

      # Dynamic tag discovery
      def self.discover_tags
        return if @tags_discovered

        @tags ||= {}
        tags_dir = File.dirname(__FILE__)

        Dir.glob(File.join(tags_dir, "*_tag.rb")).each do |file|
          next if File.basename(file) == "base_tag.rb"

          tag_name = File.basename(file, ".rb").gsub("_tag", "")
          register_tag_from_file(tag_name)
        end

        @tags_discovered = true
        Jekyll.logger.debug "ImgFlow:", "Discovered #{@tags.size} tags"
      end

      def self.register_tag_from_file(name)
        class_name = "#{name.split('_').map(&:capitalize).join}Tag"

        begin
          require_relative "#{name}_tag"
          tag_class = JekyllImgFlow::Tags.const_get(class_name)
          register_tag name.to_sym, tag_class
          Jekyll.logger.debug "ImgFlow:", "Registered tag: #{name} (#{class_name})"
        rescue NameError => e
          Jekyll.logger.warn "ImgFlow:", "Failed to load tag #{name}: #{e.message}"
        rescue LoadError => e
          Jekyll.logger.warn "ImgFlow:", "Failed to require tag #{name}: #{e.message}"
        end
      end

      def self.tags_discovered?
        @tags_discovered ||= false
      end

      # Force discovery (useful for testing)
      def self.reset!
        @tags = {}
        @tags_discovered = false
      end
    end
  end
end
