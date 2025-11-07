# Rubycli — Python Fire 風の Ruby 向け CLI

![Rubycli ロゴ](assets/rubycli-logo.png)

Rubycli は Ruby のクラス／モジュールにある公開メソッドの定義と、そのメソッドに付けたドキュメントコメントから CLI を自動生成する小さなフレームワークです。Python Fire にインスパイアされていますが、互換や公式ポートを目指すものではありません。Ruby のコメント記法と型アノテーションに合わせて設計しており、コメントに書いた型ヒントや繰り返し指定が CLI の引数解釈もコントロールします。

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
    greet                <NAME>

Detailed command help: hello_app.rb COMMAND help
Enable debug logging: --debug or RUBYCLI_DEBUG=true
```

```bash
rubycli examples/hello_app.rb greet
```

```text
Error: wrong number of arguments (given 0, expected 1)
Usage: hello_app.rb greet NAME

Positional arguments:
  NAME    required
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
    greet                <NAME> [--shout]

Detailed command help: hello_app_with_docs.rb COMMAND help
Enable debug logging: --debug or RUBYCLI_DEBUG=true
```

```bash
rubycli examples/hello_app_with_docs.rb greet --help
```

```text
Usage: hello_app_with_docs.rb greet NAME [--shout]

Positional arguments:
  NAME  [String]  required  挨拶対象

Options:
  --shout  [Boolean]  optional  大文字で出力 (default: false)
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

## 定数解決モード

Rubycli は「ファイル名を CamelCase にした定数」を公開対象だと想定しています。ファイル名とクラス／モジュール名が一致しない場合は、次のモードで挙動を切り替えられます。

| モード | 有効化方法 | 挙動 |
| --- | --- | --- |
| `strict`（デフォルト） | 何もしない / `--strict-target` / `RUBYCLI_AUTO_TARGET=strict` | CamelCase が一致しないとエラーになります。検出した定数一覧と再実行コマンド例を表示します。 |
| `auto` | `--auto-target`（互換の `--auto-constant`）または `RUBYCLI_AUTO_TARGET=auto` | ファイル内で CLI として実行できる定数が 1 つだけなら自動選択します。複数あれば従来通りエラーで案内します。 |

大規模なコードベースでも安全側を保ちながら、どうしても自動選択したいときだけ 1 フラグで切り替えられます。

> **インスタンスメソッド専用のクラスについて** – 公開メソッドがインスタンス側（`attr_reader` や `def greet`）にしか無い場合は、`--new` を付けて事前にインスタンス化しないと CLI から呼び出せません。クラスメソッドを 1 つ用意するか、`--new` を明示して実行してください。

## 開発方針

- **便利さが最優先** – 既存の Ruby スクリプトを最小の手間で CLI 化できることを目的にしており、Python Fire の完全移植は目指していません。
- **インスパイアであってポートではない** – アイデアの出自は Fire ですが、同等機能を揃える予定は基本的にありません。Fire 由来の未実装機能は仕様です。
- **メソッド定義が土台、コメントが挙動を補強** – 公開メソッドのシグネチャが CLI に露出する範囲と必須／任意を決めますが、コメントに `TAG...` や `[Integer]` を書くと同じ引数でも配列化や型変換が行われます。コメントと実装のズレを観測したいときだけ `RUBYCLI_STRICT=ON` で厳格モードを有効化し、警告を受け取ります。
- **軽量メンテナンス** – 実装の多くは AI 支援で作られており、深い Ruby メタプログラミングを伴う大規模拡張は想定外です。Fire 互換を求める PR は事前相談をお願いします。

## 特徴

- コメントベースで CLI オプションやヘルプを自動生成
- YARD 形式と `NAME [Type] 説明…` の簡潔記法を同時サポート
- 引数はデフォルトで安全なリテラルとして解釈し、必要に応じて厳格 JSON モードや Ruby eval モードを切り替え可能
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
| クラス初期化 | `__init__` 引数を CLI で自動受け取りインスタンス化 | `--new` 指定時だけ引数なしで明示的に初期化（初期化引数の CLI 受け渡しは未対応なので、必要なら pre-script や自前ファクトリで注入） |
| インタラクティブシェル | コマンド未指定時に Fire REPL を提供 | インタラクティブモード無し。コマンド実行専用 |
| 情報源 | 反射で引数・プロパティを解析 | ライブなメソッド定義を基点にしつつコメントをヘルプへ反映 |
| 辞書/配列 | dict/list を自動でサブコマンド化 | クラス/モジュールのメソッドに特化（辞書自動展開なし） |

## インストール

Rubycli は RubyGems からインストールできます。

```bash
gem install rubycli
```

Bundler 例:

```ruby
# Gemfile
gem "rubycli"
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

| 用途 | YARD 互換 | Rubycli 標準 |
| ---- | --------- | ----------- |
| 位置引数 | `@param name [Type] 説明` | `NAME [Type] 説明` |
| キーワード引数 | 同上 | `--flag -f VALUE [Type] 説明` |
| 戻り値 | `@return [Type] 説明` | `=> [Type] 説明` |

短いオプション（`-f` など）は任意で、登場順も自由です。Rubycli 標準の書き方では次の例が同義になります。

- `--flag -f VALUE [Type] 説明`
- `--flag VALUE [Type] 説明`
- `-f --flag VALUE [Type] 説明`

README のサンプルは既定スタイルとして大文字プレースホルダ（`NAME`, `VALUE` など）を使用しています。次項以降の表記揺れは、必要に応じて選べる追加記法です。

### 互換プレースホルダ表記

コメントやヘルプ出力では次の表記も同じ意味として解釈されます。

- 山括弧で値を明示: `--flag <value>`, `NAME [<value>]`
- ロングオプションの `=` 付き表記: `--flag=<value>`
- 繰り返し指定: `VALUE...`, `<value>...`

実行時には `--flag VALUE`, `--flag <value>`, `--flag=<value>` のどれで入力しても同じ扱いです。プロジェクトで読みやすいスタイルを選択してください。`[VALUE]` や `[VALUE...]` のような表記を使うと、真偽値・任意値・リストなどの推論が働きます。値プレースホルダを省略したオプション（例: `--quiet`）は自動で Boolean フラグとして扱われます。

> 補足: コメント内で任意引数を角括弧で表す必要はありません。Ruby 側のメソッドシグネチャから必須／任意は自動判定され、ヘルプ出力では Rubycli が適切に角括弧を追加します。

型ヒントは `[String]`, `(String)`, `(type: String)` のように角括弧・丸括弧・`type:` プレフィックスのいずれでも指定できます。複数型は `(String, nil)` や `(type: String, nil)` のように列挙してください。

`VALUE...` のような繰り返し指定（`TAG...` など）や、`[String[]]` / `Array<String>` といった配列型の注釈が付いたオプションは配列として扱われます。JSON/YAML 形式のリスト（例: `--tags '["build","test"]'`）を渡すか、カンマ区切り文字列（`--tags "build,test"`）を渡すことで配列に変換されます。スペース区切りの複数値入力（`--tags build test`）にはまだ対応しておらず、繰り返し注記のないオプションは従来どおりスカラーとして扱われます。

代表的な推論例:

- `ARG1` のように型ラベルを省略したプレースホルダは既定で `String` として扱われます。
- `--name ARG1` のようにオプションへプレースホルダだけを指定しても同じく `String` が推論されます。
- `--verbose` のように値プレースホルダを省略したオプションは Boolean フラグとして扱われます。

`@example` や `@raise`, `@see`, `@deprecated` などその他の YARD タグは、現状ヘルプ出力には反映されません。

> すべての記法をまとめて試したい場合は `rubycli examples/documentation_style_showcase.rb canonical --help` や `... angled --help` などを実行してみてください。

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
    scale                AMOUNT [<FACTOR>] [--clamp=<value>] [--notify]

Detailed command help: fallback_example.rb COMMAND help
Enable debug logging: --debug or RUBYCLI_DEBUG=true
```

```bash
rubycli examples/fallback_example.rb scale --help
```

```text
Usage: fallback_example.rb scale AMOUNT [FACTOR] [--clamp=<CLAMP>] [--notify]

Positional arguments:
  AMOUNT  [Integer]  required  処理対象の数値
  FACTOR             optional  (default: 2)

Options:
  --clamp=<CLAMP>  [String]   optional  (default: nil)
  --notify         [Boolean]  optional  (default: false)
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

## 引数解析モード

### 既定のリテラル解析

Rubycli は `{` や `[`、クォート、YAML の先頭記号といった「構造化リテラルらしい」形の引数に対して `Psych.safe_load` を試み、成功すれば Ruby の配列／ハッシュ／真偽値に変換してからメソッドへ渡します。たとえば `--names='["Alice","Bob"]'` や `--config='{foo: 1}'` のような値は追加フラグ無しでネイティブな配列・ハッシュとして届きます。一方、プレーンな `1,2,3` のような文字列はこの段階ではそのまま維持されます（コメントで `String[]` や `TAG...` と宣言されている場合は後段で配列に整形されます）。扱えない形式は自動的に文字列へフォールバックするため、`"2024-01-01"` のような値もそのまま文字列で受け取れますし、構文が崩れていても CLI 全体が落ちることはありません。

### JSON モード

CLI 実行時に `--json-args`（短縮形 `-j`）を付けると、後続の引数が厳格に JSON として解釈されます。

```bash
rubycli -j my_cli.rb MyCLI run '["--config", "{\"foo\":1}"]'
```

YAML 固有の書き方は拒否され、無効な JSON であれば `JSON::ParserError` が発生するため、入力の妥当性を強く保証したいときに便利です。プログラム側では `Rubycli.with_json_mode(true) { … }` で有効化できます。

### Eval モード

`--eval-args`（短縮形 `-e`）を使うと、後続の引数を Ruby コードとして評価した結果を CLI に渡せます。JSON や YAML では表現しづらいオブジェクトを扱いたいときに便利ですが、評価は `Object.new.instance_eval { binding }` 上で行われるため、信頼できる入力に限定してください。コード内では `Rubycli.with_eval_mode(true) { … }` で切り替えられます。

`--eval-args`/`-e` と `--json-args`/`-j` は同時指定できません。どちらのモードも既定のリテラル解析を拡張する位置づけなので、用途に応じて厳格な JSON か Ruby eval のどちらかを選択してください。

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
