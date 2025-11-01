# Rubycli — Python Fire 風の Ruby 向け CLI

Rubycli は Ruby のクラス／モジュールに書いたコメントから CLI を自動生成する小さなフレームワークです。Python Fire にインスパイアされていますが、互換や公式ポートを目指すものではありません。Ruby のコメント記法と型アノテーションに合わせて設計しています。

> English guide is available in [README.md](README.md).

### 1. Rubycli を意識しない既存スクリプト

```ruby
# hello_app.rb
module HelloApp
  module_function

  def greet(name)
    puts "Hello, #{name}!"
  end
end
```

> リポジトリには `examples/hello_app.rb` を同梱しているので、プロジェクト直下で `rubycli examples/hello_app.rb` を実行すると公開コマンドをすぐに確認できます。

```bash
rubycli examples/hello_app.rb
```

```text
Usage: hello_app.rb COMMAND [arguments]

Available commands:
  Class methods:
    greet                <name>

Detailed command help: hello_app.rb COMMAND help
Enable debug logging: --debug or RUBYCLI_DEBUG=true
```

```bash
rubycli examples/hello_app.rb greet
```

```text
Error: wrong number of arguments (given 0, expected 1)
Usage: hello_app.rb greet <NAME>

Positional arguments:
  NAME
```

```bash
rubycli examples/hello_app.rb greet Hanako
#=> Hello, Hanako!
```

`rubycli examples/hello_app.rb --help` を実行しても同じヘルプが表示されます。

### 2. コメントのヒントを足してオプションを有効化

> まだ `require "rubycli"` は不要です。コメントでオプション解析とヘルプを制御します。

**簡潔なプレースホルダ記法**

```ruby
# hello_app.rb
module HelloApp
  module_function

  # NAME [String] 挨拶対象
  # --shout [Boolean] 大文字で出力
  def greet(name, shout: false)
    message = "Hello, #{name}!"
    message = message.upcase if shout
    puts message
  end
end
```

**YARD タグでも同様に動作**

```ruby
# hello_app.rb
module HelloApp
  module_function

  # @param name [String] 挨拶対象
  # @param shout [Boolean] 大文字で出力
  def greet(name, shout: false)
    message = "Hello, #{name}!"
    message = message.upcase if shout
    puts message
  end
end
```

> README に合わせたドキュメント付きの版は `examples/hello_app_with_docs.rb` として同梱しています。

```bash
rubycli examples/hello_app_with_docs.rb
```

```text
Usage: hello_app_with_docs.rb COMMAND [arguments]

Available commands:
  Class methods:
    greet                <name> [--shout=<value>]

Detailed command help: hello_app_with_docs.rb COMMAND help
Enable debug logging: --debug or RUBYCLI_DEBUG=true
```

```bash
rubycli examples/hello_app_with_docs.rb greet --help
```

```text
Usage: hello_app_with_docs.rb greet <NAME> [--shout]

Positional arguments:
  NAME  [String] 挨拶対象

Options:
  --shout  [Boolean] 大文字で出力 (default: false)
```

```bash
rubycli examples/hello_app_with_docs.rb greet --shout Hanako
#=> HELLO, HANAKO!
```

CLI に公開したくないヘルパーは、特異クラス側で `private` として定義してください:

```ruby
module HelloApp
  class << self
    private

    def internal_ping(url)
      # CLI コマンドとしては露出しない
    end
  end
end
```

### 3. （任意）スクリプト内にランナーを組み込む

`ruby hello_app.rb ...` の形で呼び出したい場合だけ `require "rubycli"` を追加し、`Rubycli.run` に制御を渡します（後述のクイックスタート参照）。

## 開発方針

- **便利さが最優先** – 既存の Ruby スクリプトを最小の手間で CLI 化できることを目的にしており、Python Fire の完全移植は目指していません。
- **インスパイアであってポートではない** – アイデアの出自は Fire ですが、同等機能を揃える予定は基本的にありません。Fire 由来の未実装機能は仕様です。
- **コードが一次情報、コメントは補助** – メソッド定義こそが真実であり、コメントはヘルプを豊かにする付加情報です。コメントと実装のズレを観測したいときだけ `RUBYCLI_STRICT=ON` で厳格モードを有効化し、警告を受け取ります。
- **軽量メンテナンス** – 実装の多くは AI 支援で作られており、深い Ruby メタプログラミングを伴う大規模拡張は想定外です。Fire 互換を求める PR は事前相談をお願いします。

## 特徴

- コメントベースで CLI オプションやヘルプを自動生成
- YARD 形式と `NAME [Type] 説明…` の簡潔記法を同時サポート
- `--json-args` で渡された引数を自動的に JSON パース
- `--pre-script`（エイリアス: `--init`）で任意の Ruby コードを評価し、その結果オブジェクトを公開
- `RUBYCLI_STRICT=ON` で有効化できる厳格モードにより、コメントとシグネチャの矛盾を警告として検知可能

## Python Fire との違い

- **コメント対応のヘルプ生成**: コメントがあればヘルプに反映しつつ、最終的な判断は常にライブなメソッド定義に基づきます。
- **型に基づく解析**: `NAME [String]` や YARD タグから型を推論し、真偽値・配列・数値などを自動変換します。
- **厳密な整合性チェック**: 厳格モードを有効にすれば、コメントとメソッド定義が食い違う際に警告を出して保守性を高められます。
- **Ruby 向け拡張**: キーワード引数やブロック (`@yield*`) といった Ruby 固有の構文に合わせたパーサや `RUBYCLI_*` 環境変数を用意しています。

| 機能 | Python Fire | Rubycli |
| ---- | ----------- | -------- |
| 属性の辿り方 | オブジェクトを辿ってプロパティ/属性を自動公開 | 対象オブジェクトの公開メソッドをそのまま公開（暗黙の辿りは無し） |
| クラス初期化 | `__init__` 引数を CLI で自動受け取りインスタンス化 | `--new` を指定した明示的な初期化のみ。引数はコメントで宣言 |
| インタラクティブシェル | コマンド未指定時に Fire REPL を提供 | インタラクティブモード無し。コマンド実行専用 |
| 情報源 | 反射で引数・プロパティを解析 | ライブなメソッド定義を基点にしつつコメントをヘルプへ反映 |
| 辞書/配列 | dict/list を自動でサブコマンド化 | クラス/モジュールのメソッドに特化（辞書自動展開なし） |

## インストール

まだ RubyGems で公開していません。リポジトリをクローンしてローカルパスを Bundler に指定するか、`.gemspec` 追加後に `gem build` で `.gem` を作成してインストールしてください。

```bash
git clone https://github.com/inakaegg/rubycli.git
cd rubycli
# gem build rubycli.gemspec
gem build rubycli.gemspec
gem install rubycli-<version>.gem
```

Bundler 例:

```ruby
# Gemfile
gem "rubycli", path: "path/to/rubycli"
```

## クイックスタート（Rubycli をスクリプトに組み込む）

ステップ3では `require "rubycli"` を追加し、スクリプト自身から CLI を起動できるようにします。

```ruby
# hello_app.rb
require "rubycli"

module HelloApp
  module_function

  # NAME [String] 挨拶対象
  # --shout [Boolean] 大文字で出力
  # => [String] 出力したメッセージ
  def greet(name, shout: false)
    message = "Hello, #{name}!"
    message = message.upcase if shout
    puts message
    message
  end
end

Rubycli.run(HelloApp)
```

実行例:

```bash
ruby hello_app.rb greet Taro
#=> Hello, Taro!

ruby hello_app.rb greet Taro --shout
#=> HELLO, TARO!
```

`require "rubycli"` を書かなくても、付属コマンドから同じファイルを実行できます:

```bash
rubycli path/to/hello_app.rb greet --shout Hanako
```

クラス／モジュール名を省略した場合でも、ファイル名に対応する定義を自動で推測し、ネストした `Module1::Inner::Runner` のようなクラスも見つけ出します。CLI から実行するとメソッドの戻り値は常に標準出力へ表示されます。

別の定数を明示的に指定したい場合は、ファイルパスの後ろに続けてください:

```bash
rubycli scripts/multi_runner.rb Admin::Runner list --active
```

1つのファイルに複数の候補がある場合や、ファイル名と異なるネストした定義を選びたいときに便利です。

## コメント記法

| 用途 | YARD 互換 | 簡潔記法 |
| ---- | --------- | -------- |
| 位置引数 | `@param name [Type] 説明` | `NAME [Type] 説明`（NAME は大文字） |
| キーワード引数 | 同上 | `--flag -f FLAG [Type] 説明` |
| 戻り値 | `@return [Type] 説明` | `=> [Type] 説明` |

型は `String` や `Integer` のほか、`String[]` や `Array<String>`, `String | nil` なども利用できます。`[VALUE]` や `[VALUE...]` といったプレースホルダ表現で、真偽値や可変長引数を推論させられます。型名を省略した大文字プレースホルダ（例: `--quiet`）は自動的に Boolean フラグとして扱われます。

代表的な推論例:

- `ARG1` のように型ラベルを省略した大文字プレースホルダは既定で `String` として扱われます。
- `--name ARG1` のようにオプションへ大文字プレースホルダだけを指定しても同じく `String` が推論されます。
- `--verbose` のように値プレースホルダを省略したオプションは Boolean フラグとして扱われます。

`@example` や `@raise`, `@see`, `@deprecated` などその他の YARD タグは、現状ヘルプ出力には反映されません。

従来の `@param` 記法も既定で利用できます。簡潔なプレースホルダ記法だけに限定したい場合は `RUBYCLI_ALLOW_PARAM_COMMENT=OFF` を設定してください（厳格モードでの検証は継続されます）。

### コメントが不足している場合のフォールバック

Rubycli は常に実装中のメソッドシグネチャを信頼します。コメントに書いていない引数やオプションがあっても、定義そのものから名前や初期値を推論して CLI に表示します。

```ruby
# fallback_example.rb
module FallbackExample
  module_function

  # AMOUNT [Integer] 処理対象の数値
  def scale(amount, factor = 2, clamp: nil, notify: false)
    result = amount * factor
    result = [result, clamp].min if clamp
    puts "Scaled to #{result}" if notify
    result
  end
end
```

```bash
rubycli examples/fallback_example.rb
```

```text
Usage: fallback_example.rb COMMAND [arguments]

Available commands:
  Class methods:
    scale                <amount> [<factor>] [--clamp=<value>] [--notify=<value>]

Detailed command help: fallback_example.rb COMMAND help
Enable debug logging: --debug or RUBYCLI_DEBUG=true
```

```bash
rubycli examples/fallback_example.rb scale --help
```

```text
Usage: fallback_example.rb scale <AMOUNT> [<FACTOR>] [--clamp=<value>] [--notify]

Positional arguments:
  AMOUNT    [Integer] 処理対象の数値
  [FACTOR]  (default: 2)

Options:
  --clamp CLAMP  (type: String) (default: nil)
  --notify       (type: Boolean) (default: false)
```

`AMOUNT` だけがドキュメント化されていますが、`factor` や `clamp`, `notify` も自動的に補完され、既定値や型が推論されていることがわかります。コメントとシグネチャの矛盾を早期に検知したい場合は `RUBYCLI_STRICT=ON` で厳格モードを有効化してください。

#### 存在しない引数やオプションをコメントに書いた場合

- **整合しないコメントは詳細テキストへフォールバック** – 実装に存在しないオプション（例: `--ghost`）や位置引数（例: `EXTRA`）を記述すると、その行はヘルプ末尾の詳細セクションに素のテキストとして表示され、実際の引数としては機能しません。厳格モードなら `Extra positional argument comments were found: EXTRA` のような警告が出て、位置引数のズレにも気付きやすくなります。

> 実際に確認したい場合は `rubycli examples/fallback_example_with_extra_docs.rb scale --help` を試してみてください。

コメントだけでは実装を拡張できません。メソッドシグネチャとコメントを一致させておくことで、ヘルプと挙動の整合性を保てます。

### YARD 互換コメントを併用する際の注意点

- `**kwargs` を受け取るメソッドでも、Rubycli は個別のキーワードコメント（`--config-path ...` など）が無い限りヘルプへ露出させません。CLI で使わせたいキーはすべて `--LONG-NAME PLACEHOLDER [Type] 説明` の行として明示してください。
- `@param` で位置引数を記述した場合も解析できますが、位置引数・キーワード引数を同じ行形式で列挙する必要があります。`@param source Path` のように書いても、キーワード向けのロングオプションが自動生成されるわけではありません。
- `@param` の行に続く箇条書きや補足行は CLI の自動生成には使われません。補足情報を表示したい場合は、`--flag ...` 行の説明に含めるか、README など別のドキュメントで扱ってください。
- `RUBYCLI_ALLOW_PARAM_COMMENT=OFF` にすると `@param`/`@return` などのタグは警告扱いになります。プロジェクト内で簡潔記法へ統一するときはこの環境変数で段階的に移行できます。

## JSON モード

CLI 実行時に `--json-args` を付けると、後続の引数が JSON として解釈され Ruby オブジェクトに変換されます。

```bash
rubycli --json-args my_cli.rb MyCLI run '["--config", "{\"foo\":1}"]'
```

プログラム側では `Rubycli.with_json_mode(true) { … }` で同じ効果を得られます。

## Eval モード

`--eval-args` を使うと、後続の引数を Ruby コードとして評価した結果を CLI に渡せます。JSON では表現しづらいオブジェクトを扱いたいときに便利です。

```bash
rubycli --eval-args scripts/data_cli.rb DataCLI run '(1..10).to_a'
```

評価は `Object.new.instance_eval { binding }` に対して行われるため、信頼できる環境でのみ利用してください。プログラム側からは `Rubycli.with_eval_mode(true) { … }` で有効化できます。

`--eval-args` と `--json-args` は同時指定できません。両方付けた場合はエラーになります。

## Pre-script ブートストラップ

付属 CLI を起動するときに `--pre-script SRC`（別名: `--init`）を指定すると、公開メソッドを呼び出す前に任意の Ruby コードを評価できます。評価は隔離された binding 内で行われ、以下のローカル変数があらかじめ用意されています。

- `target` – `--new` を適用する前のクラス／モジュール
- `current` / `instance` – 現在公開予定のオブジェクト（`--new` を指定した場合は生成済みインスタンス）

スクリプトの最後に評価された値が新しい公開対象になります。`nil` を返した場合は直前のオブジェクトを維持します。

インラインで書く例:

```bash
rubycli --pre-script 'InitArgRunner.new(source: "cli", retries: 2)' \
  lib/init_arg_runner.rb summarize --verbose
```

ファイルに切り出す例:

```ruby
# scripts/bootstrap_runner.rb
instance = InitArgRunner.new(source: "preset")
instance.logger = Logger.new($stdout)
instance
```

```bash
rubycli --pre-script scripts/bootstrap_runner.rb \
  lib/init_arg_runner.rb summarize --verbose
```

この仕組みを使えば、`--new` のシンプルさを保ったまま、DI 風の初期化やラッパーオブジェクトの準備といった高度な前処理を CLI で行えます。

## 環境変数とフラグ

| 変数 / フラグ | 説明 | 既定値 |
| ------------- | ---- | ------ |
| `--debug` / `RUBYCLI_DEBUG=true` | デバッグログ表示 | `false` |
| `RUBYCLI_STRICT=ON` | 厳格モードを有効化（コメントとシグネチャの矛盾を警告） | `OFF` |
| `RUBYCLI_ALLOW_PARAM_COMMENT=OFF` | レガシーな `@param` 記法を無効化（互換性のため既定では ON） | `ON` |

## Rubycli API

- `Rubycli.parse_arguments(argv, method)` – コメント情報を考慮した引数解析
- `Rubycli.available_commands(target)` – 公開 CLI コマンド一覧
- `Rubycli.usage_for_method(name, method)` – 指定メソッドのヘルプ生成
- `Rubycli.method_description(method)` – 構造化されたドキュメント取得

ご意見・フィードバックは Issue や Pull Request でお寄せください。
