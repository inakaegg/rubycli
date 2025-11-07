module Rubycli
  # Environment captures runtime flags and configuration derived from ENV / argv.
  class Environment
    def initialize(env: ENV, argv: nil)
      @env = env
      @argv = argv
      @debug = env['RUBYCLI_DEBUG'] == 'true'
      @print_result = env['RUBYCLI_PRINT_RESULT'] == 'true'
      scrub_argv_flags!
    end

    def debug?
      @debug
    end

    def print_result?
      @print_result
    end

    def strict_mode?
      value = fetch_env_value('RUBYCLI_STRICT', 'OFF')
      !%w[off 0 false].include?(value.downcase)
    end

    def allow_param_comments?
      value = fetch_env_value('RUBYCLI_ALLOW_PARAM_COMMENT', 'ON')
      %w[on 1 true].include?(value)
    end

    def constant_resolution_mode
      value = fetch_env_value('RUBYCLI_AUTO_TARGET', 'strict')
      return :auto if %w[auto on true yes 1].include?(value)

      :strict
    end

    def handle_documentation_issue(message, file: nil, line: nil)
      location = nil
      if file
        expanded = File.expand_path(file)
        relative_prefix = File.expand_path(Dir.pwd) + '/'
        display_path = expanded.start_with?(relative_prefix) ? expanded.delete_prefix(relative_prefix) : expanded
        location = line ? "#{display_path}:#{line}" : display_path
      end

      formatted_message = if location
        "#{location} #{message}"
      else
        message
      end

      warn "[WARN] Rubycli documentation mismatch: #{formatted_message}" if strict_mode?
    end

    def enable_print_result!
      @print_result = true
    end

    private

    def fetch_env_value(key, default)
      (@env.fetch(key, default) || default).to_s.strip.downcase
    end

    def scrub_argv_flags!
      return unless @argv

      remove_all_flags!(@argv, '--debug') { @debug = true }
      remove_all_flags!(@argv, '--print-result') { @print_result = true }
    end

    def remove_all_flags!(argv, flag)
      found = false
      loop do
        index = argv.index(flag)
        break unless index

        argv.delete_at(index)
        found = true
      end
      yield if found && block_given?
    end
  end
end
