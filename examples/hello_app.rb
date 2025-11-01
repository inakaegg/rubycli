# frozen_string_literal: true

# Example CLI target without doc comments; see README section 1.
module HelloApp
  module_function

  def greet(name)
    puts "Hello, #{name}!"
  end
end
