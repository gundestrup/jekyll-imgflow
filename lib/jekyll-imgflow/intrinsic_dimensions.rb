# frozen_string_literal: true

require "fastimage"

module JekyllImgFlow
  # Reads a generated image file's pixel dimensions so emitted markup can
  # carry intrinsic width/height — the browser reserves the image box before
  # download (avoids layout shift). Mixed into HtmlGenerator.
  module IntrinsicDimensions
    # Emit the file's pixel dimensions unless the user supplied any.
    # Partial overrides (e.g. only width:) would skew the aspect ratio,
    # so both attributes are skipped together.
    def inject_intrinsic_dimensions(attrs, result)
      return unless result
      return if attrs["width"] || attrs["height"]

      size = intrinsic_size(result)
      return unless size

      attrs["width"] = size[0]
      attrs["height"] = size[1]
    end

    private

    def base_img_attrs(result = nil)
      attrs = @attributes[:img].dup
      attrs["alt"] = @attributes[:alt] if @attributes[:alt]
      inject_intrinsic_dimensions(attrs, result)
      attrs
    end

    def intrinsic_size(result)
      @intrinsic_sizes ||= {}
      return @intrinsic_sizes[result] if @intrinsic_sizes.key?(result)

      @intrinsic_sizes[result] = resolve_intrinsic_size(result)
    end

    def resolve_intrinsic_size(result)
      site = @context&.registers&.dig(:site)
      return unless site

      rel = result.delete_prefix("/")
      roots = [site.source]
      roots << site.dest if site.respond_to?(:dest)
      path = roots.map { |root| File.join(root, rel) }.find { |p| File.file?(p) }
      return unless path

      FastImage.size(path)
    rescue FastImage::ImageFetchError, FastImage::UnknownImageType
      nil
    end
  end
end
