# frozen_string_literal: true

require "shellwords"
require "fastimage"

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
      parts = Shellwords.split(markup)
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

      # Combine image path with preset markup. Keep the path quoted because
      # filenames may contain spaces.
      image_markup = if image_path.include?(" ")
                       escaped_path = image_path.gsub("\\") { "\\\\" }.gsub('"', '\\"')
                       "\"#{escaped_path}\""
                     else
                       image_path
                     end
      "#{image_markup} #{preset_markup}"
    end

    def process_operations(components, parsed, context)
      return "" unless parsed[:image_path]

      site = context.registers[:site]
      input_path = resolve_input_path(parsed[:image_path], site, components[:config])
      original_name = original_image_name(input_path, site, components[:config])
      page_path = page_identifier(context.registers[:page])
      results, modal_results = process_image_variants(components, parsed, original_name, input_path,
                                                      page_path)
      render_processed_results(results, modal_results, parsed, site, context)
    end

    def resolve_input_path(image_path, site, config)
      input_path = resolve_image_path(image_path, site, config)
      raise ArgumentError, "Input image file not found: #{input_path}" unless File.file?(input_path)

      input_path
    end

    def original_image_name(input_path, site, config)
      originals_dir = File.join(site.source, config.originals)
      input_path.sub("#{originals_dir}/", "")
    end

    def page_identifier(page)
      (page && (page["path"] || page["url"] || page["name"])) || "unknown"
    end

    def process_image_variants(components, parsed, original_name, input_path, page_path)
      operations = parsed[:operations]
      return [[input_path], []] if operations.empty?

      operation = operations.first
      results = process_variants(components, operation, original_name, input_path, page_path)
      modal_results = process_modal_variants(components, operation, parsed, original_name,
                                             input_path, page_path)
      [results, modal_results]
    end

    def render_processed_results(results, modal_results, parsed, site, context)
      relative_results = results.uniq.map { |result| relative_result_path(result, site) }
      relative_modal_results = modal_results.uniq.map do |result|
        relative_result_path(result, site)
      end
      parsed = parsed.merge(markup_format: "picture") if relative_results.length > 1
      generate_html(relative_results, parsed.merge(modal_results: relative_modal_results), context)
    end

    def process_modal_variants(components, operation, parsed, original_name, input_path, page_path)
      config = components[:config]
      return [] unless modal_requested?(parsed, config)

      original_width = FastImage.size(input_path)&.first
      return [] unless original_width

      params = operation[:params].dup
      formats = modal_formats(params, config)
      params.delete(:formats)
      modal_width = [original_width, config.sizes.values.max].min
      formats.map do |format|
        process_variant(components, operation, params.merge(width: modal_width, format: format),
                        original_name, input_path, page_path)
      end
    rescue FastImage::ImageFetchError, FastImage::UnknownImageType
      []
    end

    def modal_formats(params, config)
      formats = Array(params[:formats] || params[:format])
      formats.empty? ? config.formats : formats
    end

    def modal_requested?(parsed, config)
      return false if %w[direct_url naked_srcset].include?(parsed[:markup_format])

      attrs = parsed[:html_attributes] || {}
      return false if attrs[:link]

      modal = attrs[:modal]
      modal.nil? ? (config.respond_to?(:image_modal) && config.image_modal) : modal.to_s == "true"
    end

    def process_variants(components, operation, original_name, input_path, page_path)
      params = operation[:params].dup
      formats = Array(params.delete(:formats) || params[:format])
      # When no format is explicitly specified, generate all configured formats
      # (avif, webp, png, jpg) so browsers get a <picture> with <source> tags for
      # modern formats and an <img> fallback. This applies to both default-width
      # versions (which find pre-generated files in the manifest cache) and
      # specialized versions (which are generated on-demand).
      formats = components[:config].formats if formats.empty?

      formats.map do |format|
        variant_params = params.dup
        variant_params[:format] = format
        process_variant(components, operation, variant_params, original_name, input_path, page_path)
      end
    end

    def process_variant(components, operation, params, original_name, input_path, page_path)
      config = components[:config]
      if determine_version_type(params, config) == :default
        params[:format] ||= config.formats.first
        params[:quality] ||= config.quality
      end

      digest = components[:filename_generator].file_digest(input_path)
      variant = operation.merge(params: params, file_digest: digest)
      subdir = File.dirname(original_name)
      subdir = nil if subdir == "."
      filename = components[:filename_generator].generate_filename(input_path, params)
      output_path = components[:path_resolver].resolve_source_output_path(filename, subdir)
      version_type = determine_version_type(params, config)

      if components[:manifest].version_exists?(original_name, params, version_type, digest) &&
         File.file?(output_path)
        components[:stats]&.record_cache_hit
        components[:manifest].update_page_usage(original_name, params, version_type, page_path)
        return output_path
      end

      unless components[:operation_processor]
        Jekyll.logger.warn "ImgFlow:", "No image provider available — " \
                                       "rendering original without optimization."
        return input_path
      end

      components[:operation_processor].process_operation(
        original_name, variant.merge(force_processing: true), input_path, page_path
      )
    end

    def relative_result_path(result, site)
      if result.start_with?(site.dest)
        result.sub(%r{^#{Regexp.escape(site.dest)}/}, "")
      elsif result.start_with?(site.source)
        result.sub(%r{^#{Regexp.escape(site.source)}/}, "")
      else
        result.delete_prefix("/")
      end
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
        link: base_attrs[:link],
        modal: base_attrs[:modal],
        modal_results: parsed[:modal_results] || []
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
      normalized_path = image_path.delete_prefix("/")
      originals_prefix = "#{config.originals.chomp('/')}/"

      if image_path.start_with?("/") || normalized_path.start_with?(originals_prefix)
        # Site-root path, with or without a leading slash:
        # /assets/images/originals/valdemar/photo.jpg
        File.join(site.source, normalized_path)
      else
        # Originals-relative path: photo.jpg or valdemar/photo.jpg
        path_resolver.cli_path(normalized_path)
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
        if provider
          operation_processor = JekyllImgFlow::OperationProcessor.new(provider, path_resolver,
                                                                      manifest, config)
        end
        preset_manager = JekyllImgFlow::PresetManager.new(site, config)

        site.imgflow_components = {
          config: config,
          manifest: manifest,
          path_resolver: path_resolver,
          filename_generator: filename_generator,
          registry: registry,
          provider: provider,
          operation_processor: operation_processor,
          stats: operation_processor&.stats,
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
