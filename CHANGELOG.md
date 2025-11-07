# Changelog

## [0.1.4] - 2025-11-08

### Changed
- Re-cut the release that was briefly published as 0.1.3 (and yanked) so RubyGems now hosts the complete set of changes listed below.

> _Note:_ 0.1.3 was yanked before general availability; consumers should upgrade directly to 0.1.4.

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
