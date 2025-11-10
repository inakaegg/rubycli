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

    def with_json_mode(enabled = true)
      argument_mode_controller.with_json_mode(enabled) { yield }
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

    def with_eval_mode(enabled = true, **options)
      argument_mode_controller.with_eval_mode(enabled, **options) { yield }
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

    ConstantCandidate = Struct.new(
      :name,
      :constant,
      :class_methods,
      :instance_methods,
      keyword_init: true
    ) do
      def callable?(instantiate: false)
        return true if class_methods.any?

        instantiate && instance_methods.any?
      end

      def matches?(base_name)
        name.split('::').last == base_name
      end

      def instance_only?
        instance_methods.any? && class_methods.empty?
      end

      def summary
        parts = []
        parts << "class: #{format_methods(class_methods)}" if class_methods.any?
        parts << "instance: #{format_methods(instance_methods)}" if instance_methods.any?
        parts << 'no CLI methods' if parts.empty?
        parts.join(' | ')
      end

      private

      def format_methods(methods)
        list = methods.first(3).map(&:to_s)
        list << '...' if methods.size > 3
        list.join(', ')
      end
    end

    module_function

    def execute(
      target_path,
      class_name = nil,
      cli_args = nil,
      new: false,
      json: false,
      eval_args: false,
      eval_lax: false,
      pre_scripts: [],
      constant_mode: nil
    )
      raise ArgumentError, 'target_path must be specified' if target_path.nil? || target_path.empty?
      if json && eval_args
        raise Error, '--json-args cannot be combined with --eval-args or --eval-lax'
      end

      runner_target, full_path = prepare_runner_target(
        target_path,
        class_name,
        new: new,
        pre_scripts: pre_scripts,
        constant_mode: constant_mode
      )

      original_program_name = $PROGRAM_NAME
      original_argv = nil
      $PROGRAM_NAME = File.basename(full_path)
      original_argv = ARGV.dup
      ARGV.replace(Array(cli_args).dup)
      run_with_modes(runner_target, json: json, eval_args: eval_args, eval_lax: eval_lax)
    ensure
      $PROGRAM_NAME = original_program_name if original_program_name
      ARGV.replace(original_argv) if original_argv
    end

    def check(
      target_path,
      class_name = nil,
      new: false,
      pre_scripts: [],
      constant_mode: nil
    )
      raise ArgumentError, 'target_path must be specified' if target_path.nil? || target_path.empty?
      previous_doc_check = Rubycli.environment.doc_check_mode?
      Rubycli.environment.clear_documentation_issues!
      Rubycli.environment.enable_doc_check!

      runner_target, full_path = prepare_runner_target(
        target_path,
        class_name,
        new: new,
        pre_scripts: pre_scripts,
        constant_mode: constant_mode
      )

      original_program_name = $PROGRAM_NAME
      $PROGRAM_NAME = File.basename(full_path)

      catalog = Rubycli.cli.command_catalog_for(runner_target)
      Array(catalog&.entries).each do |entry|
        method_obj = entry&.method
        Rubycli.documentation_registry.metadata_for(method_obj) if method_obj
      end

      if catalog&.entries&.empty? && runner_target.respond_to?(:call)
        method_obj = runner_target.method(:call) rescue nil
        Rubycli.documentation_registry.metadata_for(method_obj) if method_obj
      end

      issues = Rubycli.environment.documentation_issues
      if issues.empty?
        puts 'rubycli documentation OK'
        0
      else
        warn "[ERROR] rubycli documentation check failed (#{issues.size} issue#{issues.size == 1 ? '' : 's'})"
        1
      end
    ensure
      Rubycli.environment.disable_doc_check! unless previous_doc_check
      $PROGRAM_NAME = original_program_name if original_program_name
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

    def run_with_modes(target, json:, eval_args:, eval_lax:)
      runner = proc { Rubycli.run(target) }

      if json
        Rubycli.with_json_mode(true, &runner)
      elsif eval_args
        Rubycli.with_eval_mode(true, lax: eval_lax, &runner)
      else
        runner.call
      end
    end

    def prepare_runner_target(
      target_path,
      class_name,
      new: false,
      pre_scripts: [],
      constant_mode: nil
    )
      full_path = find_target_path(target_path)
      capture = Rubycli.constant_capture
      capture.capture(full_path) { load full_path }
      constant_mode ||= Rubycli.environment.constant_resolution_mode
      candidates = build_constant_candidates(full_path, capture.constants_for(full_path))
      defined_constants = candidates.map(&:name)

      target = if class_name
                 constantize(
                   class_name,
                   defined_constants: defined_constants,
                   full_path: full_path
                 )
               else
                 select_constant_candidate(
                   full_path,
                   camelize(File.basename(full_path, '.rb')),
                   candidates,
                   constant_mode,
                   instantiate: new
                 )
               end

      runner_target = new ? instantiate_target(target) : target
      runner_target = apply_pre_scripts(pre_scripts, target, runner_target)
      [runner_target, full_path]
    end

    def build_constant_candidates(path, constant_names)
      normalized = normalize_path(path)
      Array(constant_names).each_with_object([]) do |const_name, memo|
        constant = safe_constant_lookup(const_name)
        next unless constant.is_a?(Module)

        class_methods = collect_defined_methods(constant.singleton_class, normalized)
        instance_methods = collect_defined_methods(constant, normalized)

        memo << ConstantCandidate.new(
          name: const_name,
          constant: constant,
          class_methods: class_methods,
          instance_methods: instance_methods
        )
      end
    end

    def collect_defined_methods(owner, normalized_path)
      owner.public_instance_methods(false).each_with_object([]) do |method_name, memo|
        method_object = owner.instance_method(method_name)
        location = method_object.source_location
        next unless location && normalize_path(location[0]) == normalized_path

        memo << method_name
      end
    rescue TypeError
      []
    end

    def safe_constant_lookup(name)
      parts = name.split('::').reject(&:empty?)
      context = Object

      parts.each do |const_name|
        return nil unless context.const_defined?(const_name, false)

        context = context.const_get(const_name)
      end

      context
    rescue NameError
      nil
    end

    def select_constant_candidate(path, base_const, candidates, constant_mode, instantiate: false)
      if candidates.empty?
        raise Error, build_missing_constant_message(
          base_const,
          [],
          path,
          details: 'Rubycli could not detect any constants in this file.'
        )
      end

      matching = candidates.find { |candidate| candidate.matches?(base_const) }
      if matching
        return matching.constant if matching.callable?(instantiate: instantiate)

        detail = if matching.instance_only?
                   "#{matching.name} only defines instance methods in this file. Run with --new to instantiate before invoking CLI commands."
                 else
                   "#{matching.name} does not define any CLI-callable methods in this file. Add a public class or instance method defined in this file."
                 end
        raise Error, build_missing_constant_message(
          base_const,
          candidates.map(&:name),
          path,
          details: detail
        )
      end

      callable = candidates.select { |candidate| candidate.callable?(instantiate: instantiate) }
      if callable.empty?
        raise Error, build_missing_constant_message(
          base_const,
          candidates.map(&:name),
          path,
          details: 'Rubycli detected constants in this file, but none define CLI-callable methods. Add a public class or instance method defined in this file.'
        )
      end

      if constant_mode == :auto && callable.size == 1
        return callable.first.constant
      end

      details = build_ambiguous_constant_details(callable, path)
      raise Error, build_missing_constant_message(
        base_const,
        candidates.map(&:name),
        path,
        details: details
      )
    end

    def build_ambiguous_constant_details(candidates, path)
      command_target = File.basename(path)
      if candidates.size == 1
        candidate = candidates.first
        lines = []
        lines << "This file defines #{candidate.name}, but its name does not match #{command_target}."
        lines << 'Re-run by specifying the constant explicitly:'
        lines << "  rubycli #{command_target} #{candidate.name} ..."
        lines << 'Alternatively pass --auto-target (or RUBYCLI_AUTO_TARGET=auto) to auto-select it.'
        return lines.join("\n")
      end

      lines = ['Multiple CLI-capable constants were found in this file:']
      candidates.each do |candidate|
        hint = candidate.instance_only? ? ' (instance methods only; use --new)' : ''
        lines << "  - #{candidate.name}: #{candidate.summary}#{hint}"
      end
      lines << "Specify one explicitly, e.g. rubycli #{command_target} MyRunner"
      lines << 'Or pass --auto-target to allow Rubycli to auto-select a single candidate.'
      lines.join("\n")
    end

    def normalize_path(path)
      File.expand_path(path.to_s)
    end

    def build_missing_constant_message(name, defined_constants, full_path, details: nil)
      lines = ["Could not find definition: #{name}"]
      lines << ''
      lines << "Loaded file: #{File.expand_path(full_path)}" if full_path

      if defined_constants && !defined_constants.empty?
        sample = defined_constants.first(5)
        suffix = defined_constants.size > sample.size ? " … (#{defined_constants.size} total)" : ''
        lines << "Constants found in this file: #{sample.join(', ')}#{suffix}"
      else
        lines << 'Rubycli could not detect any publicly exposable constants in this file.'
      end

      if details
        lines << ''
        lines << details
      end

      lines << ''
      lines << 'Hint: Ensure the CLASS_OR_MODULE argument is correct when invoking the CLI.'
      lines.join("\n")
    end
  end
end
