# frozen_string_literal: true

module Rubycli
  module CommandLine
    USAGE = <<~USAGE
      Usage: rubycli [--new|-n[=<value>]] [--pre-script=<src>] [--json-args|-j | --eval-args|-e | --eval-lax|-E] [--strict] [--check|-c] <target-path> [<class-or-module>] [-- <cli-args>...]

      Examples:
        rubycli path/to/greeter.rb greet Hanako
        rubycli path/to/multi_runner.rb AlternateRunner greet --name Ruby
        rubycli --auto-target path/to/mismatched_runner.rb greet Hanako
        rubycli --new='["a","b"]' path/to/collection_runner.rb run --mode summary
        rubycli --json-args --new='["a","b"]' path/to/collection_runner.rb run --mode '"summary"'

      Options:
        --new, -n [<value>]  Instantiate the class/module before invoking CLI commands; one optional literal can follow and is bound to the constructor's first parameter (respects --json-args/--eval-args/--eval-lax; use --pre-script for several or keyword arguments)
        --pre-script=<src>   Evaluate Ruby code and use its result as the exposed target (--init alias; also accepts space-separated form)
        --json-args, -j      Parse all following arguments strictly as JSON (no YAML literals; even plain words need quoting)
        --eval-args, -e      Evaluate following arguments as Ruby code (every argument must be valid Ruby)
        --eval-lax, -E       Evaluate as Ruby but fall back to raw strings when parsing fails
        --auto-target, -a    Auto-select the only callable constant when names don't match
        --strict             Enforce documented input types/choices (invalid values abort)
        --check, -c          Validate documentation/comments without executing commands
        --help, -h           Show this message (the bare word `help` works too)
        (Note: --json-args cannot be combined with --eval-args or --eval-lax)
        (Note: Every option that accepts a value understands both --flag=value and --flag value forms.)

      When <class-or-module> is omitted, Rubycli infers it from the file name in CamelCase.
      Arguments are parsed as safe literals by default; pick a mode above if you need strict JSON or Ruby eval.
      Method return values are printed to STDOUT by default.
      <cli-args> are forwarded to Rubycli unchanged.
    USAGE

    # Flags collected before the target path; forwarded to Rubycli::Runner.
    Options = Struct.new(
      :new_flag,
      :new_args,
      :json_mode,
      :eval_mode,
      :eval_lax,
      :constant_mode,
      :check_mode,
      :pre_scripts,
      keyword_init: true
    ) do
      def self.defaults
        new(
          new_flag: false,
          new_args: nil,
          json_mode: false,
          eval_mode: false,
          eval_lax: false,
          constant_mode: nil,
          check_mode: false,
          pre_scripts: []
        )
      end
    end

    module_function

    def run(argv = ARGV)
      previous_state = environment_state
      args = Array(argv).dup
      Rubycli.environment.enable_print_result!
      return print_usage(1) if args.empty?

      options = Options.defaults
      status = parse_flags!(args, options)
      return status if status
      return print_usage(1) if args.empty?

      target_path, class_or_module = extract_target!(args)
      status = reject_conflicting_flags(options, args)
      return status if status

      Rubycli.environment.clear_documentation_issues!
      dispatch(target_path, class_or_module, args, options)
    rescue Rubycli::Runner::Error => e
      warn "[ERROR] #{e.message}"
      1
    ensure
      restore_environment(previous_state)
    end

    # Consumes leading flags from +args+ and fills +options+.
    # Returns an exit status when the CLI should stop, otherwise nil.
    def parse_flags!(args, options)
      until args.empty?
        case args.first
        when '-h', '--help', 'help'
          return print_usage(0)
        when /\A--new(?:=(.+))?\z/
          inline_value = Regexp.last_match(1)
          args.shift
          consume_new_arguments!(args, options, inline_value)
        when '-n'
          args.shift
          consume_new_arguments!(args, options, nil)
        when /\A--pre-script=(.+)\z/, /\A--init=(.+)\z/
          flag = Regexp.last_match(0).start_with?('--pre-script') ? '--pre-script' : '--init'
          options.pre_scripts << { value: Regexp.last_match(1), context: "(inline #{flag})" }
          args.shift
        when '--pre-script', '--init'
          status = consume_pre_script_source!(args, options)
          return status if status
        when '--json-args', '-j'
          options.json_mode = true
          args.shift
        when '--eval-args', '-e'
          options.eval_mode = true
          args.shift
        when '--eval-lax', '-E'
          options.eval_mode = true
          options.eval_lax = true
          args.shift
        when '--strict'
          Rubycli.environment.enable_strict_input!
          args.shift
        when '--check', '-c'
          options.check_mode = true
          Rubycli.environment.enable_doc_check!
          args.shift
        when '--print-result'
          args.shift
        when '--debug'
          args.shift
          warn '[ERROR] --debug flag has been removed; set RUBYCLI_DEBUG=true instead.'
          return 1
        when '--auto-target', '-a'
          options.constant_mode = :auto
          args.shift
        when '--'
          args.shift
          break
        else
          break
        end
      end

      nil
    end

    def consume_new_arguments!(args, options, inline_value)
      options.new_flag = true
      options.new_args = inline_value
      return unless inline_value.nil?

      candidate = args.first
      return unless candidate && !candidate.start_with?('-') && likely_new_args_value?(candidate)

      options.new_args = args.shift
    end

    def consume_pre_script_source!(args, options)
      flag = args.shift
      source = args.shift
      unless source
        warn "[ERROR] #{flag} requires a file path or inline Ruby code"
        return 1
      end

      context = File.file?(source) ? File.expand_path(source) : "(inline #{flag})"
      options.pre_scripts << { value: source, context: context }
      nil
    end

    # Removes the target path and the optional explicit constant from +args+.
    def extract_target!(args)
      target_path = args.shift
      class_or_module = nil
      candidate = args.first
      class_or_module = args.shift if candidate && candidate != '--' && candidate.match?(/\A[A-Z]/)
      args.shift if args.first == '--'
      [target_path, class_or_module]
    end

    # Returns an exit status when the flag combination is unusable, otherwise nil.
    def reject_conflicting_flags(options, args)
      if options.json_mode && options.eval_mode
        warn '[ERROR] --json-args cannot be combined with --eval-args or --eval-lax'
        return 1
      end

      return nil unless options.check_mode

      if options.json_mode || options.eval_mode
        warn '[ERROR] --check cannot be combined with --json-args or --eval-args'
        return 1
      end

      unless args.empty?
        warn '[ERROR] --check does not accept command arguments'
        return 1
      end

      nil
    end

    def dispatch(target_path, class_or_module, args, options)
      if options.check_mode
        return Rubycli::Runner.check(
          target_path,
          class_or_module,
          new: options.new_flag,
          new_args: options.new_args,
          pre_scripts: options.pre_scripts,
          constant_mode: options.constant_mode
        )
      end

      Rubycli::Runner.execute(
        target_path,
        class_or_module,
        args,
        new: options.new_flag,
        new_args: options.new_args,
        json: options.json_mode,
        eval_args: options.eval_mode,
        eval_lax: options.eval_lax,
        pre_scripts: options.pre_scripts,
        constant_mode: options.constant_mode
      )

      0
    end

    def print_usage(status)
      $stdout.puts(USAGE)
      status
    end

    def environment_state
      environment = Rubycli.environment
      {
        doc_check: environment.doc_check_mode?,
        strict_input: environment.strict_input?,
        print_result: environment.print_result?
      }
    end

    def restore_environment(state)
      environment = Rubycli.environment
      state[:doc_check] ? environment.enable_doc_check! : environment.disable_doc_check!
      state[:strict_input] ? environment.enable_strict_input! : environment.disable_strict_input!
      state[:print_result] ? environment.enable_print_result! : environment.disable_print_result!
    end

    def likely_new_args_value?(token)
      token.include?(',') || token.start_with?('[', '{')
    end
  end
end
