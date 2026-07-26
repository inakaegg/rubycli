# frozen_string_literal: true

module Rubycli
  # Loads a target file, resolves the class/module to expose, and hands it to
  # Rubycli::CLI. Also implements the --check documentation lint.
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
      new_args: nil,
      json: false,
      eval_args: false,
      eval_lax: false,
      pre_scripts: [],
      constant_mode: nil
    )
      raise ArgumentError, 'target_path must be specified' if target_path.nil? || target_path.empty?
      raise Error, '--json-args cannot be combined with --eval-args or --eval-lax' if json && eval_args

      original_program_name = nil
      original_argv = nil
      execution = proc do
        runner_target, full_path = prepare_runner_target(
          target_path,
          class_name,
          new: new,
          new_args: new_args,
          json_mode: json,
          eval_mode: eval_args,
          eval_lax: eval_lax,
          pre_scripts: pre_scripts,
          constant_mode: constant_mode
        )

        original_program_name = $PROGRAM_NAME
        $PROGRAM_NAME = File.basename(full_path)
        original_argv = ARGV.dup
        ARGV.replace(Array(cli_args).dup)
        run_with_modes(runner_target, json: json, eval_args: eval_args, eval_lax: eval_lax)
      end

      if eval_args
        Rubycli.eval_coercer.with_eval_binding(&execution)
      else
        execution.call
      end
    ensure
      $PROGRAM_NAME = original_program_name if original_program_name
      ARGV.replace(original_argv) if original_argv
    end

    def check(
      target_path,
      class_name = nil,
      new: false,
      new_args: nil,
      pre_scripts: [],
      constant_mode: nil,
      json_mode: false,
      eval_mode: false,
      eval_lax: false
    )
      previous_doc_check = Rubycli.environment.doc_check_mode?
      raise ArgumentError, 'target_path must be specified' if target_path.nil? || target_path.empty?
      raise Error, '--check cannot be combined with --pre-script or --init' unless Array(pre_scripts).empty?

      Rubycli.environment.clear_documentation_issues!
      Rubycli.environment.enable_doc_check!

      runner_target, full_path = resolve_runner_target(
        target_path,
        class_name,
        constant_mode: constant_mode,
        instantiate: new
      )

      original_program_name = $PROGRAM_NAME
      $PROGRAM_NAME = File.basename(full_path)

      documentation_methods_for(runner_target, full_path, instantiate: new).each do |method_obj|
        Rubycli.documentation_registry.metadata_for(method_obj)
      end

      issues = Rubycli.environment.documentation_issues
      if issues.empty?
        puts 'rubycli documentation OK'
        0
      else
        warn "[ERROR] rubycli documentation check failed (#{issues.size} issue#{'s' unless issues.size == 1})"
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
    rescue SyntaxError => e
      raise PreScriptError, "Failed to evaluate pre-script (#{context}): #{e.message}"
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
      resolved = if File.file?(path)
                   path
                 elsif File.file?("#{path}.rb")
                   "#{path}.rb"
                 else
                   raise Error, "File not found: #{path}"
                 end

      # Reading the target happens in two places (source analysis and load), so
      # check once here to report a curated error instead of an Errno backtrace.
      raise Error, "File is not readable: #{resolved}" unless File.readable?(resolved)

      File.expand_path(resolved)
    end

    def camelize(name)
      name.split(/[^a-zA-Z0-9]+/).reject(&:empty?).map do |part|
        part[0].upcase + part[1..].downcase
      end.join
    end

    def constantize(name, defined_constants: nil, full_path: nil)
      parts = name.to_s.split('::').reject(&:empty?)
      raise Error, "Unable to resolve class/module name: #{name.inspect}" if parts.empty?

      parts.reduce(Object) do |context, const_name|
        context.const_get(const_name, false)
      end
    rescue NameError
      message = build_missing_constant_message(name, defined_constants, full_path)
      raise Error.new(message), cause: nil
    end

    def instantiate_target(target, initializer_args = nil)
      positional_args, keyword_args = Array(initializer_args || [[], {}])
      positional_args ||= []
      keyword_args ||= {}

      case target
      when Class
        if keyword_args.empty?
          target.new(*positional_args)
        else
          target.new(*positional_args, **keyword_args)
        end
      when Module
        Object.new.extend(target)
      else
        target
      end
    rescue ::ArgumentError, Rubycli::ArgumentError => e
      raise Error, "Failed to instantiate target: #{e.message}"
    end

    def run_with_modes(target, json:, eval_args:, eval_lax:)
      # Rubycli.run terminates the process, which is what an embedded
      # `Rubycli.run(MyApp)` script wants. Here the status has to travel back to
      # Rubycli::CommandLine.run so callers can decide what to do with it.
      runner = proc { Rubycli.cli.run(target, ARGV.dup, true) }

      if json
        Rubycli.with_json_mode(true, &runner)
      elsif eval_args
        Rubycli.with_eval_mode(true, lax: eval_lax, reuse_binding: true, &runner)
      else
        runner.call
      end
    end

    def parse_initializer_arguments(raw_value, target, json_mode:, eval_mode:, eval_lax:)
      return [[], {}] if raw_value.nil?
      if json_mode && eval_mode
        raise Rubycli::ArgumentError,
              '--json-args cannot be combined with --eval-args or --eval-lax'
      end

      initializer_method = initializer_method_for(target)
      tokens = Array(raw_value)

      positional_args = []
      keyword_args = {}

      Rubycli.argument_mode_controller.with_json_mode(json_mode) do
        Rubycli.argument_mode_controller.with_eval_mode(eval_mode, lax: eval_lax, reuse_binding: true) do
          positional_args, keyword_args = Rubycli.argument_parser.parse(tokens.dup, initializer_method)
          Rubycli.apply_argument_coercions(positional_args, keyword_args)
          Rubycli.argument_parser.validate_inputs(initializer_method, positional_args, keyword_args)
        end
      end

      [positional_args || [], keyword_args || {}]
    rescue Rubycli::ArgumentError => e
      raise Runner::Error, "Failed to parse --new arguments: #{e.message}"
    end

    def initializer_method_for(target)
      return nil unless target.is_a?(Class)

      begin
        target.instance_method(:initialize)
      rescue NameError
        nil
      end
    end

    def prepare_runner_target(
      target_path,
      class_name,
      new: false,
      new_args: nil,
      json_mode: false,
      eval_mode: false,
      eval_lax: false,
      pre_scripts: [],
      constant_mode: nil
    )
      target, full_path = resolve_runner_target(
        target_path,
        class_name,
        constant_mode: constant_mode,
        instantiate: new
      )

      initializer_args = if new
                           parse_initializer_arguments(new_args, target, json_mode: json_mode,
                                                                         eval_mode: eval_mode, eval_lax: eval_lax)
                         end

      runner_target = new ? instantiate_target(target, initializer_args) : target
      runner_target = apply_pre_scripts(pre_scripts, target, runner_target)
      [runner_target, full_path]
    end

    def resolve_runner_target(target_path, class_name, constant_mode:, instantiate:)
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
                   instantiate: instantiate
                 )
               end

      [target, full_path]
    end

    def documentation_methods_for(target, _full_path, instantiate:)
      unless target.is_a?(Module)
        catalog = Rubycli.cli.command_catalog_for(target)
        methods = Array(catalog&.entries).filter_map(&:method)
        if methods.empty? && target.respond_to?(:call)
          callable = begin
            target.method(:call)
          rescue NameError
            nil
          end
          methods << callable if callable
        end
        return methods
      end

      class_methods = target.singleton_class.public_instance_methods(false)
                            .map { |name| target.method(name) }
                            .select { |method_obj| Rubycli.cli.exposable_method?(method_obj) }
      return class_methods unless instantiate

      instance_methods = target.public_instance_methods(false)
                               .map { |name| target.instance_method(name) }
                               .select { |method_obj| Rubycli.cli.exposable_method?(method_obj) }
      target.is_a?(Class) ? instance_methods + class_methods : instance_methods
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
          details: detail,
          headline: "#{matching.name} cannot be used as a CLI target"
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

      return callable.first.constant if constant_mode == :auto && callable.size == 1

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

    # +headline+ replaces the default first line when the constant was found but
    # cannot be exposed, so the message does not claim it is missing.
    def build_missing_constant_message(name, defined_constants, full_path, details: nil, headline: nil)
      lines = [headline || "Could not find definition: #{name}"]
      lines << ''
      lines << "Loaded file: #{File.expand_path(full_path)}" if full_path

      if defined_constants && !defined_constants.empty?
        sample = defined_constants.first(5)
        suffix = defined_constants.size > sample.size ? " ... (#{defined_constants.size} total)" : ''
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
