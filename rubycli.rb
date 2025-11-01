#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/rubycli'

if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  exit Rubycli::CommandLine.run(ARGV)
end
