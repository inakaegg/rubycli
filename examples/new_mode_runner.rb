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

  # mode [Symbol] 実行モード
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
#   # コンストラクタ options を JSON で渡す（厳格にパースされる）
#   rubycli --json-args --new='["a","b"]' examples/new_mode_runner.rb run --mode summary --options '{"source":"json","limit":5}'
#
#   # eval モードで Ruby ハッシュを渡す（シンボルキーなど柔軟に扱える）
#   rubycli --eval-args --new='["x","y"]' examples/new_mode_runner.rb run --mode summary --options '{retry: 2, tags: [:a, :b]}'
#
#   # pre-script で初期化する例（ファイル名は任意）
#   rubycli --pre-script 'NewModeRunner.new(%w[a b c], options: {from: :pre})' examples/new_mode_runner.rb run --mode summary
