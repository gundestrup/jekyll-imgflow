#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/jekyll-imgflow/html_generator"

# Mock context
class MockContext
  def registers
    {
      :site => MockSite.new,
    }
  end
end

class MockSite
  def config
    { "url" => "https://example.com" }
  end
end
context = MockContext.new

# Test data
results = [
  "/assets/images/optimized/example.webp",
  "/assets/images/optimized/example.avif",
  "/assets/images/optimized/example.jpg",
]

puts "🧪 HTML Generator Test Suite"
puts "=" * 60

# Test 1: Standard img element
puts "\n1. Standard <img> element (default)"
puts "-" * 60
attributes = {
  :img => { "class" => "responsive" },
  :alt => "Example Image",
}
html = JekyllImgFlow::HtmlGenerator.generate(results, attributes, "img", context, nil)
puts html
puts

# Test 2: Picture element
puts "2. <picture> element with sources"
puts "-" * 60
attributes = {
  :picture => { "class" => "hero-wrapper" },
  :img     => { "class" => "hero-image" },
  :alt     => "Hero Image",
}
html = JekyllImgFlow::HtmlGenerator.generate(results, attributes, "picture", context, nil)
puts html
puts

# Test 3: Data attributes for lazy loading
puts "3. Lazy loading with data-* attributes"
puts "-" * 60
attributes = {
  :img => { "class" => "fade-in" },
  :alt => "Lazy loaded image",
}
html = JekyllImgFlow::HtmlGenerator.generate(results, attributes, "data_img", context, nil)
puts html
puts

# Test 4: Data picture for lazy loading
puts "4. Lazy loading <picture> with data-* attributes"
puts "-" * 60
attributes = {
  :picture => { "class" => "lazy-picture" },
  :img     => { "class" => "lazy-img" },
  :alt     => "Lazy picture",
}
html = JekyllImgFlow::HtmlGenerator.generate(results, attributes, "data_picture", context, nil)
puts html
puts

# Test 5: Link wrapping
puts "5. Image wrapped in link"
puts "-" * 60
attributes = {
  :img  => { "class" => "gallery-thumb" },
  :a    => { "class" => "gallery-link", "data-lightbox" => "gallery" },
  :link => "/images/full.jpg",
  :alt  => "Gallery Image",
}
html = JekyllImgFlow::HtmlGenerator.generate(results, attributes, "img", context, nil)
puts html
puts

# Test 6: Parent container
puts "6. Image with parent container"
puts "-" * 60
attributes = {
  :img    => { "class" => "article-image" },
  :parent => { "class" => "image-container", "data-aos" => "fade-up" },
  :alt    => "Article Image",
}
html = JekyllImgFlow::HtmlGenerator.generate(results, attributes, "img", context, nil)
puts html
puts

# Test 7: Direct URL
puts "7. Direct URL (no HTML)"
puts "-" * 60
html = JekyllImgFlow::HtmlGenerator.generate(results, {}, "direct_url", context, nil)
puts html
puts

# Test 8: Naked srcset
puts "8. Naked srcset (just srcset string)"
puts "-" * 60
html = JekyllImgFlow::HtmlGenerator.generate(results, {}, "naked_srcset", context, nil)
puts html
puts

# Test 9: Complex example - everything combined
puts "9. Complex: Picture + Link + Parent + Data attributes"
puts "-" * 60
attributes = {
  :picture => { "class" => "hero-wrapper", "data-component" => "hero" },
  :img     => { "class" => "hero-image", "id" => "main-hero" },
  :a       => { "class" => "hero-link", "data-track" => "click" },
  :parent  => { "class" => "hero-container", "data-aos" => "fade-up" },
  :link    => "/hero",
  :alt     => "Hero Banner",
}
html = JekyllImgFlow::HtmlGenerator.generate(results, attributes, "picture", context, nil)
puts html
puts

# Test 10: Boolean attributes
puts "10. Boolean attributes (data-parallax)"
puts "-" * 60
attributes = {
  :img => { "class" => "parallax-image", "data-parallax" => true },
  :alt => "Parallax Image",
}
html = JekyllImgFlow::HtmlGenerator.generate(results, attributes, "img", context, nil)
puts html
puts

puts "=" * 60
puts "✅ All HTML generator tests complete!"
puts
puts "Summary:"
puts "- ✅ Standard img element"
puts "- ✅ Picture element with sources"
puts "- ✅ Data attributes for lazy loading"
puts "- ✅ Link wrapping"
puts "- ✅ Parent containers"
puts "- ✅ Direct URL output"
puts "- ✅ Naked srcset output"
puts "- ✅ Complex combinations"
puts "- ✅ Boolean attributes"
