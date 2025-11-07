# frozen_string_literal: true

require 'json'

feature_path = File.expand_path(__FILE__)
$LOADED_FEATURES << feature_path unless $LOADED_FEATURES.include?(feature_path)

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
      cli.run(target, args.dup, cli_mode)
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

    def with_json_mode(enabled = true)
      argument_mode_controller.with_json_mode(enabled) { yield }
    end

    def coerce_json_value(value)
      json_coercer.coerce_json_value(value)
    end

    def eval_mode?
      argument_mode_controller.eval_mode?
    end

    def with_eval_mode(enabled = true)
      argument_mode_controller.with_eval_mode(enabled) { yield }
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

  module Runner
    class Error < Rubycli::Error; end
    class PreScriptError < Error; end

    module_function

    def execute(
      target_path,
      class_name = nil,
      cli_args = nil,
      new: false,
      json: false,
      eval_args: false,
      pre_scripts: []
    )
      raise ArgumentError, 'target_path must be specified' if target_path.nil? || target_path.empty?
      original_program_name = $PROGRAM_NAME
      if json && eval_args
        raise Error, '--json-args and --eval-args cannot be used together'
      end

      full_path = find_target_path(target_path)
      load full_path
      $PROGRAM_NAME = File.basename(full_path)
      defined_constants = constants_defined_in_file(full_path)

      constant_name = class_name || infer_class_name(full_path)
      target = constantize(
        constant_name,
        defined_constants: defined_constants,
        full_path: full_path
      )
      runner_target = new ? instantiate_target(target) : target
      runner_target = apply_pre_scripts(pre_scripts, target, runner_target)

      original_argv = ARGV.dup
      ARGV.replace(Array(cli_args).dup)
      run_with_modes(runner_target, json: json, eval_args: eval_args)
    ensure
      $PROGRAM_NAME = original_program_name if original_program_name
      ARGV.replace(original_argv) if original_argv
    end

    def apply_pre_scripts(sources, base_target, initial_target)
      Array(sources).reduce(initial_target) do |current_target, source|
        result = evaluate_pre_script(source, base_target, current_target)
        result.nil? ? current_target : result
      end
    end

    def evaluate_pre_script(source, base_target, current_target)
      code, context = read_pre_script_code(source)
      pre_binding = Object.new.instance_eval { binding }
      pre_binding.local_variable_set(:target, base_target)
      pre_binding.local_variable_set(:current, current_target)
      pre_binding.local_variable_set(:instance, current_target)

      Rubycli.with_eval_mode(true) do
        pre_binding.eval(code, context)
      end
    rescue Errno::ENOENT
      raise PreScriptError, "Pre-script file not found: #{context}"
    rescue StandardError => e
      raise PreScriptError, "Failed to evaluate pre-script (#{context}): #{e.message}"
    end

    def read_pre_script_code(source)
      value = source[:value]
      inline_context = source[:context] || '(inline pre-script)'

      if !value.nil? && File.file?(value)
        [File.read(value), File.expand_path(value)]
      else
        [String(value), inline_context]
      end
    end

    def find_target_path(path)
      if File.file?(path)
        File.expand_path(path)
      elsif File.file?("#{path}.rb")
        File.expand_path("#{path}.rb")
      else
        raise Error, "File not found: #{path}"
      end
    end

    def infer_class_name(path)
      base = File.basename(path, '.rb')
      base_const = camelize(base)
      detect_constant_for_file(path, base_const) || base_const
    end

    def camelize(name)
      name.split(/[^a-zA-Z0-9]+/).reject(&:empty?).map { |part|
        part[0].upcase + part[1..].downcase
      }.join
    end

    def constantize(name, defined_constants: nil, full_path: nil)
      parts = name.to_s.split('::').reject(&:empty?)
      raise Error, "Unable to resolve class/module name: #{name.inspect}" if parts.empty?

      parts.reduce(Object) do |context, const_name|
        context.const_get(const_name)
      end
    rescue NameError
      message = build_missing_constant_message(name, defined_constants, full_path)
      raise Error.new(message), cause: nil
    end

    def instantiate_target(target)
      case target
      when Class
        target.new
      when Module
        Object.new.extend(target)
      else
        target
      end
    rescue ArgumentError => e
      raise Error, "Failed to instantiate target: #{e.message}"
    end

    def run_with_modes(target, json:, eval_args:)
      runner = proc { Rubycli.run(target) }

      if json
        Rubycli.with_json_mode(true, &runner)
      elsif eval_args
        Rubycli.with_eval_mode(true, &runner)
      else
        runner.call
      end
    end

    def detect_constant_for_file(path, base_const)
      full_path = File.expand_path(path)
      candidates = runtime_constant_candidates(full_path, base_const)
      candidates.find { |name| constant_defined?(name) }
    end

    def constants_defined_in_file(path)
      return [] unless Module.method_defined?(:const_source_location)

      normalized = File.expand_path(path)
      ObjectSpace.each_object(Module).each_with_object([]) do |mod, memo|
        mod_name = module_name_for(mod)
        next if mod_name.nil?

        safe_module_constants(mod).each do |const_name|
          location = safe_const_source_location(mod, const_name)
          next unless location && location[0]
          next unless File.expand_path(location[0]) == normalized

          memo << qualified_constant_name(mod_name, const_name.to_s)
        end
      end.uniq.sort_by { |name| [name.count('::'), name] }
    end

    def runtime_constant_candidates(full_path, base_const)
      return [] unless Module.method_defined?(:const_source_location)

      normalized = File.expand_path(full_path)
      ObjectSpace.each_object(Module).each_with_object([]) do |mod, memo|
        mod_name = module_name_for(mod)
        next unless mod_name
        next unless safe_const_defined?(mod, base_const)

        location = safe_const_source_location(mod, base_const)
        next unless location && File.expand_path(location[0]) == normalized

        memo << qualified_constant_name(mod_name, base_const)
      end.uniq.sort_by { |name| [-name.count('::'), name] }
    end

    def module_name_for(mod)
      return '' if mod.equal?(Object)

      name = mod.name
      return nil if name.nil? || name.start_with?('#<')

      name
    end

    def qualified_constant_name(mod_name, base_const)
      mod_name.empty? ? base_const : "#{mod_name}::#{base_const}"
    end

    def safe_module_constants(mod)
      mod.constants(false)
    rescue NameError
      []
    end

    def safe_const_defined?(mod, const_name)
      mod.const_defined?(const_name, false)
    rescue NameError
      false
    end

    def safe_const_source_location(mod, const_name)
      return nil unless mod.respond_to?(:const_source_location)

      mod.const_source_location(const_name, false)
    rescue NameError
      nil
    end

    def constant_defined?(name)
      parts = name.split('::').reject(&:empty?)
      context = Object

      parts.each do |const_name|
        return false unless context.const_defined?(const_name, false)

        context = context.const_get(const_name)
      end
      true
    rescue NameError
      false
    end

    def build_missing_constant_message(name, defined_constants, full_path)
      lines = ["Could not find definition: #{name}"]
      lines << "  Loaded file: #{File.expand_path(full_path)}" if full_path

      if defined_constants && !defined_constants.empty?
        sample = defined_constants.first(5)
        suffix = defined_constants.size > sample.size ? " ... (#{defined_constants.size} total)" : ''
        lines << "  Constants found in this file: #{sample.join(', ')}#{suffix}"
      else
        lines << "  Rubycli could not detect any publicly exposable constants in this file."
      end

      lines << "  Ensure the CLASS_OR_MODULE argument is correct when invoking the CLI."
      lines.join("\n")
    end
  end
end
