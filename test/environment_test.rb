# frozen_string_literal: true

require 'test_helper'

class EnvironmentTest < Minitest::Test
  def test_debug_and_print_flags_are_enabled_and_removed_from_argv
    argv = ['--debug', 'run', '--print-result', '--debug']
    env = Rubycli::Environment.new(env: {}, argv: argv)

    assert env.debug?, 'debug flag should be enabled'
    assert env.print_result?, 'print-result flag should be enabled'
    refute_includes argv, '--debug'
    refute_includes argv, '--print-result'
    assert_equal %w[run], argv
  end

  def test_strict_mode_and_param_comment_flags_respect_environment
    env = Rubycli::Environment.new(
      env: {
        'RUBYCLI_STRICT' => 'ON',
        'RUBYCLI_ALLOW_PARAM_COMMENT' => 'off'
      }
    )

    assert env.strict_mode?
    refute env.allow_param_comments?
  end

  def test_handle_documentation_issue_includes_location_when_strict
    env = Rubycli::Environment.new(env: { 'RUBYCLI_STRICT' => 'true' })
    file = File.expand_path('test/fixtures/doc_examples.rb')

    _out, err = capture_io do
      env.handle_documentation_issue('Missing docs', file: file, line: 12)
    end

    assert_includes err, '[WARN] Rubycli documentation mismatch'
    assert_includes err, 'Missing docs'
    assert_includes err, 'doc_examples.rb:12'
  end
end
