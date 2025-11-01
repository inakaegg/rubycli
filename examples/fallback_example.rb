# frozen_string_literal: true

# Example showcasing inference when documentation is incomplete.
module FallbackExample
  module_function

  # AMOUNT [Integer] Base amount to process
  def scale(amount, factor = 2, clamp: nil, notify: false)
    result = amount * factor
    result = [result, clamp].min if clamp
    puts "Scaled to #{result}" if notify
    result
  end
end
