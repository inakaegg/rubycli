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
| `strict`（デフォルト） | 何もしない / `RUBYCLI_AUTO_TARGET=strict` | CamelCase が一致しないとエラーになります。検出した定数一覧と再実行コマンド例を表示します。 |
| `auto` | `--auto-target`（短縮 `-a`） または `RUBYCLI_AUTO_TARGET=auto` | ファイル内で CLI として実行できる定数が 1 つだけなら自動選択します。複数あれば従来通りエラーで案内します。 |

大規模なコードベースでも安全側を保ちながら、どうしても自動選択したいときだけ 1 フラグで切り替えられます。

> **インスタンスメソッド専用のクラスについて** – 公開メソッドがインスタンス側（`def greet` など）にしか無い場合は、`--new` を付けて事前にインスタンス化しないと CLI から呼び出せません。クラスメソッドを 1 つ用意するか、`--new` を明示して実行してください。`--new` を付ければ `rubycli --help` でもインスタンスメソッドが一覧に現れ、`rubycli --check --new` でコメントの lint も実行できます。初期化時に引数が必要なら `--new=VALUE` のように続けて指定できます（通常の引数と同様に YAML/JSON ライクな安全パースに加え、`--json-args` / `--eval-args` / `--eval-lax` も適用可能）。`initialize` に書いたコメントも通常の CLI メソッドと同様に型変換に反映されます。

> 補足: `--new 1` のようにスペース区切りで 1 つだけ値を渡すと、後続トークンがパス扱いされやすいため `--new=VALUE` のように `=` 付きで指定するのが確実です。

## 開発方針

- **便利さが最優先** – 既存の Ruby スクリプトを最小の手間で CLI 化できることを目的にしており、Python Fire の完全移植は目指していません。
- **インスパイアであってポートではない** – アイデアの出自は Fire ですが、同等機能を揃える予定は基本的にありません。Fire 由来の未実装機能は仕様です。
- **メソッド定義が土台、コメントが挙動を補強** – 公開メソッドのシグネチャが CLI に露出する範囲と必須／任意を決めますが、コメントに `TAG...` や `[Integer]` を書くと同じ引数でも配列化や型変換が行われます。さらに Rubycli は `--names='["Alice","Bob"]'` のような JSON/YAML らしい入力を自動的に安全なリテラルとして評価します。`rubycli --check パス/対象.rb` でコメントと実装のズレ（未定義の型ラベルや列挙値の誤記を含む）を DidYouMean の候補付きで検査し、通常実行時に `--strict` を付ければドキュメント通りでない入力をその場でエラーにできます。
- **軽量メンテナンス** – 実装の多くは AI 支援で作られており、深い Ruby メタプログラミングを伴う大規模拡張は想定外です。Fire 互換を求める PR は事前相談をお願いします。

## 特徴

- コメントベースで CLI オプションやヘルプを自動生成
- YARD 形式と `NAME [Type] 説明…` の簡潔記法を同時サポート
- 引数はデフォルトで安全なリテラルとして解釈し、必要に応じて厳格 JSON モードや Ruby eval モードを切り替え可能
- `--pre-script`（エイリアス: `--init`）で任意の Ruby コードを評価し、その結果オブジェクトを公開
- `--check` でコメント整合性を lint、`--strict` で入力値をドキュメント通りに強制する二段構えのガード
- `examples/new_mode_runner.rb` ではインスタンス専用クラスを `--new=VALUE` で初期化し、eval/JSON モードや pre-script を組み合わせる例を示しています。

### サンプル / 付属例

- `examples/hello_app.rb` / `examples/hello_app_with_docs.rb`: 最小のモジュール関数とドキュメント付きの版
- `examples/typed_arguments_demo.rb`: 標準ライブラリ型 (Date/Time/BigDecimal/Pathname) の coercion
- `examples/strict_choices_demo.rb`: リテラル列挙と `--strict` の組み合わせ
- `examples/new_mode_runner.rb`: インスタンス専用クラスを `--new=VALUE` で初期化し、eval/JSON/pre-script を組み合わせる例

#### サンプルコマンド

- `rubycli examples/new_mode_runner.rb run --new='["a","b","c"]' --mode reverse`
- `rubycli --json-args --new='["x","y"]' examples/new_mode_runner.rb run --mode summary --options '{"source":"json"}'`
- `rubycli --eval-args --new='["x","y"]' examples/new_mode_runner.rb run --mode summary --options '{tags: [:a, :b]}'`
- `rubycli --pre-script 'NewModeRunner.new(%w[a b c], options: {from: :pre})' examples/new_mode_runner.rb run --mode summary`

> 補足: `--strict` はコメントに書かれた型／許可値をそのまま信頼して検証するため、コメントが誤記だと実行時には検出できません。CI では必ず `rubycli --check` を走らせ、`--strict` は「 lint を通過したドキュメントを本番で厳密に守る」用途に使ってください。

## Python Fire との違い

- **コメント対応のヘルプ生成**: コメントがあればヘルプに反映しつつ、最終的な判断は常にライブなメソッド定義に基づきます。
- **型に基づく解析**: `NAME [String]` や YARD タグから型を推論し、真偽値・配列・数値などを自動変換します。
- **厳密な整合性チェック**: `rubycli --check` でコメントと実装のズレ（未定義の型ラベルや列挙値の誤記など）をコード実行前に検査し、通常実行時に `--strict` を付ければドキュメントで宣言した型・許可値以外の入力を拒否できます。
- **Ruby 向け拡張**: キーワード引数やブロック (`@yield*`) といった Ruby 固有の構文に合わせたパーサや `RUBYCLI_*` 環境変数を用意しています。

| 機能 | Python Fire | Rubycli |
| ---- | ----------- | -------- |
| 属性の辿り方 | オブジェクトを辿ってプロパティ/属性を自動公開 | 対象オブジェクトの公開メソッドをそのまま公開（暗黙の辿りは無し） |
| クラス初期化 | `__init__` 引数を CLI で自動受け取りインスタンス化 | `--new` 指定時だけ初期化（コンストラクタ引数は `--new=VALUE` で渡せる。YAML/JSON らしいリテラルは安全にパース、`--json-args` / `--eval-args` / `--eval-lax` も適用可能。より複雑なら pre-script や自前ファクトリを利用） |
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

型ヒントは `[String]` や `(String)` のように角括弧／丸括弧で指定できます。複数型は `(String, nil)` のように列挙してください。

`VALUE...` のような繰り返し指定（`TAG...` など）や、`[String[]]` / `Array<String>` といった配列型の注釈が付いたオプションは配列として扱われます。JSON/YAML 形式のリスト（例: `--tags '["build","test"]'`）を渡すか、カンマ区切り文字列（`--tags "build,test"`）を渡すことで配列に変換されます。スペース区切りの複数値入力（`--tags build test`）にはまだ対応しておらず、繰り返し注記のないオプションは従来どおりスカラーとして扱われます。`--strict` 実行時は各要素の型も検証されるため、`[String[]]` と書かれているのに `--tags [1,2]` のような数値配列を渡すと即エラーになります。

JSON やカンマ区切りで表現しづらいシンボル配列・ハッシュなどを渡したい場合は eval モード（`--eval-args`/`-e` または `--eval-lax`/`-E`）を有効にし、ドキュメントで宣言した型に合わせた Ruby リテラルを渡してください。スペース区切りが未対応でも、安全に複数選択を指定できます（後述の eval 例を参照）。

代表的な推論例:

- `ARG1` のように型ラベルを省略したプレースホルダは既定で `String` として扱われます。
- `--name ARG1` のようにオプションへプレースホルダだけを指定しても同じく `String` が推論されます。
- `--verbose` のように値プレースホルダを省略したオプションは Boolean フラグとして扱われます。
- 位置引数を Boolean にしたい場合は必ず `[Boolean]` を明示してください。`NAME 説明` や `@param name 説明` のように型を省略すると、Ruby 側のデフォルト値に関わらず `String` とみなされます。

### リテラル列挙による制約

`--format MODE [:json, :yaml, :auto]` や `LEVEL [:info, :warn]` のように型注釈内へ許容リテラルを列挙すると、ヘルプに選択肢を表示しつつ Rubycli が入力制約として解釈します。シンボル・文字列（裸の単語も可）・真偽値・数値・`nil` に対応し、型ヒントと混在させて `--channel TARGET [:stdout, :stderr, Boolean]` のような宣言も書けます。`%i[info warn]` / `%w[debug info]` などの短縮記法も展開されるため、`LEVEL %i[info warn]` でも同じ効果になります。通常実行では許可外の入力に警告を表示して続行し、`--strict` を付けた場合は `Rubycli::ArgumentError` を送出して即座に停止します。

> シンボルと文字列は厳密に区別されます。`[:info, :warn]` と書いた場合は `:info` のようにコロン付きで入力してください。`["info", "warn"]` を選んだ場合はプレーンな文字列のみ受け付けます。

> 列挙は各スカラー値に適用されます。`[Symbol[]]` のような配列注釈に対して「許可される組み合わせ」をリテラルで書く構文（例: `[%i[foo bar][]]`）は未サポートなので、必要に応じて文章で説明するか、eval モードで Ruby の配列を渡してください。

```bash
# literal choice デモ (examples/strict_choices_demo.rb)
ruby examples/strict_choices_demo.rb report warn --format json
#=> [WARN] format=json

# --strict を付けると仕様外の値で即エラー
ruby -Ilib exe/rubycli --strict examples/strict_choices_demo.rb report debug
#=> Rubycli::ArgumentError: Value "debug" for LEVEL is not allowed: allowed values are :info, :warn, :error
```

```bash
# シンボル入力はコロンを付ける
ruby -Ilib exe/rubycli --strict examples/strict_choices_demo.rb report :warn
#=> [WARN] format=text

ruby -Ilib exe/rubycli --strict examples/strict_choices_demo.rb report warn
#=> Rubycli::ArgumentError: Value "warn" for LEVEL is not allowed: allowed values are :info, :warn, :error
```

### 標準ライブラリ型ヒント

コメントに `Date` や `Time`, `BigDecimal`, `Pathname` など標準ライブラリの型名を書けば、Rubycli が必要な `require` を行った上で CLI 引数をその型へ変換します。

```bash
# examples/typed_arguments_demo.rb より
ruby examples/typed_arguments_demo.rb ingest \
  --date 2024-12-25 \
  --moment 2024-12-25T10:00:00Z \
  --budget 123.45 \
  --input ./data/input.csv
```

ハンドラ側には `Date` / `Time` / `BigDecimal` / `Pathname` のインスタンスがそのまま渡るため、追加のパース処理は不要です。

各オプションには既定値があるため、`ruby examples/typed_arguments_demo.rb ingest --budget 999.99` のように個別の型だけ試すこともできます。

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

`AMOUNT` だけがドキュメント化されていますが、`factor` や `clamp`, `notify` も自動的に補完され、既定値や型が推論されていることがわかります。開発時は `rubycli --check 対象.rb` でコメントとシグネチャの矛盾を検出し、本番実行で `--strict` を付ければ仕様外の入力をその場で弾けます。

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

Ruby 評価はシンボルや配列／ハッシュもそのまま扱えるため、列挙値の組み合わせをオプションへ渡すときにも役立ちます。

```bash
rubycli -E scripts/report_runner.rb publish \
  --targets '[:marketing, :sales]' \
  --channels '[:email, :slack]'
```

Ruby 評価を使いつつ、構文エラーが出たときは元の文字列にフォールバックさせたい場合は `--eval-lax`（短縮形 `-E`）を指定します。`--eval-args` と同じく eval モードを有効にしますが、Ruby として解釈できなかったトークン（例: 素の `https://example.com`）は警告を出した上でそのまま渡すため、`60*60*24*14` のような式と文字列を気軽に混在させられます。

`--json-args`/`-j` は `--eval-args`/`-e` および `--eval-lax`/`-E` と同時指定できません。どのモードも既定のリテラル解析を拡張する位置づけなので、用途に応じて厳格な JSON か Ruby eval（通常／lax）のいずれかを選択してください。

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
| `RUBYCLI_DEBUG=true` | デバッグログ表示 | `false` |
| `--check` | コメント／実装のズレを検査し、コマンドは実行しない | `off` |
| `--strict` | ドキュメントで許可した型・値以外をエラーとして拒否 | `off` |
| `RUBYCLI_ALLOW_PARAM_COMMENT=OFF` | レガシーな `@param` 記法を無効化（互換性のため既定では ON） | `ON` |

## Rubycli API

- `Rubycli.parse_arguments(argv, method)` – コメント情報を考慮した引数解析
- `Rubycli.available_commands(target)` – 公開 CLI コマンド一覧
- `Rubycli.usage_for_method(name, method)` – 指定メソッドのヘルプ生成
- `Rubycli.method_description(method)` – 構造化されたドキュメント取得

ご意見・フィードバックは Issue や Pull Request でお寄せください。
