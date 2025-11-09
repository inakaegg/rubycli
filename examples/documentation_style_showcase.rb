# frozen_string_literal: true

# Compact examples that highlight how Rubycli parses different documentation styles.
module DocumentationStyleShowcase
  module_function

  # Canonical uppercase placeholders covering required, optional, and repeated forms.
  #
  # NAME [String] Name to display
  # COUNT [Integer] Repetition count
  # --prefix PREFIX [String] Descriptor printed before the subject
  # --tags TAG... [String[]] Comma-separated or JSON list of tags (repeatable)
  # --quiet [Boolean] Suppress the trailing newline marker
  def canonical(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:canonical, subject, count, prefix, tags, quiet)
  end

  # Minimal uppercase form – same signature, but placeholders omit type hints entirely.
  #
  # NAME Name to display
  # COUNT Repetition count
  # --prefix PREFIX Descriptor printed before the subject
  # --tags TAG... JSON/YAML array or comma-separated list
  # --quiet
  def canonical_min(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:canonical_min, subject, count, prefix, tags, quiet)
  end

  # Angle-bracket placeholders with parenthesized type hints.
  # <subject> [String] Subject text to render
  # <count> [Integer] Repetition count
  # --prefix=<prefix> [String] Prefix that appears before the subject
  # --tags <tag>... [String[]] JSON/YAML array or comma-separated tags (repeatable)
  # --quiet [Boolean] Suppress the trailing newline marker
  def angled(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:angled, subject, count, prefix, tags, quiet)
  end

  # Minimal angle-bracket form without explicit types.
  #
  # <subject> Subject text to render
  # <count> Repetition count
  # --prefix=<prefix> Prefix shown before the subject
  # --tags <tag>... JSON/YAML array or comma-separated list
  # --quiet
  def angled_min(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:angled_min, subject, count, prefix, tags, quiet)
  end

  # Bracketed type hints combined with ellipsis for repeated values.
  #
  # <subject> [String] Subject identifier to capture
  # <count> [Integer, nil] Repetition count (accepts nil)
  # prefix [String, nil] Heading for the entry
  # --tags <tag>... [String[]] JSON/YAML array or comma-separated tags (repeatable)
  # --quiet [Boolean] Suppress the trailing newline marker
  # => [Hash] Summary of captured attributes
  def typed(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:typed, subject, count, prefix, tags, quiet)
  end

  # Minimal typed variant using compact notation.
  #
  # <subject> [String] Subject identifier
  # <count> [Integer] Repetition count
  # prefix [String] Title prefix
  # --tags <tag>... [String[]] JSON/YAML array or comma-separated list
  # --quiet [Boolean]
  def typed_min(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:typed_min, subject, count, prefix, tags, quiet)
  end

  # YARD-style annotations without inline option metadata.
  #
  # @param subject [String] Subject to process
  # @param count [Integer] Number of repetitions when composing the label
  # @param prefix [String, nil] Descriptor printed before the subject
  # @param tags [Array<String>, nil] Additional tags (JSON/YAML array or comma-separated, repeatable)
  # @param quiet [Boolean] Suppress the trailing newline marker
  # @return [Hash] Normalized configuration summary
  def yard(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:yard, subject, count, prefix, tags, quiet)
  end

  # Minimal YARD-style form with the shortest acceptable annotations.
  #
  # @param subject Subject to process
  # @param count Repetition count
  # @param prefix Descriptor printed before the subject
  # @param tags Tags list (JSON/YAML array or comma-separated)
  # @param quiet Quiet flag
  def yard_min(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:yard_min, subject, count, prefix, tags, quiet)
  end

  class << self
    private

    def build_payload(style, subject, count, prefix, tags, quiet)
      {
        style: style,
        subject: subject,
        count: count,
        prefix: prefix,
        tags: tags,
        quiet: quiet,
      }
    end
  end
end
