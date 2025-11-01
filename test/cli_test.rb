# frozen_string_literal: true

require 'test_helper'

class CLITest < Minitest::Test
  def setup
    @environment = Rubycli::Environment.new(env: {}, argv: [])
    @documentation_registry = Rubycli::DocumentationRegistry.new(environment: @environment)
    argument_parser = Rubycli::ArgumentParser.new(
      environment: @environment,
      documentation_registry: @documentation_registry,
      json_coercer: Rubycli::JsonCoercer.new,
      debug_logger: nil
    )
    help_renderer = Rubycli::HelpRenderer.new(documentation_registry: @documentation_registry)
    result_emitter = Rubycli::ResultEmitter.new(environment: @environment)

    @cli = Rubycli::CLI.new(
      environment: @environment,
      argument_parser: argument_parser,
      documentation_registry: @documentation_registry,
      help_renderer: help_renderer,
      result_emitter: result_emitter
    )

    @original_program_name = $PROGRAM_NAME
    $PROGRAM_NAME = 'rubycli'
  end

  def teardown
    $PROGRAM_NAME = @original_program_name
  end

  def test_parameterless_method_help_does_not_invoke_method
    target = Class.new do
      class << self
        attr_accessor :calls
      end

      self.calls = 0

      def self.info
        self.calls += 1
        :info
      end
    end

    method_obj = target.method(:info)

    out, _err = capture_io do
      exit_error = assert_raises(SystemExit) do
        @cli.send(:execute_parameterless_method, method_obj, 'info', ['--help'], true)
      end
      assert_equal 0, exit_error.status
    end

    assert_equal 0, target.calls
    assert_includes out, 'Usage: rubycli info'
  end
end
