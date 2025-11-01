# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'minitest/autorun'
require 'rubycli'

Dir[File.expand_path('fixtures/**/*.rb', __dir__)].sort.each do |path|
  require path
end
