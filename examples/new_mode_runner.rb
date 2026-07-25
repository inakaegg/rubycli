# frozen_string_literal: true

# Demonstrates instance-only CLI with constructor arguments and eval/json modes.
class NewModeRunner
  attr_reader :items, :options

  # ITEMS [String[]]  List input (comma-separated or a JSON array)
  # --options [Hash]  Extra settings (JSON or eval literals)
  def initialize(items, options: {})
    @items = items
    @options = options
  end

  # --mode MODE [Symbol] Execution mode (summary or reverse)
  def run(mode: :summary)
    case mode.to_sym
    when :summary
      {
        count: items.size,
        uppercased: items.map(&:upcase),
        options: options
      }
    when :reverse
      items.reverse
    else
      warn "unknown mode: #{mode}"
      nil
    end
  end
end

# Usage examples (from the repository root):
#   # Instance methods only, so --new is required; the array can be JSON or comma-separated
#   rubycli --new='["a","b","c"]' examples/new_mode_runner.rb run --mode reverse
#   rubycli --new a,b,c examples/new_mode_runner.rb run --mode summary
#
#   # JSON mode: every following argument is parsed strictly as JSON (bare words are rejected)
#   rubycli --json-args --new='["a","b"]' examples/new_mode_runner.rb run
#
#   # Eval mode: Ruby literals are accepted, but every argument must be valid Ruby
#   rubycli --eval-args --new='%w[x y]' examples/new_mode_runner.rb run --mode ':reverse'
#
#   # --new passes a single value (items), so keyword arguments go through a pre-script
#   rubycli --new='["a"]' \
#     --pre-script 'NewModeRunner.new(%w[a b c], options: {from: :pre})' \
#     examples/new_mode_runner.rb run --mode summary
