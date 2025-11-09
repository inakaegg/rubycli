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

  def test_doc_check_and_param_comment_flags_respect_environment
    env = Rubycli::Environment.new(
      env: {
        'RUBYCLI_ALLOW_PARAM_COMMENT' => 'off'
      }
    )

    refute env.doc_check_mode?
    refute env.allow_param_comments?
    env.enable_doc_check!
    assert env.doc_check_mode?
  end

  def test_handle_documentation_issue_includes_location_when_doc_check_enabled
    env = Rubycli::Environment.new
    env.enable_doc_check!
    file = File.expand_path('test/fixtures/doc_examples.rb')

    _out, err = capture_io do
      env.handle_documentation_issue('Missing docs', file: file, line: 12)
    end

    assert_includes err, '[WARN] Rubycli documentation mismatch'
    assert_includes err, 'Missing docs'
    assert_includes err, 'doc_examples.rb:12'
  end

  def test_handle_input_violation_warns_by_default
    env = Rubycli::Environment.new
    _out, err = capture_io do
      env.handle_input_violation('Value invalid')
    end
    assert_includes err, 'Value invalid'
    assert_includes err, '--strict'
  end

  def test_handle_input_violation_raises_when_strict_input_enabled
    env = Rubycli::Environment.new
    env.enable_strict_input!

    assert_raises(Rubycli::ArgumentError) do
      env.handle_input_violation('bad')
    end
  end
end
