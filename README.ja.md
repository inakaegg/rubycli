# Rubycli — Python Fire 風の Ruby 向け CLI

![Rubycli ロゴ](assets/rubycli-logo.png)

[![Gem Version](https://img.shields.io/gem/v/rubycli)](https://rubygems.org/gems/rubycli)

Rubycli は、既存の Ruby クラス／モジュールをそのままコマンドラインインターフェースにするツールです。
公開メソッドの定義と、メソッドに付けたドキュメントコメントを読み取って CLI を組み立てるため、
最小構成ではスクリプト側の変更が一切不要です（`require "rubycli"` すら要りません）。
コメント内の型アノテーションは単なる説明ではなく、CLI 引数の解釈そのものを制御します
（例: `TAG... [String[]]` と書くと配列としてパースされます）。

[Python Fire](https://github.com/google/python-fire) にインスパイアされていますが、
移植や公式プロジェクトではなく、Ruby のコメント記法と型アノテーションに焦点を当てた独自実装です。

> English documentation: [README.md](README.md)

![Rubycli のデモ（コマンド生成と実行の様子）](assets/rubycli-demo.gif)

## インストール

```bash
gem install rubycli
```

```ruby
# Gemfile
gem "rubycli"
```

Ruby 3.0 以上が必要です。ライセンスは [MIT](LICENSE) です。

## クイックスタート

### 1. 既存スクリプトをそのまま実行する

```ruby
# hello_app.rb
module HelloApp
  module_function

  def greet(name)
    puts "Hello, #{name}!"
  end
end
```

同じ内容を `examples/hello_app.rb` として同梱しているので、以下のコマンドは
プロジェクト直下でそのまま試せます。

```bash
rubycli examples/hello_app.rb
```

```text
Usage: hello_app.rb COMMAND [arguments]

Available commands:
  Class methods:
    greet                NAME

Detailed command help: hello_app.rb COMMAND help
```

引数が足りない場合はスタックトレースではなく使い方が表示されます。

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

`rubycli examples/hello_app.rb --help` でも、コマンド未指定時と同じ一覧が表示されます。

### 2. コメントを足して型付きオプションを有効にする

この段階でも `require "rubycli"` は不要です。コメントだけでオプション解析とヘルプが変わります。
簡潔なプレースホルダ記法と YARD タグのどちらでも書けます。

```ruby
# 簡潔なプレースホルダ記法
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

```ruby
# YARD タグ
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

ドキュメント付きの版は `examples/hello_app_with_docs.rb` として同梱しています。
このファイル名は定義している定数（`HelloApp`）と一致しないため、実行時に
`--auto-target` / `-a` を付けるか、定数名を明示してください
（詳細は後述の[対象定数の解決](#対象定数の解決)を参照）。

```bash
rubycli -a examples/hello_app_with_docs.rb greet --help
```

```text
Usage: hello_app_with_docs.rb greet NAME [--shout]

Positional arguments:
  NAME  [String]  required  Name to greet

Options:
  --shout  [Boolean]  optional  Print in uppercase (default: false)
```

```bash
rubycli -a examples/hello_app_with_docs.rb greet --shout Hanako
#=> HELLO, HANAKO!
```

CLI に公開したくないヘルパーは、特異クラス側で `private` として定義します。

```ruby
module HelloApp
  class << self
    private

    def internal_ping(url)
      # CLI コマンドとしては公開されない
    end
  end
end
```

### 3. （任意）スクリプトにランナーを組み込む

`ruby スクリプト.rb ...` の形で起動したい場合は、gem を require して
`Rubycli.run` に委譲します（`examples/hello_app_with_require.rb` として同梱）。

```ruby
# hello_app_with_require.rb
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

```bash
ruby examples/hello_app_with_require.rb greet Taro --shout
#=> HELLO, TARO!
```

付属の `rubycli` コマンド経由で実行した場合は、メソッドの戻り値が自動で標準出力に表示されます。

## 対象定数の解決

Rubycli は「ファイル名を CamelCase にした定数」を公開対象と想定します。
一致しない場合の挙動はモードで切り替えられます。

| モード | 有効化方法 | 挙動 |
| --- | --- | --- |
| `strict`（既定） | 何もしない / `RUBYCLI_AUTO_TARGET=strict` | CamelCase 名が一致しないとエラー。検出した定数一覧と再実行方法を表示します。 |
| `auto` | `--auto-target` / `-a` / `RUBYCLI_AUTO_TARGET=auto` | CLI として実行できる定数がファイル内に 1 つだけなら自動選択します。 |

ファイルパスの後ろに定数名を明示することもできます。1 ファイルに候補が複数ある場合や、
ネストした定数を選びたい場合に便利です。

```bash
rubycli scripts/multi_runner.rb Admin::Runner list --active
```

`Module1::Inner::Runner` のようなネストした定数も検出できます。

## インスタンスメソッド専用クラスと `--new`

公開メソッドがインスタンス側にしかないクラスは、`--new` を付けて事前にインスタンス化しないと
CLI から呼び出せません（Rubycli から見えるコマンドが 1 つもない状態になります）。

- `--new` を付けると `--help` の一覧にインスタンスメソッドが現れ、
  `rubycli --check --new` でコメントの lint も実行できます。
- コンストラクタに引数が必要な場合は、**ファイルパスより前に** `--new=VALUE` の形で渡します。
  値は安全な YAML/JSON ライクなリテラルとして解釈され、`initialize` に付けたコメントも
  通常の CLI メソッドと同様に型変換へ反映されます。
- スペース区切りの `--new VALUE` は値がファイルパスと誤認されやすいため、
  `--new=VALUE` の形を推奨します。

実行例（`examples/new_mode_runner.rb`）:

```bash
rubycli --new='["a","b","c"]' examples/new_mode_runner.rb run --mode reverse
#=> ["c", "b", "a"]
```

## コメント記法

YARD タグと短縮形のどちらでも書けます。

| 用途 | YARD 互換 | Rubycli 標準 |
| ---- | --------- | ----------- |
| 位置引数 | `@param name [Type] 説明` | `NAME [Type] 説明` |
| キーワード引数 | 同上 | `--flag -f VALUE [Type] 説明` |
| 戻り値 | `@return [Type] 説明` | `=> [Type] 説明` |

短いオプション（`-f` など）は任意で、順序も自由です。次の 3 つは同義です。

- `--flag -f VALUE [Type] 説明`
- `--flag VALUE [Type] 説明`
- `-f --flag VALUE [Type] 説明`

型は `[String]` でも `(String)` でも指定でき、`(String, nil)` のように複数型も書けます。

### 互換プレースホルダ表記

コメントの解析とヘルプ出力の両方で、次の表記も同じ意味として扱われます。

- 山括弧: `--flag <value>`, `NAME [<value>]`
- `=` 付きロングオプション: `--flag=<value>`
- 繰り返し指定: `VALUE...`, `<value>...`

実行時には `--flag VALUE`, `--flag <value>`, `--flag=<value>` のどれも同じ扱いなので、
プロジェクトで読みやすいスタイルを選んでください。任意引数を自分で角括弧に包む必要は
ありません。必須／任意は Ruby のメソッドシグネチャから自動判定され、ヘルプ出力では
Rubycli が角括弧を補います。

注釈が部分的な場合の推論規則:

- `ARG1` のように型を省略したプレースホルダは `String` として扱われます。
- 値プレースホルダのないオプション（`--verbose`）は Boolean フラグになります。
- 位置引数を Boolean にするには `[Boolean]` の明示が必要です。`NAME 説明` のように
  型を省略すると、Ruby 側のデフォルト値に関わらず `String` とみなされます。

### 配列と繰り返し値

`TAG...` のような繰り返し指定、または `[String[]]` / `Array<String>` のような配列型注釈が
付いたオプションは配列としてパースされます。JSON/YAML 形式のリスト
（`--tags '["build","test"]'`）とカンマ区切り文字列（`--tags "build,test"`）の両方を
受け付けます。スペース区切りの複数値（`--tags build test`）には対応しておらず、
繰り返し注記のないオプションはスカラーのままです。`--strict` 実行時は各要素の型も
検証されるため、`[String[]]` と書かれた注釈に対して `--tags [1,2]` を渡すとエラーになります。
`--tags '["true","null"]'` のように引用された要素は、別のリテラルに見える内容でも文字列の
まま保持されます。

### リテラル列挙（enum）

許容値の集合を型注釈の中に直接書けます: `--format MODE [:json, :yaml, :auto]`、
`LEVEL [:info, :warn]` など。シンボル・文字列（裸の単語も可）・真偽値・数値・`nil` に対応し、
`--channel TARGET [:stdout, :stderr, Boolean]` のように通常の型とも混在できます。
`%i[info warn]` / `%w[debug info]` の短縮記法も展開されます。選択肢は常にヘルプへ表示され、
許可外の値は `--strict` なしなら警告のみで続行、`--strict` 付きなら中断します。

シンボルと文字列は厳密に区別されます。`[:info, :warn]` にはコロン付きの `:info` を、
`["info", "warn"]` にはプレーンな文字列を入力してください。

```bash
# examples/strict_choices_demo.rb — LEVEL の注釈は [:info, :warn, :error]
rubycli examples/strict_choices_demo.rb report :warn --format json
#=> [WARN] format=json   （続けて戻り値のハッシュが表示される）

# 裸の文字列はシンボルと一致しない: 警告して続行
rubycli examples/strict_choices_demo.rb report warn
#=> [WARN] LEVEL must be one of :info, :warn, :error (received "warn") (use --strict to abort on invalid input)

# --strict を付けると許可外の入力で中断
rubycli --strict examples/strict_choices_demo.rb report debug
#=> [ERROR] LEVEL must be one of :info, :warn, :error (received "debug")
```

列挙は各スカラー引数に適用されます。`[%i[foo bar][]]` のような「配列の許容組み合わせ」を
リテラルで書く構文は未サポートです。

### 標準ライブラリの型ヒント

コメントに `Date`、`Time`、`BigDecimal`、`Pathname` などの標準クラスを書くと、
Rubycli が必要な stdlib を読み込んだ上で CLI 入力をその型へ変換します。
ハンドラには実際のオブジェクトが渡るため、追加のパース処理は不要です。

```bash
# examples/typed_arguments_demo.rb を参照
rubycli examples/typed_arguments_demo.rb ingest \
  --date 2024-12-25 \
  --moment 2024-12-25T10:00:00Z \
  --budget 123.45 \
  --input ./data/input.csv
```

各オプションには既定値があるため、`... ingest --budget 999.99` のように
1 つずつ試すこともできます。

`@example`、`@raise`、`@see`、`@deprecated` などその他の YARD タグは、
現状ヘルプ出力には反映されません。

> すべての記法をまとめて試すには
> `rubycli examples/documentation_style_showcase.rb canonical --help` などの
> showcase コマンドを実行してください。

### YARD 互換コメントを併用する際の注意

- `**kwargs` を受け取るメソッドでも、キーは自動では公開されません。CLI で使わせたいキーは
  すべて `--long-name PLACEHOLDER [Type] 説明` の行として明示してください。
- `@param` 行に続く箇条書きや補足行は CLI 生成には使われません。補足情報は
  オプションの説明文に含めてください。
- 簡潔なプレースホルダ記法へ統一したい場合は `RUBYCLI_ALLOW_PARAM_COMMENT=OFF` を
  設定します。`@param`/`@return` タグが警告扱いになり、段階的に移行できます。

### コメントが不足している場合

Rubycli は常に実装のメソッドシグネチャを信頼します。コメントに書かれていない引数も、
定義から名前・既定値・型を推論して CLI に公開されます。

```ruby
# examples/fallback_example.rb
module FallbackExample
  module_function

  # AMOUNT [Integer] Base amount to process
  def scale(amount, factor = 2, clamp: nil, notify: false)
    result = amount * factor
    result = [result, clamp].min if clamp
    puts "Scaled to #{result}" if notify
    result
  end
end
```

```bash
rubycli examples/fallback_example.rb scale --help
```

```text
Usage: fallback_example.rb scale AMOUNT [FACTOR] [--clamp=<CLAMP>] [--notify]

Positional arguments:
  AMOUNT  [Integer]  required  Base amount to process
  FACTOR  [String]   optional  (default: 2)

Options:
  --clamp=<CLAMP>  [String]   optional  (default: nil)
  --notify         [Boolean]  optional  (default: false)
```

ドキュメント化されているのは `AMOUNT` だけですが、`factor`・`clamp`・`notify` も
推論された既定値・型付きで表示されます。

コメントだけで実引数が増えることはありません。実装に存在しないオプション（例: `--ghost`）や
位置引数をコメントに書いた場合、その行はヘルプ末尾の詳細セクションに素のテキストとして
表示されるだけで、strict モードでは位置引数のズレに対する警告も出ます。動作するデモ:
`rubycli examples/fallback_example_with_extra_docs.rb scale --help`

開発中は `rubycli --check 対象.rb` でコメントと実装のズレ（未定義の型ラベルや列挙値の
誤記を含む。DidYouMean の候補付き）を検出し、実行時に `--strict` を付ければ仕様外の
入力を警告ではなくエラーにできます。

> `--strict` はコメントに書かれた型・許容値をそのまま信頼します。コメント自体の誤記は
> 実行時には検出できないため、CI で `rubycli --check` を回した上で `--strict` を
> 使ってください。

## 引数解析モード

### 既定のリテラル解析

`{`、`[`、クォート、YAML 記号で始まる「構造化リテラルらしい」引数は `Psych.safe_load` で
解釈され、`--names='["Alice","Bob"]'` や `--config='{foo: 1}'` は追加フラグなしで
ネイティブな配列・ハッシュとして届きます。`1,2,3` のようなプレーンな文字列はこの段階では
そのまま維持され（コメントで `String[]` や `TAG...` と宣言されていれば後段で配列化）、
解釈できない形式は元の文字列にフォールバックします。`"2024-01-01"` は文字列のまま届き、
構文が崩れた入力でも実行全体は落ちません。

### JSON モード（`--json-args` / `-j`）

後続の引数を厳格に JSON として解釈します。YAML 固有の記法は拒否され、無効な JSON は
`JSON::ParserError` になるため、silent fallback ではなく明示的な失敗が欲しい場合に
便利です。プログラムからは `Rubycli.with_json_mode(true) { ... }` で切り替えられます。

### Eval モード（`--eval-args` / `-e`、`--eval-lax` / `-E`）

各引数を Ruby 式として評価してから渡します。シンボル配列・Range・インライン計算など、
JSON では書きにくい値に便利です。

```bash
rubycli -E scripts/report_runner.rb publish \
  --targets '[:marketing, :sales]' \
  --channels '[:email, :slack]'
```

評価は隔離された binding（`Object.new.instance_eval { binding }`）内で行われます。
1回の Runner 実行では、`--new=VALUE` のコンストラクタ引数と選択したコマンドの引数を含む
すべての eval 引数が同じ binding を共有し、実行終了時に破棄されます。入力そのものは
信頼できる呼び出し元に限定してください。プログラムからは
`Rubycli.with_eval_mode(true) { ... }` で切り替えられます。

`--eval-lax` / `-E` は `--eval-args` と同様に eval モードを有効にしつつ、Ruby として
解釈できなかったトークン（例: 素の `https://example.com`）は警告を出して元の文字列の
まま渡します。`60*60*24*14` のような式と通常の文字列を混在させたいときに便利です。

`--json-args` と eval 系フラグは同時指定できません（両方あるとエラーになります）。

## Pre-script ブートストラップ

`--pre-script SRC`（別名: `--init`）を付けると、コマンド解決の前に任意の Ruby コードを
評価できます。評価は隔離された binding 内で行われ、次のローカル変数が用意されています。

- `target` — 元のクラス／モジュール（`--new` 適用前）
- `current` / `instance` — そのまま公開される予定のオブジェクト

最後に評価された値が新しい公開対象になります（`nil` を返すと直前のオブジェクトを維持）。
`SRC` にはインラインの Ruby コードとファイルパスのどちらも指定できます。

実行例 — `--new` で作られるインスタンスを、自分で組み立てたものに差し替える:

```bash
rubycli --new='["a"]' \
  --pre-script 'NewModeRunner.new(%w[a b c], options: {from: :pre})' \
  examples/new_mode_runner.rb run --mode summary
```

## フラグと環境変数

| フラグ / 環境変数 | 説明 | 既定値 |
| ---------------- | ---- | ------ |
| `--auto-target` / `-a`, `RUBYCLI_AUTO_TARGET=auto` | ファイル名と定数名が一致しないときに自動選択 | `strict` |
| `--new[=VALUE]` | コマンド解決前にインスタンス化。`VALUE` はコンストラクタ引数 | off |
| `--pre-script SRC` / `--init SRC` | 公開対象オブジェクトを Ruby コードで構築・差し替え | off |
| `--check` | コメントと実装のズレを検査（コマンドは実行しない） | off |
| `--strict` | ドキュメントの型・許容値を強制。仕様外入力はエラー | off |
| `--json-args` / `-j` | 引数を厳格に JSON として解釈 | off |
| `--eval-args` / `-e`, `--eval-lax` / `-E` | 引数を Ruby として評価（lax は失敗時に素の文字列へフォールバック） | off |
| `RUBYCLI_DEBUG=true` | デバッグログを表示 | `false` |
| `RUBYCLI_ALLOW_PARAM_COMMENT=OFF` | YARD `@param` 行を無効化（互換性のため既定は有効） | `ON` |

## ライブラリ API

- `Rubycli.parse_arguments(argv, method)` — コメント情報を考慮した引数解析
- `Rubycli.available_commands(target)` — 公開 CLI コマンド一覧
- `Rubycli.usage_for_method(name, method)` — 指定メソッドのヘルプ生成
- `Rubycli.method_description(method)` — 構造化されたドキュメント取得

## Python Fire との違い

- **コメント対応のヘルプ生成** — コメントはヘルプを豊かにしますが、最終的な判断は常に
  ライブなメソッド定義に基づきます。
- **型に基づく解析** — プレースホルダ記法と YARD タグから、真偽値・配列・数値などへ
  追加コードなしで変換します。
- **二段構えの検証** — `--check` はコマンドを実行せずにドキュメントのズレを lint し、
  `--strict` はドキュメントの型・許容値を実行時の契約として強制します。
- **Ruby 中心の設計** — キーワード引数、ブロックドキュメント（`@yield*` タグ）、
  `RUBYCLI_*` 環境変数に対応します。

| 機能 | Python Fire | Rubycli |
| ---- | ----------- | ------- |
| 属性の辿り方 | プロパティ／属性を再帰的に自動公開 | 対象の公開メソッドのみ公開（暗黙の辿りなし） |
| クラス初期化 | `__init__` 引数を自動で受け取る | `--new` 指定時のみ初期化。引数は `--new=VALUE`、複雑な構築は pre-script |
| インタラクティブシェル | コマンド未指定時に Fire REPL | なし。コマンド実行専用 |
| 情報源 | 純粋なリフレクション | ライブなメソッド定義 + コメントをヘルプへ反映 |
| 辞書/配列 | dict/list を自動でサブコマンド化 | クラス／モジュールのメソッドに特化（自動展開なし） |

## 開発方針

- **便利さを最優先** — 既存の Ruby スクリプトを最小の手間で CLI 化することが目的です。
  Python Fire との機能一致は目標ではなく、Fire 由来の未実装機能は基本的に仕様です。
- **メソッド定義が土台、コメントが補強** — 公開範囲と必須／任意はシグネチャが決め、
  コメントは型・ヘルプ・検証を補強します。
- **軽量メンテナンス** — 実装の多くは AI 支援で作られており、深い Ruby メタプログラミングに
  踏み込む拡張は想定外です。互換性追求の PR は事前にご相談ください。

## 同梱サンプル

- `examples/hello_app.rb` / `examples/hello_app_with_docs.rb` — 最小のモジュール関数、
  ドキュメントなし／あり
- `examples/hello_app_with_require.rb` — `Rubycli.run` の組み込み
- `examples/typed_arguments_demo.rb` — 標準ライブラリ型の変換
  （Date/Time/BigDecimal/Pathname）
- `examples/strict_choices_demo.rb` — リテラル列挙と `--strict`
- `examples/new_mode_runner.rb` — `--new=VALUE` で初期化するインスタンス専用クラス
- `examples/documentation_style_showcase.rb` — 全コメント記法のショーケース
- `examples/fallback_example.rb` / `examples/fallback_example_with_extra_docs.rb`
  — シグネチャからの補完とコメント不一致のデモ

## 開発時の検証

全テストを実行し、リポジトリのカバレッジ基準
（全体 line 90%、branch 70%、`origin/main` から変更した実行可能行 90%）
を検査するには次を実行します。

```bash
ruby -Ilib:test test/coverage_runner.rb
```

## ライセンス

MIT。[LICENSE](LICENSE) を参照してください。

ご意見・不具合報告は Issue や Pull Request でお寄せください。
