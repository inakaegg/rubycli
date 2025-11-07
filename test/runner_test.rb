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
    ensure
      Object.send(:remove_const, :AlphaRunner) if Object.const_defined?(:AlphaRunner)
      Object.send(:remove_const, :BetaRunner) if Object.const_defined?(:BetaRunner)
    end
  end
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
      assert_match('Specify one explicitly', error.message)
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
      assert_match('public class or instance method', error.message)
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
