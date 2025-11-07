# frozen_string_literal: true

# Demonstrates a file whose constant does not match the file name. By default
# Rubycli will ask you to call out the constant explicitly:
#   rubycli examples/mismatched_constant_runner.rb FriendlyGreeter greet --message "Hello"
# To auto-select it, pass --auto-constant.
class FriendlyGreeter
  # NAME [String] Text to display
  # --message MESSAGE [String] Greeting to print (defaults to "Hello")
  def self.greet(name = 'friend', message: 'Hello', quiet: false)
    output = "#{message}, #{name}!"
    puts(output) unless quiet
    output
  end
end
