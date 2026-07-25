# frozen_string_literal: true

# Demonstrates instance-only CLI with constructor arguments and eval/json modes.
class NewModeRunner
  attr_reader :items, :options

  # ITEMS [String[]]  リスト入力（カンマ区切りや JSON 配列を許容）
  # --options [Hash]  追加設定（JSON / eval で指定）
  def initialize(items, options: {})
    @items = items
    @options = options
  end

  # --mode MODE [Symbol] 実行モード（summary または reverse）
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

# Usage examples (from project root):
#   # インスタンスメソッドのみなので --new が必須。配列はカンマ区切りでも JSON でも OK
#   rubycli --new='["a","b","c"]' examples/new_mode_runner.rb run --mode reverse
#   rubycli --new a,b,c examples/new_mode_runner.rb run --mode summary
#
#   # JSON モード: 以降の引数は厳格に JSON として解釈される（裸の単語は不可）
#   rubycli --json-args --new='["a","b"]' examples/new_mode_runner.rb run
#
#   # eval モード: Ruby リテラルを渡せる（すべての引数が有効な Ruby である必要がある）
#   rubycli --eval-args --new='%w[x y]' examples/new_mode_runner.rb run --mode ':reverse'
#
#   # --new が渡せる値は 1 つ（= items）だけなので、options: は pre-script で渡す
#   rubycli --new='["a"]' --pre-script 'NewModeRunner.new(%w[a b c], options: {from: :pre})' examples/new_mode_runner.rb run --mode summary
