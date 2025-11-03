# frozen_string_literal: true
require "rubycli"

module HelloApp
  module_function

  # NAME [String] Name to greet
  # --shout [Boolean] Print in uppercase
  # => [String] Printed message
  def greet(name, shout: false)
    message = "Hello, #{name}!"
    message = message.upcase if shout
    puts message
    message
  end
end

Rubycli.run(HelloApp)
