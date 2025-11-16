# Changelog

# Changelog

## [0.1.7] - 2025-11-12

### Added
- `--new` now optionally accepts constructor arguments inline (e.g., `--new=[...]`); YAML/JSON-like literals are safely parsed, and `--json-args` / `--eval-args` / `--eval-lax` still apply. Arrays become positional args, hashes become keyword args.
- Positional argument coercion now runs through the same type-conversion pipeline as options/`--new`, including comment-driven array/element coercion and strict-mode validation; new tests cover arrays, hashes, booleans, and `--new` with JSON/eval modes.

### Changed
- `--new` arguments now flow through the same type-coercion pipeline as regular CLI arguments (including comment-driven type hints) before being passed to `initialize`.

## [0.1.6] - 2025-11-11

### Changed
- `rubycli --check` now reports unknown type tokens and enumerated allowed values (with DidYouMean suggestions) instead of silently treating them as strings, while `--strict` continues to enforce the surviving annotations at runtime.

## [0.1.5] - 2025-11-10

### Added
- `rubycli --check` gained a short `-c` alias and refuses to run target commands while linting, making documentation checks easier to script.
- Bundled `examples/strict_choices_demo.rb` and `examples/typed_arguments_demo.rb` now illustrate literal choice validation and stdlib type coercions.

### Changed
- Runtime validation now reads the documented literal choices and inferred types for both positional and keyword arguments; invalid values emit `[WARN] …` guidance by default and raise `Rubycli::ArgumentError` under `--strict` with friendly suggestions.
- Help output renders positional arguments and options as structured tables showing requirement level, types, defaults, and descriptions for quicker scanning.
- Documentation comments are aligned with the actual method signature, and mismatches surface with file/line context during `rubycli --check`.
- CLI warnings/errors are prefixed with `[WARN]` / `[ERROR]`, and the deprecated `--debug` flag was removed in favor of `RUBYCLI_DEBUG=true`.

### Fixed
- `--check` now rejects forwarded CLI arguments as well as JSON/Eval modes, ensuring documentation linting never executes user code and always starts from a clean issue list.
- Placeholder parsing keeps option descriptions such as `--prefix` in the documentation showcase so README snippets and live behavior stay in sync.

## [0.1.4] - 2025-11-08

### Changed
- Re-cut the release that was briefly published as 0.1.3 (and yanked) so RubyGems now hosts the complete set of changes listed below.

> _Note:_ 0.1.3 was yanked before general availability; consumers should upgrade directly to 0.1.4.

### Documentation
- Clarified repeated-value guidance (type enforcement, eval mode workflows) and updated both READMEs to reflect the retirement of `(type: …)` annotations while preserving the historical changelog entry.

## [0.1.3] - 2025-11-08

### Added
- TracePoint-backed constant capture so Rubycli can detect CLI classes/modules even when they are defined indirectly; bundled example and tests illustrate the behavior.
- Strict/auto constant selection modes with the new `--auto-target` / `-a` flag so single callable constants are picked automatically when requested.
- `--eval-lax` / `-E` argument mode that evaluates Ruby inputs but gracefully falls back to raw strings on parse failures.

### Changed
- Argument parsing internals were modularized so JSON/eval coercion now flows through a dedicated controller, simplifying future extensions.
- `rubycli` now returns explicit status codes for success and failure, improving scriptability.
- CLI constant selection errors provide clearer guidance, document the `--new` behavior, and consistently refer to the `--auto-target` flag.

### Documentation
- Clarified the authoritative source for documentation comments, reorganized helper logic in the showcase example, and expanded guidance around constant modes.

### Fixed
- CLI no longer dumps a Ruby backtrace when `Rubycli::Runner` reports user-facing errors; only the curated guidance is shown.

## [0.1.2] - 2025-11-06

### Added
- Example `examples/documentation_style_showcase.rb` covering all supported documentation notations.
- Parenthesised `(Type)` and `(type: Type)` annotations for positional and option documentation.

### Documentation
- Linked the showcase example from the English and Japanese READMEs to highlight the new syntax.
- Clarified that optional arguments do not require brackets in comments and noted the current comma-delimited behaviour for repeated values.
- Documented the refined literal parsing guard rails so only structured values auto-coerce while plain strings stay untouched unless type hints request otherwise.

### Fixed
- Restored uppercase positional placeholders in the generated help output so the default style stays consistent.
- Help renderer now preserves documented placeholder casing instead of wrapping everything in `<...>`.
- Default literal parsing now skips generic strings to avoid collapsing comma-separated inputs, while still supporting array coercion when documentation specifies list types.

## [0.1.1] - 2025-11-01

### Added
- Initial public release of Rubycli with the `rubycli` executable for running documented Ruby classes and modules.
- Documentation-driven argument parsing with strict mode validation, JSON coercion, and optional eval hooks.
- English and Japanese README guides outlining installation, quick start, and project philosophy ahead of the RubyGems publish.
