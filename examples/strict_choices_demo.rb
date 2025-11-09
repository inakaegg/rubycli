# frozen_string_literal: true

# Demonstrates literal enum choices and strict validation.
module StrictChoicesDemo
  module_function

  # LEVEL %i[info warn error] Report severity
  # --format TARGET ["text", "json", "yaml"] Output destination (strings)
  # --notify [Boolean] Print a notification banner
  def report(level, format: 'text', notify: false)
    payload = { level: level, format: format, notify: notify }
    message = "[#{level.to_s.upcase}] format=#{format}"
    message = "#{message} (notify enabled)" if notify
    puts message
    payload
  end
end

if $PROGRAM_NAME == __FILE__
  require 'rubycli'
  Rubycli.run(StrictChoicesDemo)
end
