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
end
