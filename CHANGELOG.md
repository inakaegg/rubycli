# Changelog

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
