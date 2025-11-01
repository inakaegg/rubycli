# frozen_string_literal: true

require 'test_helper'

class CommandLineTest < Minitest::Test
  def test_returns_usage_when_no_arguments
    status = nil
    out, err = capture_io do
      status = Rubycli::CommandLine.run([])
    end

    assert_equal 1, status
    assert_includes out, 'Usage: rubycli'
    assert_equal '', err
  end

  def test_parses_flags_and_invokes_runner_with_options
    argv = [
      '--new',
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
    assert_equal true, captured[:options][:json]
    assert_equal false, captured[:options][:eval_args]
    assert_equal(
      [{ value: 'instance.new', context: '(inline --pre-script)' }],
      captured[:options][:pre_scripts]
    )
  end

  def test_json_and_eval_flags_conflict_is_reported
    argv = [
      '--json-args',
      '--eval-args',
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
      assert_includes err, '--json-args and --eval-args cannot be used at the same time'
    end
  end
end
