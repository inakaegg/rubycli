# frozen_string_literal: true

# Demonstrates that Rubycli::Runner can locate constants whose names do not
# match the file name. Run with:
#   rubycli examples/mismatched_constant_runner.rb greet --message "Hello"
class FriendlyGreeter
  # NAME [String] Text to display
  # --message MESSAGE [String] Greeting to print (defaults to "Hello")
  def self.greet(name = 'friend', message: 'Hello', quiet: false)
    output = "#{message}, #{name}!"
    puts(output) unless quiet
    output
  end
end
