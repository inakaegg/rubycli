# frozen_string_literal: true

require 'test_helper'

module HelpEnumSamples
  module_function

  # LEVEL [:info, :warn, :error] Severity
  # --format TARGET ["text", "json"] Output channel
  def report(level, format: 'text'); end
end

class HelpRendererTest < Minitest::Test
  def setup
    environment = Rubycli::Environment.new(env: {}, argv: [])
    @registry = Rubycli::DocumentationRegistry.new(environment: environment)
    @renderer = Rubycli::HelpRenderer.new(documentation_registry: @registry)
    @original_program_name = $PROGRAM_NAME
    $PROGRAM_NAME = 'rubycli'
  end

  def teardown
    $PROGRAM_NAME = @original_program_name
  end

  def test_usage_renders_tagged_documentation
    method = DocExamples::TaggedSamples.new.method(:greet)
    usage = @renderer.usage_for_method('greet', method)

    expected = <<~HELP.strip
      Compose a friendly greeting.

      Supports both positional and keyword documentation using YARD tags.

      Usage: rubycli greet NAME [-g, --greeting=<GREETING>] [-s, --shout] [--punctuation=<PUNCT>]

      Positional arguments:
        NAME  [String]  required  Person to greet

      Options:
        -g, --greeting=<GREETING>  [String]       optional  Greeting prefix (default: 'Hello')
        -s, --shout                [Boolean]      optional  Emit uppercase output (default: false)
        --punctuation=<PUNCT>      [nil, String]  optional  Optional punctuation suffix (default: nil)

      Return values:
        String  Finalised greeting
    HELP

    assert_usage(expected, usage)
  end

  def test_usage_for_incomplete_docs_has_fallbacks
    method = DocExamples::IncompleteDocs.new.method(:fallback)
    usage = @renderer.usage_for_method('fallback', method)

    expected = <<~HELP.strip
      Deliberately underspecified to exercise fallbacks.

      Usage: rubycli fallback NAME [ATTEMPTS] [--safe-mode] [--tag=<TAG>]

      Positional arguments:
        NAME      [String]  required
        ATTEMPTS  [String]  optional  (default: 3)

      Options:
        --safe-mode  [Boolean]  optional  (default: true)
        --tag=<TAG>  [String]   optional  (default: nil)
    HELP

    assert_usage(expected, usage)
  end

  def test_method_description_uses_summary_when_present
    method = DocExamples::ConciseSamples.new.method(:toggle)
    description = @renderer.method_description(method)
    assert_equal 'Toggle settings using boolean and optional value options.', description
  end

  def test_method_description_falls_back_to_signature
    method = DocExamples::TaggedSamples.new.method(:process)
    description = @renderer.method_description(method)
    assert_equal 'JSON [-v, --verbose]', description
  end

  def test_method_description_preserves_documented_placeholders
    method = DocExamples::TypeHintSamples.new.method(:analyse)
    description = @renderer.method_description(method)
    assert_equal '<file> [<pattern>] [--format=<format>] [--tags=<tag>...]', description
  end

  def test_literal_choices_render_in_help_tables
    method = HelpEnumSamples.method(:report)
    usage = @renderer.usage_for_method('report', method)
    assert_includes usage, 'LEVEL  [:info, :warn, :error]'
    assert_includes usage, '--format=<TARGET>  ["text", "json"]'
  end

  private

  def assert_usage(expected, actual)
    expected_lines = expected.split("\n").map(&:rstrip)
    actual_lines = actual.split("\n").map(&:rstrip)
    assert_equal expected_lines, actual_lines
  end
end
