#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/jekyll-imgflow/picture_tag_adaptor"

# Simple test objects
site = Object.new
config = Object.new

adaptor = JekyllImgFlow::PictureTagAdaptor.new(site, config)

test_cases = [
  # Basic HTML attributes
  '{% picture example.jpg --alt "Example Image" %}',

  # Element-specific attributes
  '{% picture example.jpg --img class="responsive" id="main-image" %}',

  # Picture element attributes
  '{% picture example.jpg --picture class="hero" --img class="responsive" %}',

  # Link attributes
  '{% picture example.jpg --link "/example" --a class="image-link" %}',

  # Parent attributes
  "{% picture example.jpg --parent data-parallax %}",

  # Markup formats
  '{% picture example.jpg data_auto --alt "Lazy loaded" %}',
  '{% picture example.jpg picture --picture class="gallery" %}',

  # Complex example with everything
  '{% picture hero example.jpg 16:9 --img class="hero-image" --picture class="hero-wrapper" --alt "Hero Image" --link "/hero" data_auto %}'
]

puts "🎯 Enhanced Picture Tag Adaptor Test"
puts "=" * 50

test_cases.each do |test_case|
  puts "\nInput:  #{test_case}"

  # Debug: Show parsed arguments
  content = test_case.match(/\{%\s*picture\s+(.+?)\s*%}/)[1]
  args = adaptor.send(:parse_arguments, content)
  puts "Parsed args: #{args.inspect}"

  result = adaptor.translate_to_imgflow(test_case)

  puts "Output: #{result[:markup]}"

  puts "All attributes: #{result[:attributes]}"

  if result[:attributes].any? { |k, v| (k == :alt && v) || (k != :alt && v.is_a?(Hash) && v.any?) }
    puts "Parsed Attributes:"
    result[:attributes].each do |element, attrs|
      next if attrs.nil? || (attrs.is_a?(Hash) && attrs.empty?)

      case element
      when :alt
        puts "  alt: #{attrs}"
      when :link
        puts "  link: #{attrs}"
      else
        puts "  #{element}: #{attrs}"
      end
    end
  end

  puts "Markup format: #{result[:markup_format]}" if result[:markup_format]
  puts "---"
end

puts "\n🎉 Enhanced adaptor test complete!"
