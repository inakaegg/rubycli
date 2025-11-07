# frozen_string_literal: true

# Demonstrates how Rubycli behaves when a file defines multiple constants.
# By default Rubycli will prefer the constant whose name matches the file
# (MultiConstantRunner). To invoke HelperRunner instead, specify it explicitly:
#   rubycli examples/multi_constant_runner.rb HelperRunner inspect
class HelperRunner
  def self.inspect
    puts("Helper invoked")
    :helper
  end
end

class MultiConstantRunner
  # TEXT [String] Message to display
  def self.echo(text = "hello")
    puts(text)
    text
  end
end
