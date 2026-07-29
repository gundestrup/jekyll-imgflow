#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/jekyll-imgflow/picture_tag_adaptor"

# Simple test objects
site = Object.new
config = Object.new

adaptor = JekyllImgFlow::PictureTagAdaptor.new(site, config)

test_cases = [
  "{% picture example.jpg mobile: example_mobile.jpg 1:1 %}",
  "{% picture example.jpg 16:9 center %}",
  "{% picture hero example.jpg %}",
  "{% picture example.jpg --alt Example %}",
  "{% picture example.jpg --alt Example --link /example %}"
]

test_cases.each do |test_case|
  puts "Input:  #{test_case}"
  result = adaptor.translate_to_imgflow(test_case)
  puts "Output: #{result}"
  puts "---"
end
