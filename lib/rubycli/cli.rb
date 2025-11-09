require 'set'

module Rubycli
  class CLI
    CommandEntry = Struct.new(:command, :method, :category, :aliases, keyword_init: true) do
      def all_commands
        [command] + aliases
      end
    end

    CommandCatalog = Struct.new(:entries, :alias_map, :duplicates, keyword_init: true) do
      def lookup(command)
        alias_map[command]
      end

      def entries_for(category)
        entries.select { |entry| entry.category == category }
      end

      def commands
        entries.map(&:command)
      end
    end

    def initialize(environment:, argument_parser:, documentation_registry:, help_renderer:, result_emitter:)
      @environment = environment
      @argument_parser = argument_parser
      @documentation_registry = documentation_registry
      @help_renderer = help_renderer
      @result_emitter = result_emitter
      @file_cache = {}
    end

    def run(target, args = ARGV, cli_mode = true)
      debug_log "Starting rubycli with args: #{args.inspect}"
      catalog = command_catalog(target)

      if should_show_help?(args)
        @help_renderer.print_help(target, catalog)
        return 0
      end

      command = args.shift
      entry = resolve_command_entry(catalog, command)

      if entry.nil?
        handle_missing_method(target, catalog, command, args, cli_mode)
      else
        execute_method(entry.method, command, args, cli_mode)
      end
    end

    def available_commands(target)
      command_catalog(target).commands.sort
    end

    def find_method(target, command)
      catalog = command_catalog(target)
      entry = catalog.lookup(command)
      entry ||= catalog.lookup(normalize_command(command)) if command.include?('-')
      entry&.method
    end

    def usage_for_method(command, method)
      @help_renderer.usage_for_method(command, method)
    end

    def method_description(method)
      @help_renderer.method_description(method)
    end

    def command_catalog_for(target)
      command_catalog(target)
    end

    private

    def debug_log(message)
      return unless @environment.debug?

      puts "[DEBUG] #{message}"
    end

    def should_show_help?(args)
      args.empty? || ['help', '--help', '-h'].include?(args[0])
    end

    def resolve_command_entry(catalog, command)
      entry = catalog.lookup(command)
      return entry if entry

      return entry unless command.include?('-')

      normalized = normalize_command(command)
      debug_log "Tried snake_case conversion: #{command} -> #{normalized}" if normalized != command
      catalog.lookup(normalized)
    end

    def handle_missing_method(target, catalog, command, args, cli_mode)
      if target.respond_to?(:call)
        debug_log "Target is callable, treating as lambda/proc"
        args.unshift(command)
        execute_callable(target, args, command, cli_mode)
      else
        error_msg = "Command '#{command}' is not available."
        puts error_msg
        @help_renderer.print_help(target, catalog)
        1
      end
    end

    def execute_callable(target, args, command, cli_mode)
      method = target.method(:call)
      pos_args, kw_args = @argument_parser.parse(args, method)
      Rubycli.apply_argument_coercions(pos_args, kw_args)
      @argument_parser.validate_inputs(method, pos_args, kw_args)
      begin
        result = Rubycli.call_target(target, pos_args, kw_args)
        @result_emitter.emit(result)
        0
      rescue StandardError => e
        handle_execution_error(e, command, method, pos_args, kw_args, cli_mode)
      end
    end

    def execute_method(method_obj, command, args, cli_mode)
      if method_obj.parameters.empty? && !args.empty?
        execute_parameterless_method(method_obj, command, args, cli_mode)
      else
        execute_method_with_params(method_obj, command, args, cli_mode)
      end
    end

    def execute_parameterless_method(method_obj, command, args, cli_mode)
      if help_requested_for_parameterless?(args)
        puts usage_for_method(command, method_obj)
        return 0
      end

      begin
        result = method_obj.call
        debug_log "Parameterless method returned: #{result.inspect}"
        if result
          return run(result, args, false)
        end
        0
      rescue StandardError => e
        handle_execution_error(e, command, method_obj, [], {}, cli_mode)
      end
    end

    def execute_method_with_params(method_obj, command, args, cli_mode)
      pos_args, kw_args = @argument_parser.parse(args, method_obj)
      Rubycli.apply_argument_coercions(pos_args, kw_args)
      @argument_parser.validate_inputs(method_obj, pos_args, kw_args)

      if should_show_method_help?(pos_args, kw_args)
        puts usage_for_method(command, method_obj)
        return 0
      end

      begin
        result = Rubycli.call_target(method_obj, pos_args, kw_args)
        @result_emitter.emit(result)
        0
      rescue StandardError => e
        handle_execution_error(e, command, method_obj, pos_args, kw_args, cli_mode)
      end
    end

    def should_show_method_help?(pos_args, kw_args)
      (kw_args.key?(:help) && kw_args.delete(:help)) || pos_args.include?('help')
    end

    def help_requested_for_parameterless?(args)
      return false if args.nil? || args.empty?

      args.all? { |arg| help_argument?(arg) }
    end

    def help_argument?(arg)
      %w[help --help -h].include?(arg)
    end

    def handle_execution_error(error, command, method_obj, pos_args, kw_args, cli_mode)
      if cli_mode && !arguments_match?(method_obj, pos_args, kw_args) && usage_error?(error)
        puts "Error: #{error.message}"
        puts usage_for_method(command, method_obj)
        1
      else
        raise error
      end
    end

    def usage_error?(error)
      msg = error.message
      msg.include?('wrong number of arguments') ||
        msg.include?('missing keyword') ||
        msg.include?('unknown keyword') ||
        msg.include?('no implicit conversion')
    end

    def arguments_match?(method, pos_args, kw_args)
      return false unless method

      params = method.parameters
      positional_match = check_positional_arguments(params, pos_args)
      keyword_match = check_keyword_arguments(params, kw_args)

      positional_match && keyword_match
    end

    def check_positional_arguments(params, pos_args)
      req_pos = params.count { |type, _| type == :req }
      opt_pos = params.count { |type, _| type == :opt }
      has_rest = params.any? { |type, _| type == :rest }

      if has_rest
        pos_args.size >= req_pos
      else
        (req_pos..(req_pos + opt_pos)).cover?(pos_args.size)
      end
    end

    def check_keyword_arguments(params, kw_args)
      known_keys = params.select { |t, _| %i[key keyreq keyrest].include?(t) }.map { |_, n| n }
      unknown_keys = kw_args.keys - known_keys
      req_kw = params.select { |type, _| type == :keyreq }.map { |_, name| name }
      has_keyrest = params.any? { |type, _| type == :keyrest }

      required_keywords_present = req_kw.all? { |k| kw_args.key?(k) }
      no_unknown_keywords = has_keyrest || unknown_keys.empty?

      required_keywords_present && no_unknown_keywords
    end

    def command_catalog(target)
      if target.is_a?(Module) || target.is_a?(Class)
        entries = collect_singleton_entries(target)
        alias_map = build_alias_map(entries)
        CommandCatalog.new(entries: entries, alias_map: alias_map, duplicates: Set.new)
      else
        build_instance_catalog(target)
      end
    end

    def collect_singleton_entries(target)
      method_names = target.singleton_class.public_instance_methods(false)
      method_names.each_with_object([]) do |name, memo|
        method_obj = safe_method_lookup(target, name)
        next unless exposable_method?(method_obj)

        memo << CommandEntry.new(command: name.to_s, method: method_obj, category: :class, aliases: [])
      end.sort_by { |entry| entry.command }
    end

    def build_instance_catalog(target)
      instance_methods = collect_instance_methods(target)
      class_methods = collect_class_methods(target)

      duplicate_names = instance_methods.keys & class_methods.keys
      entries = []

      instance_methods.keys.sort.each do |name|
        method_obj = instance_methods[name]
        aliases = duplicate_names.include?(name) ? ["instance::#{name}"] : []
        entries << CommandEntry.new(command: name, method: method_obj, category: :instance, aliases: aliases)
      end

      class_methods.keys.sort.each do |name|
        method_obj = class_methods[name]
        entries << CommandEntry.new(command: "class::#{name}", method: method_obj, category: :class, aliases: [])
      end

      alias_map = build_alias_map(entries)
      CommandCatalog.new(entries: entries, alias_map: alias_map, duplicates: duplicate_names.sort)
    end

    def collect_instance_methods(target)
      collect_method_map(target.public_methods(false)) { |name| safe_method_lookup(target, name) }
    end

    def collect_class_methods(target)
      klass = target.class
      collect_method_map(klass.singleton_class.public_instance_methods(false)) { |name| safe_method_lookup(klass, name) }
    end

    def collect_method_map(method_names)
      method_names.each_with_object({}) do |name, memo|
        method_obj = yield(name)
        next unless exposable_method?(method_obj)

        memo[name.to_s] = method_obj
      end
    end

    def safe_method_lookup(target, name)
      target.method(name)
    rescue NameError
      nil
    end

    def exposable_method?(method_obj)
      return false unless method_obj&.source_location
      return false if accessor_generated_method?(method_obj)

      true
    end

    def build_alias_map(entries)
      entries.each_with_object({}) do |entry, memo|
        entry.all_commands.each do |command|
          memo[command] = entry
        end
      end
    end

    def normalize_command(command)
      return command unless command

      if command.start_with?('class::')
        base = command.split('class::', 2).last
        "class::#{base.tr('-', '_')}"
      elsif command.start_with?('instance::')
        base = command.split('instance::', 2).last
        "instance::#{base.tr('-', '_')}"
      else
        command.tr('-', '_')
      end
    end

    def accessor_generated_method?(method_obj)
      location = method_obj.source_location
      return false unless location

      file, line = location
      lines = (@file_cache[file] ||= File.readlines(file, chomp: true))
      line_content = lines[line - 1]
      return false unless line_content

      line_content.match?(/\battr_(reader|writer|accessor)\b/)
    rescue Errno::ENOENT
      false
    end
  end
end
