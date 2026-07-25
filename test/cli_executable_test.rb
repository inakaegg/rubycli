# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'rbconfig'

# End-to-end coverage for the shipped executable: the other CLI tests stub the
# runner, so these run `exe/rubycli` in a subprocess and check what a user sees.
class CLIExecutableTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  EXECUTABLE = File.join(ROOT, 'exe', 'rubycli')

  def test_without_arguments_prints_usage_and_fails
    out, err, status = run_cli

    assert_equal 1, status
    assert_includes out, 'Usage: rubycli'
    assert_empty err
  end

  def test_help_flag_prints_usage_and_succeeds
    out, _err, status = run_cli('--help')

    assert_equal 0, status
    assert_includes out, 'Usage: rubycli'
    assert_includes out, '--auto-target, -a'
  end

  def test_runs_a_documented_command
    out, err, status = run_cli('examples/hello_app.rb', 'greet', 'Hanako')

    assert_equal 0, status
    assert_equal "Hello, Hanako!\n", out
    assert_empty err
  end

  def test_missing_positional_argument_reports_usage_instead_of_a_backtrace
    out, _err, status = run_cli('examples/hello_app.rb', 'greet')

    assert_equal 1, status
    assert_includes out, 'wrong number of arguments'
    assert_includes out, 'Usage: hello_app.rb greet NAME'
    refute_includes out, 'lib/rubycli'
  end

  def test_prints_return_values_as_json
    out, _err, status = run_cli('--new=["a","b","c"]', 'examples/new_mode_runner.rb', 'run', '--mode', 'reverse')

    assert_equal 0, status
    assert_equal %w[c b a], JSON.parse(out)
  end

  def test_check_succeeds_for_documented_example
    out, _err, status = run_cli('--check', 'examples/hello_app.rb')

    assert_equal 0, status
    assert_includes out, 'rubycli documentation OK'
  end

  def test_check_fails_and_reports_issues_for_undocumented_parameters
    _out, err, status = run_cli('--check', 'examples/fallback_example.rb')

    assert_equal 1, status
    assert_includes err, 'rubycli documentation check failed'
  end

  def test_strict_mode_aborts_on_values_outside_documented_choices
    _out, err, status = run_cli('--strict', 'examples/strict_choices_demo.rb', 'report', 'debug')

    assert_equal 1, status
    assert_includes err, '[ERROR] LEVEL must be one of :info, :warn, :error'
  end

  def test_missing_target_file_reports_a_user_facing_error
    _out, err, status = run_cli('missing_file.rb')

    assert_equal 1, status
    assert_includes err, '[ERROR] File not found: missing_file.rb'
    refute_includes err, 'lib/rubycli'
  end

  def test_conflicting_argument_modes_are_rejected
    _out, err, status = run_cli('--json-args', '--eval-args', 'examples/hello_app.rb', 'greet', 'x')

    assert_equal 1, status
    assert_includes err, '--json-args cannot be combined with --eval-args'
  end

  private

  def run_cli(*args)
    out, err, status = Open3.capture3(
      RbConfig.ruby, '-I', File.join(ROOT, 'lib'), EXECUTABLE, *args, chdir: ROOT
    )
    [out, err, status.exitstatus]
  end
end
