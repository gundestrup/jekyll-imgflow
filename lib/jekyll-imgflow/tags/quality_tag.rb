# frozen_string_literal: true

require_relative "base_tag"

module JekyllImgFlow
  module Tags
    # Quality tag - validates and processes quality settings
    class QualityTag < BaseTag
      def process(input_path, output_path, options = {})
        ensure_output_dir(output_path)

        # Validate quality (use default from config if not provided)
        quality = validate_quality(options[:quality])

        @provider.quality = quality
        @provider.execute(input_path, output_path)
      end
    end
  end
end
