# Rubycli — Python Fire-inspired CLI for Ruby

![Rubycli logo](assets/rubycli-logo.png)

Rubycli turns existing Ruby classes and modules into CLIs by inspecting their public method definitions and the doc comments attached to those methods. It is inspired by [Python Fire](https://github.com/google/python-fire) but is not a drop-in port or an official project; the focus here is Ruby’s documentation conventions and type annotations, and those annotations can actively change how a CLI argument is coerced (for example, `TAG... [String[]]` forces array parsing).

> 🇯🇵 Japanese documentation is available in [README.ja.md](README.ja.md).

![Rubycli demo showing generated commands and invocation](assets/rubycli-demo.gif)

### 1. Existing Ruby script (Rubycli unaware)

```ruby
# hello_app.rb
module HelloApp
  module_function

  def greet(name)
    puts "Hello, #{name}!"
  end
end
```

> Try it yourself: this repository ships with `examples/hello_app.rb`, so from the project root you can run `rubycli examples/hello_app.rb` to explore the generated commands.

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

Running `rubycli examples/hello_app.rb --help` prints the same summary as invoking it without a command.

### 2. Add documentation hints for richer flags

> Still no `require "rubycli"` needed; comments alone drive option parsing and help text.

**Concise placeholder style**

```ruby
# hello_app.rb
module HelloApp
  module_function

  # NAME [String] Name to greet
  # --shout [Boolean] Print in uppercase
  def greet(name, shout: false)
    message = "Hello, #{name}!"
    message = message.upcase if shout
    puts message
  end
end
```

**YARD-style tags work too**

```ruby
# hello_app.rb
module HelloApp
  module_function

  # @param name [String] Name to greet
  # @param shout [Boolean] Print in uppercase
  def greet(name, shout: false)
    message = "Hello, #{name}!"
    message = message.upcase if shout
    puts message
  end
end
```

> The documented variant lives at `examples/hello_app_with_docs.rb` if you want to follow along locally.

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
  NAME  [String]  required  Name to greet

Options:
  --shout  [Boolean]  optional  Print in uppercase (default: false)
```

```bash
rubycli examples/hello_app_with_docs.rb greet --shout Hanako
#=> HELLO, HANAKO!
```

Need to keep a helper off the CLI? Define it as `private` on the singleton class:

```ruby
module HelloApp
  class << self
    private

    def internal_ping(url)
      # not exposed as a CLI command
    end
  end
end
```

### 3. (Optional) Embed the runner inside your script

Prefer to launch via `ruby ...` directly? Require the gem and delegate to `Rubycli.run` (see Quick start below for `examples/hello_app_with_require.rb`).

```bash
ruby examples/hello_app_with_require.rb greet Hanako --shout
#=> HELLO, HANAKO!
```

## Constant resolution modes

Rubycli assumes that the file name (CamelCased) matches the class or module you want to expose. When that is not the case you can choose how eagerly Rubycli should pick a constant:

| Mode | How to enable | Behaviour |
| --- | --- | --- |
| `strict` (default) | do nothing / `RUBYCLI_AUTO_TARGET=strict` | Fails unless the CamelCase name matches. The error lists the detected constants and gives explicit rerun instructions. |
| `auto` | `--auto-target`, `-a`, or `RUBYCLI_AUTO_TARGET=auto` | If exactly one constant in that file defines CLI-callable methods, Rubycli auto-selects it; otherwise you still get the friendly error message. |

This keeps large projects safe by default but still provides a one-flag escape hatch when you prefer the fully automatic behaviour.

> **Instance-only classes** – If a class only defines public *instance* methods (for example, it exposes functionality via `attr_reader` or `def greet` on the instance), you must run Rubycli with `--new` so the class is instantiated before commands are resolved. Otherwise Rubycli cannot see any CLI-callable methods. Add at least one public class method when you do not want to rely on `--new`.

## Project Philosophy

- **Convenience first** – The goal is to wrap existing Ruby scripts in a CLI with almost no manual plumbing. Fidelity with Python Fire is not a requirement.
- **Inspired, not a port** – We borrow ideas from Python Fire, but we do not aim for feature parity. Missing Fire features are generally “by design.”
- **Method definitions first, comments augment behavior** – Public method signatures determine what gets exposed (and which arguments are required), while doc comments like `TAG...` or `[Integer]` can turn the very same CLI value into arrays, integers, booleans, etc. Enable strict mode (`RUBYCLI_STRICT=ON`) when you want warnings about mismatches.
- **Lightweight maintenance** – Much of the implementation was generated with AI assistance; contributions that diverge into deep Ruby metaprogramming are out of scope. Please discuss expectations before opening parity PRs.

## Features

- Comment-aware CLI generation with both YARD-style tags and concise placeholders
- Automatic option signature inference (`NAME [Type] Description…`) without extra DSLs
- Safe literal parsing out of the box (arrays / hashes / booleans) with opt-in strict JSON and Ruby eval modes
- Optional pre-script hook (`--pre-script` / `--init`) to evaluate Ruby and expose the resulting object
- Opt-in strict mode (`RUBYCLI_STRICT=ON`) that emits warnings whenever comments contradict method signatures

## How it differs from Python Fire

- **Comment-aware help** – Rubycli leans on doc comments when present but still reflects the live method signature, keeping code as the ultimate authority.
- **Type-aware parsing** – Placeholder syntax (`NAME [String]`) and YARD tags let Rubycli coerce arguments to booleans, arrays, numerics, etc. without additional code.
- **Strict validation** – Opt-in strict mode surfaces warnings when comments fall out of sync with method signatures, helping teams keep help text accurate.
- **Ruby-centric tooling** – Supports Ruby-specific conventions such as optional keyword arguments, block documentation (`@yield*` tags), and `RUBYCLI_*` environment toggles.

| Capability | Python Fire | Rubycli |
| ---------- | ----------- | -------- |
| Attribute traversal | Recursively exposes attributes/properties on demand | Exposes public methods defined on the target; no implicit traversal |
| Constructor handling | Automatically prompts for `__init__` args when instantiating classes | `--new` simply instantiates without passing CLI args (use pre-scripts or your own factories if you need injected dependencies) |
| Interactive shell | Offers Fire-specific REPL when invoked without command | No interactive shell mode; strictly command execution |
| Input discovery | Pure reflection, no doc comments required | Doc comments drive option names, placeholders, and validation |
| Data structures | Dictionaries / lists become subcommands by default | Focused on class or module methods; no automatic dict/list expansion |

## Installation

Rubycli is published on RubyGems.

```bash
gem install rubycli
```

Bundler example:

```ruby
# Gemfile
gem "rubycli"
```

## Quick start (embed Rubycli in the script)

Step 3 adds `require "rubycli"` so the script can invoke the CLI directly (see `examples/hello_app_with_require.rb`):

```ruby
# hello_app_with_require.rb
require "rubycli"

module HelloApp
  module_function

  # NAME [String] Name to greet
  # --shout [Boolean] Print in uppercase
  # => [String] Printed message
  def greet(name, shout: false)
    message = "Hello, #{name}!"
    message = message.upcase if shout
    puts message
    message
  end
end

Rubycli.run(HelloApp)
```

Run it:

```bash
ruby examples/hello_app_with_require.rb greet Taro
#=> Hello, Taro!

ruby examples/hello_app_with_require.rb greet Taro --shout
#=> HELLO, TARO!
```

To launch the same file without adding `require "rubycli"`, use the bundled executable:

```bash
rubycli path/to/hello_app.rb greet --shout Hanako
```

When you omit `CLASS_OR_MODULE`, Rubycli now infers it from the file name and even locates nested constants such as `Module1::Inner::Runner`. Return values are printed by default when you run the bundled CLI.

Need to target a different constant explicitly? Provide it after the file path:

```bash
rubycli scripts/multi_runner.rb Admin::Runner list --active
```

This is useful when a file defines multiple candidates or when you want a nested constant that does not match the file name.

## Comment syntax

Rubycli parses a hybrid format – you can stick to familiar YARD tags or use short forms.

| Purpose | YARD-compatible | Rubycli style |
| ------- | --------------- | ------------- |
| Positional argument | `@param name [Type] Description` | `NAME [Type] Description` |
| Keyword option | Same as above | `--flag -f VALUE [Type] Description` |
| Return value | `@return [Type] Description` | `=> [Type] Description` |

Short options are optional and order-independent, so the following examples are equivalent in Rubycli’s default style:

- `--flag -f VALUE [Type] Description`
- `--flag VALUE [Type] Description`
- `-f --flag VALUE [Type] Description`

Our examples keep the classic uppercase placeholders (`NAME`, `VALUE`) as the canonical style; the variations below are optional sugar.

### Alternate placeholder notations

Rubycli also understands these syntaxes when parsing comments and rendering help:

- Angle brackets for user input: `--flag <value>` or `NAME [<value>]`
- Inline equals for long options: `--flag=<value>`
- Trailing ellipsis for repeated values: `VALUE...` or `<value>...`

The CLI treats `--flag VALUE`, `--flag <value>`, and `--flag=<value>` identically at runtime—document with whichever variant your team prefers. Optional placeholders like `[VALUE]` or `[VALUE...]` let Rubycli infer boolean flags, optional values, and list coercion. When you omit the placeholder entirely (for example `--quiet`), Rubycli infers a Boolean flag automatically.

> Tip: You do not need to wrap optional arguments in brackets inside the comment. Rubycli already knows which parameters are optional from the Ruby signature and will introduce the brackets in generated help.

You can annotate types using `[String]`, `(String)`, or `(type: String)`—they all convey the same hint, and you can list multiple types such as `(String, nil)` or `(type: String, nil)`.

Repeated values (`VALUE...`) now materialize as arrays automatically whenever the option is documented with an ellipsis (for example `TAG...`) or an explicit array type hint (`[String[]]`, `Array<String>`). Supply either JSON/YAML list syntax (`--tags "[\"build\",\"test\"]"`) or a comma-delimited string (`--tags "build,test"`); Rubycli will coerce both forms to arrays. Space-separated multi-value flags (`--tags build test`) are still not supported, and options without a repeated/array hint continue to be parsed as scalars.

Common inference rules:

- Writing a placeholder such as `ARG1` (without `[String]`) makes Rubycli treat it as a `String`.
- Using that placeholder in an option line (`--name ARG1`) also infers a `String`.
- Omitting the placeholder entirely (`--verbose`) produces a Boolean flag.

Other YARD tags such as `@example`, `@raise`, `@see`, and `@deprecated` are currently ignored by the CLI renderer.

> Want to explore every notation in a single script? Try `rubycli examples/documentation_style_showcase.rb canonical --help`, `... angled --help`, or the other showcase commands.

YARD-style `@param` annotations continue to work out of the box. If you want to enforce the concise placeholder syntax exclusively, set `RUBYCLI_ALLOW_PARAM_COMMENT=OFF` (strict mode still applies either way).

### When docs are missing or incomplete

Rubycli always trusts the live method signature. If a parameter (or option) is undocumented, the CLI still exposes it using the parameter name and default values inferred from the method definition:

```ruby
# fallback_example.rb
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
  AMOUNT  [Integer]  required  Base amount to process
  FACTOR             optional  (default: 2)

Options:
  --clamp=<CLAMP>  [String]   optional  (default: nil)
  --notify         [Boolean]  optional  (default: false)
```

Here only `AMOUNT` is documented, yet `factor`, `clamp`, and `notify` are still presented with sensible defaults and inferred types. Enable strict mode (`RUBYCLI_STRICT=ON`) if you want mismatches between comments and signatures to surface as warnings during development.

#### What if the docs mention arguments that do not exist?

- **Out-of-sync lines fall back to plain text** – Comments that reference non-existent options (for example `--ghost`) or positionals (such as `EXTRA`) are emitted verbatim in the help’s detail section. They do not materialize as real arguments, and strict mode still warns about positional mismatches (`Extra positional argument comments were found: EXTRA`) so you can reconcile the docs.

> Want to see this behaviour? Try `rubycli examples/fallback_example_with_extra_docs.rb scale --help` for a runnable mismatch demo.

In short, comments never add live parameters by themselves; they enrich or describe what your method already supports.

## Argument parsing modes

### Default literal parsing

Rubycli tries to interpret arguments that look like structured literals (values starting with `{`, `[`, quotes, or YAML front matter) using `Psych.safe_load` before handing them to your code. That means values such as `--names='["Alice","Bob"]'` or `--config='{foo: 1}'` arrive as native arrays / hashes without any extra flags. Plain strings like `1,2,3` stay untouched at this stage (if the documentation declares `String[]` or `TAG...`, a later pass still normalises them into arrays), and unsupported constructs fall back to the original text, so `"2024-01-01"` remains a string and malformed payloads still reach your method instead of killing the run.

### JSON mode

Supply `--json-args` (or the shorthand `-j`) when invoking the runner and Rubycli will parse subsequent arguments strictly as JSON before passing them to your method:

```bash
rubycli -j my_cli.rb MyCLI run '["--config", "{\"foo\":1}"]'
```

This mode rejects YAML-only syntax and raises `JSON::ParserError` when the payload is invalid, which is handy for callers who want explicit failures instead of silent fallbacks. Programmatically you can call `Rubycli.with_json_mode(true) { … }`.

## Eval mode

Use `--eval-args` (or the shorthand `-e`) to evaluate Ruby expressions before they are forwarded to your CLI. This is handy when you want to pass rich objects that are awkward to express as JSON:

```bash
rubycli -e scripts/data_cli.rb DataCLI run '(1..10).to_a'
```

Under the hood Rubycli evaluates each argument inside an isolated binding (`Object.new.instance_eval { binding }`). Treat this as unsafe input: do not enable it for untrusted callers. The mode can also be toggled programmatically via `Rubycli.with_eval_mode(true) { … }`.

Need Ruby evaluation plus a safety net? Pass `--eval-lax` (or `-E`). It flips on eval mode just like `--eval-args`, but if Ruby fails to parse a token (for example, a bare `https://example.com`), Rubycli emits a warning and forwards the original string unchanged. This lets you mix inline math (`60*60*24*14`) with literal values without constantly juggling quotes.

`--json-args`/`-j` cannot be combined with either `--eval-args`/`-e` or `--eval-lax`/`-E`; Rubycli will raise an error if both are present. Both modes augment the default literal parsing, so you can pick either strict JSON or one of the Ruby eval variants when the defaults are not enough.

## Pre-script bootstrap

Add `--pre-script SRC` (alias: `--init`) when launching the bundled CLI to run arbitrary Ruby code before exposing methods. The code runs inside an isolated binding where the following locals are pre-populated:

- `target` – the original class or module (before `--new` instantiation)
- `current` / `instance` – the object that would otherwise be exposed (after `--new` if specified)

The last evaluated value becomes the new public target. Returning `nil` keeps the previous object.

Inline example:

```bash
rubycli --pre-script 'InitArgRunner.new(source: "cli", retries: 2)' \
  lib/init_arg_runner.rb summarize --verbose
```

File example:

```bash
# scripts/bootstrap_runner.rb
instance = InitArgRunner.new(source: "preset")
instance.logger = Logger.new($stdout)
instance
```

```bash
rubycli --pre-script scripts/bootstrap_runner.rb \
  lib/init_arg_runner.rb summarize --verbose
```

This keeps `--new` available for quick zero-argument instantiation while allowing richer bootstrapping when needed.

## Environment variables & flags

| Flag / Env | Description | Default |
| ---------- | ----------- | ------- |
| `--debug` / `RUBYCLI_DEBUG=true` | Print debug logs | `false` |
| `RUBYCLI_STRICT=ON` | Enable strict mode validation (prints warnings on comment/signature drift) | `OFF` |
| `RUBYCLI_ALLOW_PARAM_COMMENT=OFF` | Disable legacy `@param` lines (defaults to on today for compatibility) | `ON` |

## Library helpers

- `Rubycli.parse_arguments(argv, method)` – parse argv with comment metadata
- `Rubycli.available_commands(target)` – list CLI exposable methods
- `Rubycli.usage_for_method(name, method)` – render usage for a single method
- `Rubycli.method_description(method)` – fetch structured documentation info

Feedback and issues are welcome while we prepare the public release.
