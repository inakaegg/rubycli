# frozen_string_literal: true

module Rubycli
  module CommandLine
    USAGE = <<~USAGE
      Usage: rubycli [--new|-n] [--pre-script=<src>] [--json-args|-j | --eval-args|-e | --eval-lax|-E] [--strict] [--check|-c] <target-path> [<class-or-module>] [-- <cli-args>...]

      Examples:
        rubycli scripts/sample_runner.rb echo --message hello
        rubycli scripts/sample_runner.rb AlternateRunner greet --name Ruby
        rubycli --new lib/akiya_fetcher.rb fetch_simplified_html https://example.com

      Options:
        --new, -n            Instantiate the class/module before invoking CLI commands
        --pre-script=<src>   Evaluate Ruby code and use its result as the exposed target (--init alias; also accepts space-separated form)
        --json-args, -j      Parse all following arguments strictly as JSON (no YAML literals)
        --eval-args, -e      Evaluate following arguments as Ruby code
        --eval-lax, -E       Evaluate as Ruby but fall back to raw strings when parsing fails
        --auto-target, -a    Auto-select the only callable constant when names don't match
        --strict             Enforce documented input types/choices (invalid values abort)
        --check, -c          Validate documentation/comments without executing commands
        (Note: --json-args cannot be combined with --eval-args or --eval-lax)
        (Note: Every option that accepts a value understands both --flag=value and --flag value forms.)

      When <class-or-module> is omitted, Rubycli infers it from the file name in CamelCase.
      Arguments are parsed as safe literals by default; pick a mode above if you need strict JSON or Ruby eval.
      Method return values are printed to STDOUT by default.
      <cli-args> are forwarded to Rubycli unchanged.
    USAGE

    module_function

    def run(argv = ARGV)
      args = Array(argv).dup
      Rubycli.environment.enable_print_result!

      if args.empty?
        $stdout.puts(USAGE)
        return 1
      end

      new_flag = false
      json_mode = false
      eval_mode = false
      eval_lax_mode = false
      constant_mode = nil
      check_mode = false
      pre_script_sources = []

      loop do
        arg = args.first
        break unless arg

        case arg
        when '-h', '--help', 'help'
          $stdout.puts(USAGE)
          return 0
        when '--new', '-n'
          new_flag = true
          args.shift
        when /\A--pre-script=(.+)\z/, /\A--init=(.+)\z/
          label = Regexp.last_match(0).start_with?('--pre-script') ? '--pre-script' : '--init'
          expr = Regexp.last_match(1)
          pre_script_sources << { value: expr, context: "(inline #{label})" }
          args.shift
        when '--pre-script', '--init'
          flag = args.shift
          src = args.shift
          unless src
            warn "[ERROR] #{flag} requires a file path or inline Ruby code"
            return 1
          end
          context = File.file?(src) ? File.expand_path(src) : "(inline #{flag})"
          pre_script_sources << { value: src, context: context }
        when '--json-args', '-j'
          json_mode = true
          args.shift
        when '--eval-args', '-e'
          eval_mode = true
          args.shift
        when '--eval-lax', '-E'
          eval_mode = true
          eval_lax_mode = true
          args.shift
        when '--strict'
          Rubycli.environment.enable_strict_input!
          args.shift
        when '--check', '-c'
          check_mode = true
          Rubycli.environment.enable_doc_check!
          args.shift
        when '--print-result'
         args.shift
        when '--auto-target', '-a'
          constant_mode = :auto
          args.shift
        when '--'
          args.shift
          break
        else
          break
        end
      end

      if args.empty?
        $stdout.puts(USAGE)
        return 1
      end

      target_path = args.shift
      class_or_module = nil
      possible_class = args.first
      if possible_class && possible_class != '--' && possible_class.match?(/\A[A-Z]/)
        class_or_module = args.shift
      end
      args.shift if args.first == '--'

      if json_mode && eval_mode
        warn '[ERROR] --json-args cannot be combined with --eval-args or --eval-lax'
        return 1
      end

      if check_mode && (json_mode || eval_mode)
        warn '[ERROR] --check cannot be combined with --json-args or --eval-args'
        return 1
      end

      if check_mode && !args.empty?
        warn '[ERROR] --check does not accept command arguments'
        return 1
      end

      Rubycli.environment.clear_documentation_issues!

      if check_mode
        return Rubycli::Runner.check(
          target_path,
          class_or_module,
          new: new_flag,
          pre_scripts: pre_script_sources,
          constant_mode: constant_mode
        )
      end

      Rubycli::Runner.execute(
        target_path,
        class_or_module,
        args,
        new: new_flag,
        json: json_mode,
        eval_args: eval_mode,
        eval_lax: eval_lax_mode,
        pre_scripts: pre_script_sources,
        constant_mode: constant_mode
      )

      0
    rescue Rubycli::Runner::PreScriptError => e
      warn "[ERROR] #{e.message}"
      1
    rescue Rubycli::Runner::Error => e
      warn "[ERROR] #{e.message}"
      1
    end
  end
end
