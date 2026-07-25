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

    status = nil
    out, _err = capture_io do
      status = @cli.send(:execute_parameterless_method, method_obj, 'info', ['--help'], true)
    end
    assert_equal 0, status

    assert_equal 0, target.calls
    assert_includes out, 'Usage: rubycli info'
  end

  def test_parameterless_method_rejects_extra_arguments_without_invoking_method
    target = Class.new do
      class << self
        attr_accessor :calls
      end

      self.calls = 0

      def self.info
        self.calls += 1
        nil
      end
    end

    status = nil
    out, _err = capture_io do
      status = @cli.run(target, ['info', 'unexpected'], true)
    end

    assert_equal 1, status
    assert_equal 0, target.calls
    assert_includes out, "Command 'info' does not accept arguments."
    assert_includes out, 'Usage: rubycli info'
  end

  def test_help_input_skips_strict_validation
    method_obj = ChoiceDocSamples.method(:report)
    status = nil
    out, err = capture_io do
      status = @cli.send(:execute_method_with_params, method_obj, 'report', ['help'], true)
    end
    assert_equal 0, status
    assert_includes out, 'Usage:'
    assert_equal '', err
  end

  def test_top_level_help_lists_available_commands_without_invoking_them
    target = Module.new do
      def self.greet(name)
        "Hello, #{name}"
      end
    end

    status = nil
    out, err = capture_io do
      status = @cli.run(target, ['--help'])
    end

    assert_equal 0, status
    assert_includes out, 'Available commands:'
    assert_includes out, 'greet'
    assert_equal '', err
  end

  def test_run_invokes_a_documented_command_with_converted_arguments
    received = nil
    target = Module.new do
      define_singleton_method(:repeat) do |count|
        received = count
        count * 2
      end
    end

    status = @cli.run(target, %w[repeat 3])

    assert_equal 0, status
    assert_equal 3, received
  end

  def test_missing_command_prints_help_for_non_callable_target
    target = Module.new do
      def self.available
        :ok
      end
    end

    status = nil
    out, _err = capture_io do
      status = @cli.run(target, ['missing'])
    end

    assert_equal 1, status
    assert_includes out, "Command 'missing' is not available."
    assert_includes out, 'available'
  end

  def test_callable_target_receives_reconstructed_keyword_arguments
    received = nil
    target = lambda do |name:, loud: false|
      received = [name, loud]
      :ok
    end

    status = @cli.run(target, %w[--name Ruby --loud])

    assert_equal 0, status
    assert_equal ['Ruby', true], received
  end

  def test_missing_required_argument_returns_usage_in_cli_mode
    target = Module.new do
      def self.greet(name)
        name
      end
    end

    status = nil
    out, _err = capture_io do
      status = @cli.run(target, ['greet'], true)
    end

    assert_equal 1, status
    assert_includes out, 'wrong number of arguments'
    assert_includes out, 'Usage: rubycli greet'
  end

  def test_application_argument_error_is_not_reclassified_as_usage_error
    target = Module.new do
      def self.explode(value)
        raise ::ArgumentError, "wrong number of arguments inside #{value}"
      end
    end

    error = assert_raises(::ArgumentError) do
      @cli.run(target, %w[explode payload], true)
    end

    assert_includes error.message, 'inside payload'
  end

  def test_hyphenated_command_resolves_to_snake_case_method
    target = Module.new do
      def self.hello_world
        :ok
      end
    end

    method_obj = @cli.find_method(target, 'hello-world')

    assert_equal :hello_world, method_obj.name
    assert_equal target.method(:hello_world), method_obj
  end

  def test_instance_catalog_exposes_duplicate_instance_and_class_commands
    klass = Class.new do
      def run
        :instance
      end

      def self.run
        :class
      end
    end
    target = klass.new

    catalog = @cli.command_catalog_for(target)

    assert_equal %w[class::run run], catalog.commands.sort
    assert_equal ['run'], catalog.duplicates
    assert_equal :instance, catalog.lookup('instance::run').method.call
    assert_equal :class, catalog.lookup('class::run').method.call
    assert_equal ['run'], catalog.entries_for(:instance).map(&:command)
  end

  def test_generated_accessors_are_not_exposed_as_commands
    klass = Class.new do
      attr_accessor :value

      def run
        :ok
      end
    end

    assert_equal ['run'], @cli.available_commands(klass.new)
  end

  def test_usage_and_description_delegate_to_documented_method_renderer
    method_obj = ChoiceDocSamples.method(:report)

    assert_includes @cli.usage_for_method('report', method_obj), 'Usage: rubycli report LEVEL'
    assert_equal 'LEVEL', @cli.method_description(method_obj)
  end
end
module ChoiceDocSamples
  module_function

  # LEVEL %i[info warn] Report level
  def report(level); end
end
