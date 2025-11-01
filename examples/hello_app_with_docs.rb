# frozen_string_literal: true

# Example CLI target with documentation-driven options; see README section 2.
module HelloApp
  module_function

  # NAME [String] Name to greet
  # --shout [Boolean] Print in uppercase
  def greet(name, shout: false)
    message = "Hello, #{name}!"
    message = message.upcase if shout
    puts message
  end
end

# Provide a constant that matches the file name so Rubycli infers it automatically.
HelloAppWithDocs = HelloApp
