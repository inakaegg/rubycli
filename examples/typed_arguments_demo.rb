# frozen_string_literal: true

require 'date'
require 'time'
require 'bigdecimal'
require 'pathname'

# Demonstrates standard library type coercions.
module TypedArgumentsDemo
  module_function

  # --date DATE [Date] Planned schedule date
  # --moment TIME [Time] Execution timestamp
  # --budget AMOUNT [BigDecimal] Budget amount
  # --input FILE [Pathname] Path to source file
  def ingest(
    date: Date.today,
    moment: Time.now,
    budget: BigDecimal('0'),
    input: Pathname.new('.')
  )
    summary = <<~TEXT
      Date: #{date.iso8601}
      Moment: #{moment.utc.iso8601}
      Budget: #{budget.to_s('F')}
      Input: #{input.expand_path}
    TEXT

    puts summary
    {
      date: date,
      moment: moment,
      budget: budget,
      input: input
    }
  end
end

if $PROGRAM_NAME == __FILE__
  require 'rubycli'
  Rubycli.run(TypedArgumentsDemo)
end
