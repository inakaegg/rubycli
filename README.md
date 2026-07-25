# Rubycli — Python Fire-inspired CLI for Ruby

![Rubycli logo](assets/rubycli-logo.png)

[![Gem Version](https://img.shields.io/gem/v/rubycli)](https://rubygems.org/gems/rubycli)

Rubycli turns existing Ruby classes and modules into command-line interfaces.
It inspects public method definitions and the doc comments attached to them, so
in the simplest case your script needs no changes at all — not even
`require "rubycli"`. Type annotations in comments are not just documentation:
they drive how CLI arguments are parsed (for example, `TAG... [String[]]`
forces array parsing).

Rubycli is inspired by [Python Fire](https://github.com/google/python-fire) but
is not a port or an official project; the focus is Ruby's documentation
conventions and type annotations.

> 🇯🇵 Japanese documentation: [README.ja.md](README.ja.md)

![Rubycli demo showing generated commands and invocation](assets/rubycli-demo.gif)

## Installation

```bash
gem install rubycli
```

```ruby
# Gemfile
gem "rubycli"
```

Requires Ruby 3.0 or later. Licensed under [MIT](LICENSE).

## Quick start

### 1. Run an existing script as-is

```ruby
# hello_app.rb
module HelloApp
  module_function

  def greet(name)
    puts "Hello, #{name}!"
  end
end
```

This repository ships the same file as `examples/hello_app.rb`, so you can try
everything below from the project root.

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

Missing arguments produce a usage message instead of a stack trace:

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

`rubycli examples/hello_app.rb --help` prints the same summary as invoking it
without a command.

### 2. Add doc comments for typed options

Still no `require "rubycli"` needed; comments alone drive option parsing and
help text. Both the concise placeholder style and YARD-style tags work:

```ruby
# Concise placeholder style
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

```ruby
# YARD-style tags
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

The documented variant lives at `examples/hello_app_with_docs.rb`. Its file
name does not match the constant it defines (`HelloApp`), so pass
`--auto-target` / `-a` or name the constant explicitly — see
[Target constant resolution](#target-constant-resolution) below.

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

To keep a helper off the CLI, define it as `private` on the singleton class:

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

### 3. Optional: embed the runner in your script

If you prefer launching via plain `ruby`, require the gem and delegate to
`Rubycli.run` (shipped as `examples/hello_app_with_require.rb`):

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

```bash
ruby examples/hello_app_with_require.rb greet Taro --shout
#=> HELLO, TARO!
```

When you run a file through the bundled `rubycli` executable instead, return
values are printed automatically.

## Target constant resolution

Rubycli assumes that the file name (CamelCased) matches the class or module you
want to expose. When it does not, choose how eagerly Rubycli should pick a
constant:

| Mode | How to enable | Behaviour |
| --- | --- | --- |
| `strict` (default) | nothing / `RUBYCLI_AUTO_TARGET=strict` | Fails unless the CamelCase name matches. The error lists the detected constants and shows how to rerun. |
| `auto` | `--auto-target` / `-a` / `RUBYCLI_AUTO_TARGET=auto` | If exactly one constant in the file defines CLI-callable methods, it is selected automatically. |

You can always name the constant explicitly after the file path — useful when a
file defines several candidates or a nested constant:

```bash
rubycli scripts/multi_runner.rb Admin::Runner list --active
```

Nested constants such as `Module1::Inner::Runner` are found as well.

## Instance-only classes and `--new`

If a class only defines public *instance* methods, run Rubycli with `--new` so
the class is instantiated before commands are resolved; otherwise Rubycli sees
no CLI-callable methods.

- `--new` also makes instance methods appear in `--help` output, and lets
  `rubycli --check --new` lint their documentation.
- When the constructor needs arguments, pass them with `--new=VALUE` **before
  the file path**. Values are parsed as safe YAML/JSON-like literals, and
  comments on `initialize` drive type coercion just like regular CLI methods.
- Prefer the `--new=VALUE` form over a space-separated `--new VALUE`, so the
  value is not mistaken for the file path.

Example (`examples/new_mode_runner.rb`):

```bash
rubycli --new='["a","b","c"]' examples/new_mode_runner.rb run --mode reverse
#=> ["c", "b", "a"]
```

## Comment syntax

Rubycli parses a hybrid format — familiar YARD tags or short forms:

| Purpose | YARD-compatible | Rubycli style |
| ------- | --------------- | ------------- |
| Positional argument | `@param name [Type] Description` | `NAME [Type] Description` |
| Keyword option | same | `--flag -f VALUE [Type] Description` |
| Return value | `@return [Type] Description` | `=> [Type] Description` |

Short options are optional and order-independent; these are equivalent:

- `--flag -f VALUE [Type] Description`
- `--flag VALUE [Type] Description`
- `-f --flag VALUE [Type] Description`

Types can be written as `[String]` or `(String)`, and unions as
`(String, nil)`.

### Alternate placeholder notations

These are understood both when parsing comments and when rendering help:

- Angle brackets: `--flag <value>`, `NAME [<value>]`
- Inline equals: `--flag=<value>`
- Trailing ellipsis for repeated values: `VALUE...`, `<value>...`

At runtime `--flag VALUE`, `--flag <value>`, and `--flag=<value>` are
identical — document with whichever variant your team prefers. You do not need
to bracket optional arguments yourself: Rubycli already knows which parameters
are optional from the Ruby signature and adds the brackets in generated help.

Inference rules when annotations are partial:

- A bare placeholder such as `ARG1` (no type) is treated as `String`.
- An option with no value placeholder (`--verbose`) becomes a Boolean flag.
- Positional arguments only become booleans with an explicit `[Boolean]`;
  a bare `NAME Description` falls back to `String` regardless of the Ruby
  default value.

### Arrays and repeated values

Options documented with an ellipsis (`TAG...`) or an array type
(`[String[]]`, `Array<String>`) are parsed as arrays. Both JSON/YAML list
syntax (`--tags '["build","test"]'`) and comma-delimited strings
(`--tags "build,test"`) are accepted. Space-separated multi-value flags
(`--tags build test`) are not supported, and options without a repeated/array
hint stay scalars. `--strict` verifies each element against the documented
type, so `--tags [1,2]` fails when the docs say `[String[]]`.

### Literal choices and enums

A finite set of accepted values can be written directly inside the type
annotation: `--format MODE [:json, :yaml, :auto]` or `LEVEL [:info, :warn]`.
Symbols, strings (including barewords), booleans, numbers, and `nil` are
supported; literals can be mixed with broader types
(`--channel TARGET [:stdout, :stderr, Boolean]`), and `%i[info warn]` /
`%w[debug info]` shorthands expand as expected. The choices always appear in
generated help; without `--strict` an out-of-range value only prints a warning,
with `--strict` it aborts.

Symbols and strings are compared strictly: `[:info, :warn]` requires symbol
input such as `:info` (prefix the value with `:` at the CLI), while
`["info", "warn"]` only accepts plain strings.

```bash
# see examples/strict_choices_demo.rb — LEVEL is documented as [:info, :warn, :error]
rubycli examples/strict_choices_demo.rb report :warn --format json
#=> [WARN] format=json   (followed by the returned hash)

# a plain string is not the documented symbol: warn and continue
rubycli examples/strict_choices_demo.rb report warn
#=> [WARN] LEVEL must be one of :info, :warn, :error (received "warn") (use --strict to abort on invalid input)

# with --strict, out-of-range input aborts
rubycli --strict examples/strict_choices_demo.rb report debug
#=> [ERROR] LEVEL must be one of :info, :warn, :error (received "debug")
```

Literal enums currently apply to each scalar argument; combined literal arrays
such as `[%i[foo bar][]]` are not supported.

### Standard library type hints

Doc comments can reference standard classes such as `Date`, `Time`,
`BigDecimal`, or `Pathname`. Rubycli loads the required stdlib on demand and
coerces CLI inputs, so the handler receives real objects without manual
parsing:

```bash
# see examples/typed_arguments_demo.rb
rubycli examples/typed_arguments_demo.rb ingest \
  --date 2024-12-25 \
  --moment 2024-12-25T10:00:00Z \
  --budget 123.45 \
  --input ./data/input.csv
```

Every option there has a default, so you can also experiment one at a time
(`... ingest --budget 999.99`).

Other YARD tags such as `@example`, `@raise`, `@see`, and `@deprecated` are
currently ignored by the help renderer.

> To explore every notation in one script, try
> `rubycli examples/documentation_style_showcase.rb canonical --help` and the
> other showcase commands.

### Notes on YARD-style comments

- Methods that accept `**kwargs` do not expose those keys automatically; every
  key you want on the CLI needs its own `--long-name PLACEHOLDER [Type] ...`
  line.
- Bullet lists or free-form lines following a `@param` line are not used for
  CLI generation; put supplementary text in the option's description instead.
- To enforce the concise placeholder syntax exclusively, set
  `RUBYCLI_ALLOW_PARAM_COMMENT=OFF`; `@param`/`@return` tags then produce
  warnings, which helps a gradual migration.

### When docs are missing or incomplete

Rubycli always trusts the live method signature. Undocumented parameters are
still exposed, with names, defaults, and types inferred from the definition:

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

Only `AMOUNT` is documented, yet `factor`, `clamp`, and `notify` are presented
with inferred defaults and types.

Comments never add live parameters by themselves. Lines that reference
non-existent options (say `--ghost`) or positionals are shown verbatim in the
help's detail section instead of becoming real arguments, and strict mode warns
about positional mismatches. For a runnable mismatch demo:
`rubycli examples/fallback_example_with_extra_docs.rb scale --help`.

Run `rubycli --check path/to/script.rb` during development to lint
documentation drift — including undefined type labels and enum typos, with
DidYouMean suggestions — and pass `--strict` at runtime when invalid input
should abort instead of merely warning.

> `--strict` trusts whatever types/choices your comments spell out. Keep
> `rubycli --check` in CI so documentation typos are caught before production
> runs that rely on `--strict`.

## Argument parsing modes

### Default literal parsing

Arguments that look like structured literals (starting with `{`, `[`, quotes,
or YAML markers) are parsed with `Psych.safe_load`, so
`--names='["Alice","Bob"]'` or `--config='{foo: 1}'` arrive as native arrays
and hashes without extra flags. Plain strings like `1,2,3` stay untouched at
this stage (a later pass normalises them into arrays when the docs declare
`String[]` or `TAG...`), and unsupported constructs fall back to the original
text, so `"2024-01-01"` remains a string and malformed payloads still reach
your method instead of killing the run.

### JSON mode (`--json-args` / `-j`)

Parses subsequent arguments strictly as JSON. YAML-only syntax is rejected and
invalid payloads raise `JSON::ParserError` — for callers who want explicit
failures instead of silent fallbacks. Programmatic equivalent:
`Rubycli.with_json_mode(true) { ... }`.

### Eval mode (`--eval-args` / `-e`, `--eval-lax` / `-E`)

Evaluates each argument as a Ruby expression before it is forwarded, which is
handy for objects that are awkward as JSON — symbol arrays, ranges, inline
math:

```bash
rubycli -E scripts/report_runner.rb publish \
  --targets '[:marketing, :sales]' \
  --channels '[:email, :slack]'
```

Evaluation happens inside an isolated binding
(`Object.new.instance_eval { binding }`). Treat this as unsafe input: do not
enable it for untrusted callers. Programmatic equivalent:
`Rubycli.with_eval_mode(true) { ... }`.

`--eval-lax` / `-E` behaves like `--eval-args`, but tokens that fail to parse
as Ruby (for example a bare `https://example.com`) produce a warning and are
forwarded as the original string — convenient for mixing expressions like
`60*60*24*14` with plain values.

`--json-args` cannot be combined with either eval variant; Rubycli raises an
error if both are present.

## Pre-script bootstrap

`--pre-script SRC` (alias: `--init`) runs arbitrary Ruby before commands are
resolved, inside an isolated binding with these locals pre-populated:

- `target` — the original class or module (before `--new` instantiation)
- `current` / `instance` — the object that would otherwise be exposed

The last evaluated value becomes the new public target (`nil` keeps the
previous object). `SRC` can be inline Ruby or a file path.

Example — replace the `--new`-built instance with a hand-built one:

```bash
rubycli --new='["a"]' \
  --pre-script 'NewModeRunner.new(%w[a b c], options: {from: :pre})' \
  examples/new_mode_runner.rb run --mode summary
```

## Flags and environment variables

| Flag / Env | Description | Default |
| ---------- | ----------- | ------- |
| `--auto-target` / `-a`, `RUBYCLI_AUTO_TARGET=auto` | Auto-select the target constant when the file name does not match | `strict` |
| `--new[=VALUE]` | Instantiate the class before resolving commands; `VALUE` feeds the constructor | off |
| `--pre-script SRC` / `--init SRC` | Run Ruby code to build/replace the exposed object | off |
| `--check` | Lint documentation/comments without executing commands | off |
| `--strict` | Enforce documented types/choices; invalid input aborts | off |
| `--json-args` / `-j` | Parse arguments strictly as JSON | off |
| `--eval-args` / `-e`, `--eval-lax` / `-E` | Evaluate arguments as Ruby (lax: fall back to the raw string) | off |
| `RUBYCLI_DEBUG=true` | Print debug logs | `false` |
| `RUBYCLI_ALLOW_PARAM_COMMENT=OFF` | Disable YARD `@param` lines (on by default for compatibility) | `ON` |

## Library helpers

- `Rubycli.parse_arguments(argv, method)` — parse argv with comment metadata
- `Rubycli.available_commands(target)` — list CLI-exposable methods
- `Rubycli.usage_for_method(name, method)` — render usage for a single method
- `Rubycli.method_description(method)` — fetch structured documentation info

## How it differs from Python Fire

- **Comment-aware help** — doc comments enrich the help, but the live method
  signature stays the ultimate authority.
- **Type-aware parsing** — placeholder syntax and YARD tags coerce arguments to
  booleans, arrays, numerics, and more without additional code.
- **Two-stage validation** — `--check` lints documentation drift without
  executing commands; `--strict` turns documented types/choices into
  enforceable runtime contracts.
- **Ruby-centric** — keyword arguments, block documentation (`@yield*` tags),
  and `RUBYCLI_*` environment toggles.

| Capability | Python Fire | Rubycli |
| ---------- | ----------- | ------- |
| Attribute traversal | Recursively exposes attributes/properties | Exposes public methods on the target; no implicit traversal |
| Constructor handling | Prompts for `__init__` args automatically | `--new` instantiates; constructor args via `--new=VALUE`, richer wiring via pre-scripts |
| Interactive shell | Fire-specific REPL when invoked without a command | No interactive shell; strictly command execution |
| Input discovery | Pure reflection, no doc comments | Doc comments drive option names, placeholders, and validation |
| Data structures | Dicts/lists become subcommands | Class/module methods only; no automatic dict/list expansion |

## Project philosophy

- **Convenience first** — wrap existing Ruby scripts with almost no manual
  plumbing. Fidelity with Python Fire is not a goal; missing Fire features are
  generally by design.
- **Method definitions first, comments augment** — signatures determine what is
  exposed and what is required; comments refine types, help text, and
  validation.
- **Lightweight maintenance** — much of the implementation was generated with
  AI assistance; contributions that dive into deep Ruby metaprogramming are out
  of scope. Please discuss expectations before opening parity PRs.

## Bundled examples

- `examples/hello_app.rb` / `examples/hello_app_with_docs.rb` — minimal
  module-function variants, without and with docs
- `examples/hello_app_with_require.rb` — embedded `Rubycli.run`
- `examples/typed_arguments_demo.rb` — stdlib type coercions
  (Date/Time/BigDecimal/Pathname)
- `examples/strict_choices_demo.rb` — literal enumerations and `--strict`
- `examples/new_mode_runner.rb` — instance-only class initialized via
  `--new=VALUE`
- `examples/documentation_style_showcase.rb` — every comment notation in one
  script
- `examples/fallback_example.rb` / `examples/fallback_example_with_extra_docs.rb`
  — signature fallback and doc-mismatch demos

## License

MIT. See [LICENSE](LICENSE).

Feedback and issues are welcome.
