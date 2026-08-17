# frozen_string_literal: true

module Jekyll
  class ImgflowTag < Liquid::Tag
    def initialize(tag_name, markup, tokens)
      super
      @markup = markup.strip
    end

    def render(context)
      # Get components
      components = get_imgflow_components(context)

      # Check if markup contains preset
      markup_to_parse = if @markup.include?("preset:")
                          # Route through PresetManager: preset → tags:value → Parser
                          expand_preset_markup(@markup, components[:preset_manager])
                        else
                          # Direct route: markup → Parser
                          @markup
                        end

      # Use central parser to parse markup (uniform for both paths)
      parsed = JekyllImgFlow::Parser.parse(markup_to_parse, context)

      # Process operations through the new architecture
      process_operations(components, parsed, context)
    rescue StandardError => e
      # Handle errors gracefully - don't crash the build for one image
      Jekyll.logger.error "ImgFlow Error: #{e.message}"
      Jekyll.logger.debug "ImgFlow Backtrace: #{e.backtrace.first(5).join("\n")}"
      "<!-- ImgFlow Error: #{e.message} -->"
    end

    private

    def expand_preset_markup(markup, preset_manager)
      # Parse markup to extract image path, preset name, and user options
      parts = markup.split
      image_path = parts.first

      # Extract preset name and user options
      preset_name = nil
      user_options = {}

      parts[1..].each do |part|
        if part.start_with?("preset:")
          preset_name = part.split(":", 2).last
        elsif part.include?(":")
          key, value = part.split(":", 2)
          user_options[key.to_sym] = value
        end
      end

      # Get preset markup from PresetManager
      preset_markup = preset_manager.build_markup_from_preset(preset_name, user_options)

      # Combine image path with preset markup
      "#{image_path} #{preset_markup}"
    end

    def process_operations(components, parsed, context)
      return "" unless parsed[:image_path]

      site = context.registers[:site]
      page = context.registers[:page]

      # Resolve input path
      input_path = resolve_image_path(parsed[:image_path], site, components[:config])
      raise ArgumentError, "Input image file not found: #{input_path}" unless File.file?(input_path)

      # Store original name relative to the configured originals directory
      # so output can mirror the original directory structure
      originals_dir = File.join(site.source, components[:config].originals)
      original_name = input_path.sub("#{originals_dir}/", "")

      # Get page path for manifest tracking
      # Try multiple attributes to get the page identifier
      page_path = if page
                    page["path"] || page["url"] || page["name"] || "unknown"
                  else
                    "unknown"
                  end

      # Process operations using clean architecture
      operations = parsed[:operations]

      result = if operations.empty?
                 # No operations - use original image
                 input_path
               else
                 # Generate filename early to check existence
                 operation = operations.first
                 params = operation[:params]

                 # For default versions, include default format and quality for proper identification
                 if determine_version_type(params, components[:config]) == :default
                   params = params.dup
                   params[:format] ||= components[:config].formats.first  # Use default format
                   params[:quality] ||= components[:config].quality       # Use default quality
                 end

                 # Preserve original directory structure under output
                 subdir = File.dirname(original_name)
                 subdir = nil if subdir == "."

                 filename = components[:filename_generator].generate_filename(input_path, params)
                 output_path = components[:path_resolver].resolve_source_output_path(filename, subdir)

                 # Determine version type
                 version_type = determine_version_type(params, components[:config])

                 # Check if version exists in manifest
                 Jekyll.logger.debug "🔍 ImgflowTag: Checking existence - original_name: #{original_name}, version_type: #{version_type}, page_path: #{page_path}"
                 Jekyll.logger.debug "🔍 ImgflowTag: Params being checked: #{params.inspect}"

                 if components[:manifest].version_exists?(original_name, params, version_type)
                   # Version exists - update page usage and return path
                   Jekyll.logger.debug "✅ ImgflowTag: Version exists! Updating page usage"
                   components[:manifest].update_page_usage(original_name, params, version_type,
                                                           page_path)
                   output_path
                 else
                   # Version doesn't exist - create it
                   Jekyll.logger.debug "❌ ImgflowTag: Version doesn't exist - creating"
                   versions = components[:manifest].get_versions(original_name)
                   Jekyll.logger.debug "🔍 ImgflowTag: Manifest has - default: #{versions['default']&.length || 0}, specialized: #{versions['specialized']&.length || 0}"

                   components[:operation_processor].process_operation(
                     original_name,
                     operation,
                     input_path,
                     page_path
                   )
                 end
               end

      # Convert absolute paths to relative for HTML generation
      relative_result = if result.start_with?(site.dest)
                          # Processed images - remove site.dest and leading /
                          result.sub(%r{^#{Regexp.escape(site.dest)}/}, "")
                        elsif result.start_with?(site.source)
                          # Original images - convert from source to relative and remove leading /
                          result.sub(%r{^#{Regexp.escape(site.source)}/}, "")
                        else
                          # Already relative or other format - remove leading / if present
                          result.start_with?("/") ? result[1..] : result
                        end

      # Generate HTML for the result
      generate_html([relative_result], parsed, context)
    end

    def generate_html(results, parsed, context)
      return "" if results.empty?

      # Extract attributes and markup format from parsed data
      attributes = extract_element_attributes(parsed)
      markup_format = parsed[:markup_format] || "img"

      # Get config from components
      components = get_imgflow_components(context)
      config = components[:config]

      # Use unified HTML generator with config
      JekyllImgFlow::HtmlGenerator.generate(results, attributes, markup_format, context, config)
    end

    # Extract element-specific attributes from parsed data
    def extract_element_attributes(parsed)
      # Start with basic HTML attributes
      base_attrs = parsed[:html_attributes] || {}

      # Build element-specific attribute structure
      {
        img: base_attrs.reject do |k, _v|
          k.to_s.start_with?("picture-", "source-", "a-", "parent-")
        end,
        picture: extract_prefixed_attrs(base_attrs, "picture-"),
        source: extract_prefixed_attrs(base_attrs, "source-"),
        a: extract_prefixed_attrs(base_attrs, "a-"),
        parent: extract_prefixed_attrs(base_attrs, "parent-"),
        alt: base_attrs[:alt],
        link: base_attrs[:link]
      }
    end

    # Extract attributes with a specific prefix
    def extract_prefixed_attrs(attrs, prefix)
      attrs.select { |k, _v| k.to_s.start_with?(prefix) }
           .transform_keys { |k| k.to_s.sub(prefix, "") }
    end

    def render_liquid_variable(variable, context)
      # Simple liquid variable rendering
      variable_name = variable.tr("{}", "").strip
      context[variable_name] || variable
    end

    # Determine if params represent a default or specialized version
    def determine_version_type(params, config)
      config.determine_version_type(params)
    end

    def resolve_image_path(image_path, site, config)
      # Use PathResolver for consistent path handling
      path_resolver = JekyllImgFlow::PathResolver.new(config)

      # Handle different path formats
      if image_path.start_with?("/")
        # Absolute site-root path: /assets/images/originals/valdemar/photo.jpg
        File.join(site.source, image_path)
      else
        # Relative path: photo.jpg or valdemar/photo.jpg
        # Always resolve against the configured originals directory
        path_resolver.cli_path(image_path)
      end
    end

    def get_imgflow_components(context)
      # Get or create ImgFlow components
      site = context.registers[:site]

      # Cache components on site object
      unless site.imgflow_components
        config = JekyllImgFlow::Config.new(site)
        manifest = JekyllImgFlow::ManifestManager.new(site)
        path_resolver = JekyllImgFlow::PathResolver.new(config)
        filename_generator = JekyllImgFlow::FilenameGenerator.new
        registry = JekyllImgFlow::ProviderRegistry.new(config)
        provider = registry.current_provider
        operation_processor = JekyllImgFlow::OperationProcessor.new(provider, path_resolver,
                                                                    manifest, config)
        preset_manager = JekyllImgFlow::PresetManager.new(site, config)

        site.imgflow_components = {
          config: config,
          manifest: manifest,
          path_resolver: path_resolver,
          filename_generator: filename_generator,
          registry: registry,
          provider: provider,
          operation_processor: operation_processor,
          preset_manager: preset_manager
        }
      end

      # Manifest is shared with BuildTimeProcessor for page usage tracking

      site.imgflow_components
    end
  end
end

# Register the tag with Liquid
Liquid::Template.register_tag("imgflow", Jekyll::ImgflowTag)
