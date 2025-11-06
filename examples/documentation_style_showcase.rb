# frozen_string_literal: true

# Compact examples that highlight how Rubycli parses different documentation styles.
module DocumentationStyleShowcase
  module_function

  # Canonical uppercase placeholders covering required, optional, and repeated forms.
  #
  # NAME [String] Name to display
  # COUNT [Integer] Optional repetition count
  # --prefix PREFIX [String] Optional descriptor printed before the subject
  # --tags TAG... [String] Comma-separated or JSON list of tags (repeatable)
  # --quiet [Boolean] Suppress the trailing newline marker
  def canonical(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:canonical, subject, count, prefix, tags, quiet)
  end

  # Minimal uppercase form – same signature, but placeholders omit type hints entirely.
  #
  # NAME Name to display
  # COUNT Optional repetition count
  # --prefix PREFIX Optional descriptor
  # --tags TAG... (JSON/YAML array or comma-separated)
  # --quiet
  def canonical_min(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:canonical_min, subject, count, prefix, tags, quiet)
  end

  # Angle-bracket placeholders with parenthesized type hints.
  # <subject> [String] Subject text to render
  # <count> [Integer] Optional repetition count
  # --prefix=<prefix> [String] Optional prefix that appears before the subject
  # --tags <tag>... [String[]] JSON/YAML array or comma-separated tags (repeatable)
  # --quiet [Boolean] Suppress the trailing newline marker
  def angled(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:angled, subject, count, prefix, tags, quiet)
  end

  # Minimal angle-bracket form without explicit types.
  #
  # <subject> Subject text to render
  # <count> Optional repetition count
  # --prefix=<prefix> Optional prefix
  # --tags <tag>... (JSON/YAML array or comma-separated)
  # --quiet
  def angled_min(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:angled_min, subject, count, prefix, tags, quiet)
  end

  # type: prefixes and repeated values with ellipsis.
  #
  # <subject> [String] Subject identifier to capture
  # <count> [Integer, nil] Optional repetition count
  # title [String, nil] Optional heading for the entry
  # --tags <tag>... [String[]] JSON/YAML array or comma-separated tags (repeatable)
  # --quiet [Boolean] Suppress the trailing newline marker
  # => [Hash] Summary of captured attributes
  def typed(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:typed, subject, count, prefix, tags, quiet)
  end

  # Minimal type: variant using compact notation.
  #
  # <subject> [String] Subject identifier
  # <count> [Integer] Optional repetition count
  # title [String] Optional title
  # --tags <tag>... [String[]] (JSON/YAML array or comma-separated)
  # --quiet [Boolean]
  def typed_min(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:typed_min, subject, count, prefix, tags, quiet)
  end

  # YARD-style annotations without inline option metadata.
  #
  # @param subject [String] Subject to process
  # @param count [Integer] Number of repetitions when composing the label
  # @param prefix [String, nil] Optional descriptor printed before the subject
  # @param tags [Array<String>, nil] Additional tags (JSON/YAML array or comma-separated, repeatable)
  # @param quiet [Boolean] Suppress the trailing newline marker
  # @return [Hash] Normalized configuration summary
  def yard(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:yard, subject, count, prefix, tags, quiet)
  end

  # Minimal YARD-style form with the shortest acceptable annotations.
  #
  # @param subject Subject to process
  # @param count Optional repetitions
  # @param prefix Optional descriptor
  # @param tags Tags list (JSON/YAML array or comma-separated)
  # @param quiet Quiet flag
  def yard_min(subject, count = 1, prefix: nil, tags: nil, quiet: false)
    build_payload(:yard_min, subject, count, prefix, tags, quiet)
  end

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

module DocumentationStyleShowcase
  module_function :canonical,
                  :canonical_min,
                  :angled,
                  :angled_min,
                  :typed,
                  :typed_min,
                  :yard,
                  :yard_min
  private :build_payload
end
