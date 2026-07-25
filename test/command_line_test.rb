# frozen_string_literal: true

require 'test_helper'
require 'tempfile'

class CommandLineTest < Minitest::Test
  def setup
    @previous_print_result = Rubycli.environment.print_result?
  end

  def teardown
    Rubycli.environment.instance_variable_set(:@print_result, @previous_print_result)
  end

  def test_returns_usage_when_no_arguments
    status = nil
    out, err = capture_io do
      status = Rubycli::CommandLine.run([])
    end

    assert_equal 1, status
    assert_includes out, 'Usage: rubycli'
    assert_includes out, 'Arguments are parsed as safe literals by default'
    assert_equal '', err
  end

  def test_parses_flags_and_invokes_runner_with_options
    argv = [
      '--new=["alpha"]',
      '--pre-script=instance.new',
      '--json-args',
      'test/fixtures/doc_examples.rb',
      'DocExamples::ConciseSamples',
      '--',
      'describe',
      'topic',
      '--tags',
      'alpha,beta'
    ]

    captured = nil
    stub = lambda do |target_path, class_name = nil, cli_args = nil, **opts|
      captured = {
        target_path: target_path,
        class_name: class_name,
        cli_args: cli_args,
        options: opts
      }
    end

    status = nil
    Rubycli::Runner.stub(:execute, stub) do
      status = Rubycli::CommandLine.run(argv)
    end

    assert_equal 0, status
    refute_nil captured
    assert_equal 'test/fixtures/doc_examples.rb', captured[:target_path]
    assert_equal 'DocExamples::ConciseSamples', captured[:class_name]
    assert_equal ['describe', 'topic', '--tags', 'alpha,beta'], captured[:cli_args]
    assert_equal true, captured[:options][:new]
    assert_equal '["alpha"]', captured[:options][:new_args]
    assert_equal true, captured[:options][:json]
    assert_equal false, captured[:options][:eval_args]
    assert_equal false, captured[:options][:eval_lax]
    assert_equal(
      [{ value: 'instance.new', context: '(inline --pre-script)' }],
      captured[:options][:pre_scripts]
    )
  end

  def test_json_and_eval_flags_conflict_is_reported
    argv = [
      '-j',
      '-e',
      'test/fixtures/doc_examples.rb',
      'DocExamples::TaggedSamples'
    ]

    Rubycli::Runner.stub(:execute, ->(*) { flunk 'Runner should not be invoked' }) do
      status = nil
      out, err = capture_io do
        status = Rubycli::CommandLine.run(argv)
      end

      assert_equal 1, status
      assert_equal '', out
      assert_includes err, '--json-args cannot be combined with --eval-args or --eval-lax'
    end
  end

  def test_accepts_short_flag_for_json_mode
    argv = [
      '-j',
      'test/fixtures/doc_examples.rb',
      'DocExamples::TaggedSamples'
    ]

    captured = nil
    Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = { args: args, opts: opts } }) do
      status = Rubycli::CommandLine.run(argv)
      assert_equal 0, status
    end

    refute_nil captured
    assert_equal true, captured[:opts][:json]
    assert_equal false, captured[:opts][:eval_args]
  end

  def test_accepts_short_flag_for_eval_mode
    argv = [
      '-e',
      'test/fixtures/doc_examples.rb',
      'DocExamples::TaggedSamples'
    ]

    captured = nil
    Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = { args: args, opts: opts } }) do
      status = Rubycli::CommandLine.run(argv)
      assert_equal 0, status
    end

    refute_nil captured
    assert_equal false, captured[:opts][:json]
    assert_equal true, captured[:opts][:eval_args]
    assert_equal false, captured[:opts][:eval_lax]
  end

  def test_accepts_eval_lax_flag
    argv = [
      '--eval-lax',
      'test/fixtures/doc_examples.rb',
      'DocExamples::TaggedSamples'
    ]

    captured = nil
    Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = { args: args, opts: opts } }) do
      status = Rubycli::CommandLine.run(argv)
      assert_equal 0, status
    end

    refute_nil captured
    assert_equal false, captured[:opts][:json]
    assert_equal true, captured[:opts][:eval_args]
    assert_equal true, captured[:opts][:eval_lax]
  end

  def test_accepts_short_flag_for_eval_lax_mode
    argv = [
      '-E',
      'test/fixtures/doc_examples.rb',
      'DocExamples::TaggedSamples'
    ]

    captured = nil
    Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = { args: args, opts: opts } }) do
      status = Rubycli::CommandLine.run(argv)
      assert_equal 0, status
    end

    refute_nil captured
    assert_equal true, captured[:opts][:eval_args]
    assert_equal true, captured[:opts][:eval_lax]
  end

  def test_accepts_short_flag_for_check_mode
    argv = [
      '-c',
      'test/fixtures/doc_examples.rb'
    ]

    captured = nil
    Rubycli::Runner.stub(:execute, ->(*) { flunk 'Runner.execute should not be invoked for --check' }) do
      Rubycli::Runner.stub(:check, lambda { |*args, **opts|
        captured = { args: args, opts: opts }
        0
      }) do
        status = Rubycli::CommandLine.run(argv)
        assert_equal 0, status
      ensure
        Rubycli.environment.disable_doc_check!
        Rubycli.environment.clear_documentation_issues!
      end
    end

    refute_nil captured
    assert_equal ['test/fixtures/doc_examples.rb', nil], captured[:args]
    assert_equal false, captured[:opts][:new]
  end

  def test_check_mode_does_not_leak_into_a_later_programmatic_run
    argv = ['--check', 'test/fixtures/doc_examples.rb']

    Rubycli::Runner.stub(:check, 0) do
      assert_equal 0, Rubycli::CommandLine.run(argv)
    end

    refute Rubycli.environment.doc_check_mode?
  end

  def test_strict_mode_does_not_leak_into_a_later_programmatic_run
    argv = ['--strict', 'test/fixtures/doc_examples.rb']

    Rubycli::Runner.stub(:execute, nil) do
      assert_equal 0, Rubycli::CommandLine.run(argv)
    end

    refute Rubycli.environment.strict_input?
  end

  def test_print_result_mode_does_not_leak_into_a_later_programmatic_run
    argv = ['test/fixtures/doc_examples.rb']
    Rubycli.environment.instance_variable_set(:@print_result, false)

    Rubycli::Runner.stub(:execute, nil) do
      assert_equal 0, Rubycli::CommandLine.run(argv)
    end

    refute Rubycli.environment.print_result?
  end

  def test_pre_script_allows_space_separated_value
    argv = [
      '--pre-script',
      'instance.new',
      'test/fixtures/doc_examples.rb'
    ]

    captured = nil
    Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = { args: args, opts: opts } }) do
      status = Rubycli::CommandLine.run(argv)
      assert_equal 0, status
    end

    refute_nil captured
    assert_equal 'test/fixtures/doc_examples.rb', captured[:args].first
    assert_equal(
      [{ value: 'instance.new', context: '(inline --pre-script)' }],
      captured[:opts][:pre_scripts]
    )
  end

  def test_debug_flag_is_rejected_with_helpful_message
    argv = [
      '--debug',
      'test/fixtures/doc_examples.rb'
    ]

    Rubycli::Runner.stub(:execute, ->(*) { flunk 'Runner should not be invoked when --debug is rejected' }) do
      status = nil
      out, err = capture_io do
        status = Rubycli::CommandLine.run(argv)
      end

      assert_equal 1, status
      assert_equal '', out
      assert_includes err, 'RUBYCLI_DEBUG=true'
    end
  end

  def test_help_flag_returns_success_without_invoking_runner
    Rubycli::Runner.stub(:execute, ->(*) { flunk 'Runner should not be invoked for help' }) do
      status = nil
      out, err = capture_io do
        status = Rubycli::CommandLine.run(['--help'])
      end

      assert_equal 0, status
      assert_includes out, 'Usage: rubycli'
      assert_equal '', err
    end
  end

  def test_long_new_flag_consumes_a_separate_list_argument
    captured = nil
    argv = ['--new', 'alpha,beta', 'examples/new_mode_runner.rb']

    Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = [args, opts] }) do
      assert_equal 0, Rubycli::CommandLine.run(argv)
    end

    assert_equal 'alpha,beta', captured.last[:new_args]
    assert_equal true, captured.last[:new]
  end

  def test_short_new_flag_without_constructor_value_preserves_target_path
    captured = nil
    argv = ['-n', 'examples/new_mode_runner.rb']

    Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = [args, opts] }) do
      assert_equal 0, Rubycli::CommandLine.run(argv)
    end

    assert_equal 'examples/new_mode_runner.rb', captured.first.first
    assert_nil captured.last[:new_args]
    assert_equal true, captured.last[:new]
  end

  def test_init_alias_records_its_inline_source_context
    captured = nil
    argv = ['--init=current', 'test/fixtures/doc_examples.rb']

    Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = [args, opts] }) do
      assert_equal 0, Rubycli::CommandLine.run(argv)
    end

    assert_equal(
      [{ value: 'current', context: '(inline --init)' }],
      captured.last[:pre_scripts]
    )
  end

  def test_pre_script_without_source_is_rejected
    status = nil
    out, err = capture_io do
      status = Rubycli::CommandLine.run(['--pre-script'])
    end

    assert_equal 1, status
    assert_equal '', out
    assert_includes err, '--pre-script requires a file path or inline Ruby code'
  end

  def test_pre_script_file_records_its_expanded_path
    captured = nil
    Tempfile.create(['rubycli-pre-script', '.rb']) do |file|
      file.write('current')
      file.flush
      argv = ['--pre-script', file.path, 'test/fixtures/doc_examples.rb']

      Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = [args, opts] }) do
        assert_equal 0, Rubycli::CommandLine.run(argv)
      end

      assert_equal File.expand_path(file.path), captured.last[:pre_scripts].first[:context]
    end
  end

  def test_auto_target_and_print_result_flags_are_forwarded_or_consumed
    captured = nil
    argv = ['--print-result', '--auto-target', 'test/fixtures/doc_examples.rb']

    Rubycli::Runner.stub(:execute, ->(*args, **opts) { captured = [args, opts] }) do
      assert_equal 0, Rubycli::CommandLine.run(argv)
    end

    assert_equal :auto, captured.last[:constant_mode]
    assert_empty captured.first[2]
  end

  def test_flags_without_target_print_usage
    status = nil
    out, err = capture_io do
      status = Rubycli::CommandLine.run(['--strict'])
    end

    assert_equal 1, status
    assert_includes out, 'Usage: rubycli'
    assert_equal '', err
  end

  def test_check_rejects_argument_modes_and_forwarded_commands
    [
      [['--check', '--json-args', 'target.rb'], '--check cannot be combined'],
      [['--check', 'target.rb', 'run'], '--check does not accept command arguments']
    ].each do |argv, message|
      status = nil
      _out, err = capture_io do
        status = Rubycli::CommandLine.run(argv)
      end

      assert_equal 1, status
      assert_includes err, message
    end
  end

  def test_runner_errors_are_reported_without_backtrace
    [
      Rubycli::Runner::PreScriptError.new('bad pre-script'),
      Rubycli::Runner::Error.new('bad runner')
    ].each do |runner_error|
      status = nil
      _out, err = capture_io do
        Rubycli::Runner.stub(:execute, ->(*) { raise runner_error }) do
          status = Rubycli::CommandLine.run(['target.rb'])
        end
      end

      assert_equal 1, status
      assert_includes err, runner_error.message
      refute_includes err, 'test/command_line_test.rb'
    end
  end

  def test_preexisting_environment_modes_are_restored
    Rubycli.environment.enable_doc_check!
    Rubycli.environment.enable_strict_input!
    Rubycli.environment.enable_print_result!

    Rubycli::Runner.stub(:execute, nil) do
      assert_equal 0, Rubycli::CommandLine.run(['target.rb'])
    end

    assert Rubycli.environment.doc_check_mode?
    assert Rubycli.environment.strict_input?
    assert Rubycli.environment.print_result?
  ensure
    Rubycli.environment.disable_doc_check!
    Rubycli.environment.disable_strict_input!
    Rubycli.environment.instance_variable_set(:@print_result, @previous_print_result)
  end
end
