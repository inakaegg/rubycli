# frozen_string_literal: true

module DocExamples
  class TaggedSamples
    # Compose a friendly greeting.
    #
    # Supports both positional and keyword documentation using YARD tags.
    #
    # @param name [String] Person to greet
    # @param greeting [String] (--greeting -g GREETING) Greeting prefix
    # @param shout [Boolean] (--shout -s) Emit uppercase output
    # @param punctuation [String, nil] (--punctuation PUNCT) Optional punctuation suffix
    # => [String] Finalised greeting
    def greet(name, greeting: 'Hello', shout: false, punctuation: nil)
      message = "#{greeting}, #{name}"
      message = message.upcase if shout
      punctuation ? "#{message}#{punctuation}" : message
    end

    # @param data [Hash] (--data JSON) Structured payload
    # @param verbose [Boolean] (--verbose -v) Enable verbose mode
    # => [Hash] Normalized data
    def process(data, verbose: false)
      verbose ? data.merge('verbose' => true) : data
    end
  end

  class ConciseSamples
    # Create a descriptor for a subject.
    #
    # SUBJECT [String] Subject to describe
    # COUNT [Integer] Number of repetitions
    # --style -s STYLE [String] Style flag
    # --tags TAGS [Array<String>] Comma-separated tags
    # => [String] Description text
    def describe(subject, count = 1, style: nil, tags: nil)
      base = ([subject] * count).join(' ')
      styled = style ? "[#{style}] #{base}" : base
      tags ? "#{styled} (#{Array(tags).join(', ')})" : styled
    end

    # Toggle settings using boolean and optional value options.
    #
    # TARGET [String] Target identifier
    # --enable [Boolean] Switch on the feature
    # --limit [LIMIT] Integer Optional limit (nil allowed)
    def toggle(target, enable: false, limit: nil)
      { target: target, enabled: enable, limit: limit }
    end
  end

  class IncompleteDocs
    # Deliberately underspecified to exercise fallbacks.
    def fallback(name, attempts = 3, safe_mode: true, tag: nil)
      { name: name, attempts: attempts, safe_mode: safe_mode, tag: tag }
    end
  end
end
