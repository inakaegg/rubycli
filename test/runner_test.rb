# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class RunnerTest < Minitest::Test
  def test_execute_infers_constant_and_instantiates_when_new_flag
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'sample_runner.rb')
      File.write(file, <<~RUBY)
        class SampleRunner
          def hello
            'world'
          end
        end
      RUBY

      captured_target = nil
      original_argv = ARGV.dup
      program_before = $PROGRAM_NAME

      Rubycli.stub(:run, ->(target, *_args) { captured_target = target }) do
        Rubycli::Runner.execute(file, nil, ['hello'], new: true)
      end

      assert_instance_of SampleRunner, captured_target
      assert_equal original_argv, ARGV
      assert_equal program_before, $PROGRAM_NAME
    ensure
      $PROGRAM_NAME = program_before
      ARGV.replace(original_argv)
    end
  end

  def test_new_args_are_forwarded_to_initializer
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'init_runner.rb')
      File.write(file, <<~RUBY)
        class InitRunner
          attr_reader :args, :kwargs

          def initialize(*args, **kwargs)
            @args = args
            @kwargs = kwargs
          end

          def run
            { args: args, kwargs: kwargs }
          end
        end
      RUBY

      kw_instance = nil
      Rubycli.stub(:run, ->(target, *_args) { kw_instance = target }) do
        Rubycli::Runner.execute(file, nil, ['run'], new: true, new_args: '[1,2]')
      end

      refute_nil kw_instance
      assert_instance_of InitRunner, kw_instance
      assert_equal [[1, 2]], kw_instance.args
      assert_equal({}, kw_instance.kwargs)

      pos_instance = nil
      Rubycli.stub(:run, ->(target, *_args) { pos_instance = target }) do
        Rubycli::Runner.execute(file, nil, ['run'], new: true, new_args: '["alpha", 2]')
      end

      refute_nil pos_instance
      assert_instance_of InitRunner, pos_instance
      assert_equal [ ['alpha', 2] ], pos_instance.args
      assert_equal({}, pos_instance.kwargs)
    ensure
      Object.send(:remove_const, :InitRunner) if Object.const_defined?(:InitRunner)
    end
  end

  def test_auto_mode_selects_single_constant_when_names_differ
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'cli_entry.rb')
      File.write(file, <<~RUBY)
        class TracePointCapturedRunner
          def self.run; end
        end
      RUBY

      captured_target = nil
      Rubycli.stub(:run, ->(target, *_args) { captured_target = target }) do
        Rubycli::Runner.execute(file, nil, [], constant_mode: :auto)
      end

      assert_equal TracePointCapturedRunner, captured_target
    ensure
      Object.send(:remove_const, :TracePointCapturedRunner) if Object.const_defined?(:TracePointCapturedRunner)
    end
  end

  def test_apply_pre_scripts_transforms_target
    target = Class.new do
      def call
        :original
      end
    end

    transformed = Rubycli::Runner.apply_pre_scripts(
      [{ value: 'current.new', context: '(inline)' }],
      target,
      target
    )

    assert_instance_of target, transformed
  end

  def test_invalid_pre_script_source_raises_error
    error = assert_raises(Rubycli::Runner::PreScriptError) do
      Rubycli::Runner.apply_pre_scripts(
        [{ value: 'nonexistent_constant', context: 'missing pre-script' }],
        Object,
        Object
      )
    end
    assert_match(/Failed to evaluate pre-script/, error.message)
  end

  def test_strict_mode_requires_explicit_constant_when_names_differ
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'cli_entry.rb')
      File.write(file, <<~RUBY)
        class TracePointCapturedRunner
          def self.run; end
        end
      RUBY

      error = assert_raises(Rubycli::Runner::Error) do
        Rubycli::Runner.execute(file, nil, [], constant_mode: :strict)
      end
      assert_match('TracePointCapturedRunner', error.message)
      assert_match('specifying the constant explicitly', error.message)
      assert_match('--auto-target', error.message)
    ensure
      Object.send(:remove_const, :TracePointCapturedRunner) if Object.const_defined?(:TracePointCapturedRunner)
    end
  end

  def test_error_when_matching_constant_has_no_cli_methods
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'lonely_runner.rb')
      File.write(file, <<~RUBY)
        class LonelyRunner
          attr_reader :status
        end
      RUBY

      error = assert_raises(Rubycli::Runner::Error) do
        Rubycli::Runner.execute(file, nil, [], constant_mode: :strict)
      end
      assert_match('LonelyRunner', error.message)
      assert_match('--new', error.message)
    ensure
      Object.send(:remove_const, :LonelyRunner) if Object.const_defined?(:LonelyRunner)
    end
  end

  def test_matching_constant_with_only_instance_methods_requires_new
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'instance_runner.rb')
      File.write(file, <<~RUBY)
        class InstanceRunner
          def greet
            'hi'
          end
        end
      RUBY

      error = assert_raises(Rubycli::Runner::Error) do
        Rubycli::Runner.execute(file, nil, [], constant_mode: :strict)
      end
      assert_match('--new', error.message)

      captured = nil
      Rubycli.stub(:run, ->(target, *_args) { captured = target }) do
        Rubycli::Runner.execute(file, nil, ['greet'], constant_mode: :strict, new: true)
      end
      assert_instance_of InstanceRunner, captured
    ensure
      Object.send(:remove_const, :InstanceRunner) if Object.const_defined?(:InstanceRunner)
    end
  end

  def test_new_args_use_metadata_and_type_conversion
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'init_typed_runner.rb')
      File.write(file, <<~RUBY)
        class InitTypedRunner
          attr_reader :items, :flag

      # ITEMS [String[]]
      # --flag [Boolean]
      def initialize(items, flag: false)
        @items = items
        @flag = flag
      end

          def run
            { items: items, flag: flag }
          end
        end
      RUBY

      captured = nil
      Rubycli.stub(:run, ->(target, *_args) { captured = target }) do
        Rubycli::Runner.execute(file, nil, ['run'], new: true, new_args: 'foo,bar', constant_mode: :strict)
      end

      assert_instance_of InitTypedRunner, captured
      assert_equal %w[foo bar], captured.items
      assert_equal false, captured.flag
    ensure
      Object.send(:remove_const, :InitTypedRunner) if Object.const_defined?(:InitTypedRunner)
    end
  end

  def test_positional_array_conversion
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'positional_runner.rb')
      File.write(file, <<~RUBY)
        class PositionalRunner
          # VALUES [Integer[]]
          def self.sum(values)
            values.inject(0, :+)
          end
        end
      RUBY

      Rubycli.stub(:run, ->(target, *_args, **_kw) { target }) do
        Rubycli::Runner.execute(file, nil, ['sum', '1,2,3'], constant_mode: :strict)
      end
    ensure
      Object.send(:remove_const, :PositionalRunner) if Object.const_defined?(:PositionalRunner)
    end
  end

  def test_positional_hash_and_boolean_conversion_and_strict
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'positional_hash_runner.rb')
      File.write(file, <<~RUBY)
        class PositionalHashRunner
          # CONFIG [Hash]
          # FLAG [Boolean]
          def self.combine(config, flag)
            [config, flag]
          end
        end
      RUBY

      parsed = nil
      Rubycli.stub(:call_target, ->(_method, pos_args, kw_args) { parsed = { pos: pos_args, kw: kw_args } }) do
        Rubycli::Runner.execute(file, nil, ['combine', '{"foo":1}', 'true'], constant_mode: :strict, eval_args: false, json: true, new: false)
      end
      assert_equal([{ 'foo' => 1 }, true], parsed[:pos])
      assert_equal({}, parsed[:kw])

      previous_strict = Rubycli.environment.strict_input?
      begin
        Rubycli.environment.enable_strict_input!
        assert_raises(Rubycli::ArgumentError) do
          Rubycli::Runner.execute(file, nil, ['combine', 'not-a-hash', 'maybe'], constant_mode: :strict, eval_args: false, json: true, new: false)
        end
      ensure
        Rubycli.environment.instance_variable_set(:@strict_input, previous_strict)
      end
    ensure
      Object.send(:remove_const, :PositionalHashRunner) if Object.const_defined?(:PositionalHashRunner)
    end
  end

  def test_new_args_with_hash_and_modes_and_spacing
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'init_hash_runner.rb')
      File.write(file, <<~RUBY)
        class InitHashRunner
          attr_reader :opts

          # @param opts [Hash]
          def initialize(opts = {})
            @opts = opts
          end

          def run
            opts
          end
        end
      RUBY

      captured = nil
      Rubycli.stub(:run, ->(target, *_args) { captured = target }) do
        Rubycli::Runner.execute(file, nil, ['run'], new: true, new_args: '{"a":1}', eval_args: false, json: true, constant_mode: :strict)
      end
      assert_instance_of InitHashRunner, captured
      assert_equal({ 'a' => 1 }, captured.opts)

      captured = nil
      Rubycli.stub(:run, ->(target, *_args) { captured = target }) do
        Rubycli::Runner.execute(file, nil, ['run'], new: true, new_args: '{"b":2}', eval_args: true, constant_mode: :strict)
      end
      assert_equal({ 'b' => 2 }, captured.opts)

      error = assert_raises(Rubycli::Runner::Error) do
        Rubycli::Runner.execute(file, nil, ['run'], new: true, new_args: '{b:2}', json: true, constant_mode: :strict)
      end
      assert_includes error.message, 'Failed to parse --new arguments'

      captured = nil
      Rubycli.stub(:run, ->(target, *_args) { captured = target }) do
        Rubycli::Runner.execute(file, nil, ['run'], new: true, new_args: '{retry: 2}', eval_args: false, eval_lax: true, json: false, constant_mode: :strict)
      end
      assert_equal({ retry: 2 }, captured.opts)

      captured = nil
      Rubycli.stub(:run, ->(target, *_args) { captured = target }) do
        Rubycli::Runner.execute(
          file,
          nil,
          ['run'],
          new: true,
          new_args: '{retry: 3}',
          eval_args: false,
          eval_lax: true,
          json: false,
          constant_mode: :strict
        )
      end
      assert_equal({ retry: 3 }, captured.opts)

      captured = nil
      Rubycli.stub(:run, ->(target, *_args) { captured = target }) do
        Rubycli::Runner.execute(file, nil, ['run'], new: true, new_args: 'not{json', eval_args: false, eval_lax: true, json: false, constant_mode: :strict)
      end
      # eval-lax falls back to raw string on parse error
      assert_equal 'not{json', captured.opts
    ensure
      Object.send(:remove_const, :InitHashRunner) if Object.const_defined?(:InitHashRunner)
    end
  end

  def test_eval_lax_on_regular_cli_arguments
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'eval_lax_runner.rb')
      File.write(file, <<~RUBY)
        class EvalLaxRunner
          # values [String[]]
          def self.run(values)
            values
          end
        end
      RUBY

      captured = nil
      Rubycli.stub(:run, ->(target, *_args) { captured = target }) do
        Rubycli::Runner.execute(
          file,
          nil,
          ['run', '[:foo, :bar]'],
          eval_args: false,
          eval_lax: true,
          json: false,
          constant_mode: :strict
        )
      end

      assert_equal %i[foo bar], captured
    ensure
      Object.send(:remove_const, :EvalLaxRunner) if Object.const_defined?(:EvalLaxRunner)
    end
  end

  def test_error_lists_candidates_when_multiple_callable_constants_exist
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'multi_runner.rb')
      File.write(file, <<~RUBY)
        class AlphaRunner
          def self.run; end
        end

        class BetaRunner
          def self.run; end
        end
      RUBY

      error = assert_raises(Rubycli::Runner::Error) do
        Rubycli::Runner.execute(file, nil, [], constant_mode: :strict)
      end
      assert_match('AlphaRunner', error.message)
      assert_match('BetaRunner', error.message)
      assert_match('Specify one explicitly', error.message)
      assert_match('--auto-target', error.message)
    ensure
      Object.send(:remove_const, :AlphaRunner) if Object.const_defined?(:AlphaRunner)
      Object.send(:remove_const, :BetaRunner) if Object.const_defined?(:BetaRunner)
    end
  end

  def test_check_reports_missing_documentation
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'doc_check_runner.rb')
      File.write(file, <<~RUBY)
        class DocCheckRunner
          # @param name [String] Documented name
          # @param extra [String] This param does not exist
          def self.run(name)
            name
          end
        end
      RUBY

      Rubycli.documentation_registry.reset!
      Rubycli.environment.clear_documentation_issues!

      status = nil
      out, err = capture_io do
        status = Rubycli::Runner.check(file, 'DocCheckRunner')
      end

      assert_equal 1, status
      assert_equal '', out
      assert_includes err, 'rubycli documentation check failed'
      refute_empty Rubycli.environment.documentation_issues
    ensure
      Rubycli.documentation_registry.reset!
      Rubycli.environment.clear_documentation_issues!
      Rubycli.environment.disable_doc_check!
      Object.send(:remove_const, :DocCheckRunner) if Object.const_defined?(:DocCheckRunner)
    end
  end
end
