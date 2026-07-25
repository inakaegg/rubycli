# frozen_string_literal: true

require 'json'

require_relative 'rubycli/version'
require_relative 'rubycli/environment'
require_relative 'rubycli/types'
require_relative 'rubycli/type_utils'
require_relative 'rubycli/documentation_registry'
require_relative 'rubycli/json_coercer'
require_relative 'rubycli/eval_coercer'
require_relative 'rubycli/arguments/token_stream'
require_relative 'rubycli/arguments/value_converter'
require_relative 'rubycli/argument_mode_controller'
require_relative 'rubycli/argument_parser'
require_relative 'rubycli/help_renderer'
require_relative 'rubycli/result_emitter'
require_relative 'rubycli/cli'
require_relative 'rubycli/command_line'
require_relative 'rubycli/constant_capture'

module Rubycli
  class Error < StandardError; end
  class CommandNotFoundError < Error; end
  class ArgumentError < Error; end

  class << self
    def environment
      @environment ||= Environment.new(env: ENV, argv: ARGV)
    end

    def documentation_registry
      @documentation_registry ||= DocumentationRegistry.new(environment: environment)
    end

    def json_coercer
      @json_coercer ||= JsonCoercer.new
    end

    def eval_coercer
      @eval_coercer ||= EvalCoercer.new
    end

    def argument_mode_controller
      @argument_mode_controller ||= ArgumentModeController.new(
        json_coercer: json_coercer,
        eval_coercer: eval_coercer
      )
    end

    def argument_parser
      @argument_parser ||= ArgumentParser.new(
        environment: environment,
        documentation_registry: documentation_registry,
        json_coercer: json_coercer,
        debug_logger: method(:debug_log)
      )
    end

    def help_renderer
      @help_renderer ||= HelpRenderer.new(documentation_registry: documentation_registry)
    end

    def result_emitter
      @result_emitter ||= ResultEmitter.new(environment: environment)
    end

    def constant_capture
      @constant_capture ||= ConstantCapture.new
    end

    def cli
      @cli ||= CLI.new(
        environment: environment,
        argument_parser: argument_parser,
        documentation_registry: documentation_registry,
        help_renderer: help_renderer,
        result_emitter: result_emitter
      )
    end

    def run(target, args = ARGV, cli_mode = true)
      status = cli.run(target, args.dup, cli_mode)
      return status unless cli_mode

      exit(status.to_i)
    end

    def parse_arguments(args, method = nil)
      argument_parser.parse(args.dup, method)
    end

    def available_commands(target)
      cli.available_commands(target)
    end

    def find_method(target, command)
      cli.find_method(target, command)
    end

    def usage_for_method(command, method)
      cli.usage_for_method(command, method)
    end

    def method_description(method)
      cli.method_description(method)
    end

    def print_help(target)
      catalog = cli.command_catalog_for(target)
      help_renderer.print_help(target, catalog)
    end

    def call_target(target_callable, pos_args, kw_args)
      debug_log "Calling target with pos_args: #{pos_args.inspect}, kw_args: #{kw_args.inspect}"
      kw_args.empty? ? target_callable.call(*pos_args) : target_callable.call(*pos_args, **kw_args)
    end

    def debug_log(message)
      puts "[DEBUG] #{message}" if environment.debug?
    end

    def json_mode?
      argument_mode_controller.json_mode?
    end

    def with_json_mode(enabled = true, &block)
      argument_mode_controller.with_json_mode(enabled, &block)
    end

    def coerce_json_value(value)
      json_coercer.coerce_json_value(value)
    end

    def eval_mode?
      argument_mode_controller.eval_mode?
    end

    def eval_lax_mode?
      eval_coercer.eval_lax_mode?
    end

    def with_eval_mode(enabled = true, **options, &block)
      argument_mode_controller.with_eval_mode(enabled, **options, &block)
    end

    def coerce_eval_value(value)
      eval_coercer.coerce_eval_value(value)
    end

    def apply_argument_coercions(pos_args, kw_args)
      argument_mode_controller.apply_argument_coercions(pos_args, kw_args)
    end

    def apply_json_coercion(pos_args, kw_args)
      apply_argument_coercions(pos_args, kw_args)
    end
  end
end

# Defined after the Rubycli module so that Runner::Error can subclass Rubycli::Error.
require_relative 'rubycli/runner'
