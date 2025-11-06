require 'psych'
require_relative 'type_utils'

module Rubycli
  class ArgumentParser
    include TypeUtils

    def initialize(environment:, documentation_registry:, json_coercer:, debug_logger:)
      @environment = environment
      @documentation_registry = documentation_registry
      @json_coercer = json_coercer
      @debug_logger = debug_logger
    end

    def parse(args, method = nil)
      pos_args = []
      kw_args = {}

      kw_param_names = extract_keyword_parameter_names(method)
      debug_log "Available keyword parameters: #{kw_param_names.inspect}"

      metadata = method ? @documentation_registry.metadata_for(method) : { options: [], returns: [], summary: nil }
      option_defs = metadata[:options] || []
      cli_aliases = build_cli_alias_map(option_defs)
      option_lookup = build_option_lookup(option_defs)
      type_converters = build_type_converter_map(option_defs)

      i = 0
      while i < args.size
        token = args[i]

        if token == '--'
          rest_tokens = (args[(i + 1)..-1] || []).map { |value| convert_arg(value) }
          pos_args.concat(rest_tokens)
          break
        end

        if option_token?(token)
          i = process_option_token(
            token,
            args,
            i,
            kw_param_names,
            kw_args,
            cli_aliases,
            option_lookup,
            type_converters
          )
        elsif assignment_token?(token)
          process_assignment_token(token, kw_args)
        else
          pos_args << convert_arg(token)
        end

        i += 1
      end

      debug_log "Final parsed - pos_args: #{pos_args.inspect}, kw_args: #{kw_args.inspect}"
      [pos_args, kw_args]
    end

    private

    def debug_log(message)
      return unless @debug_logger

      @debug_logger.call(message)
    end

    def extract_keyword_parameter_names(method)
      return [] unless method

      method.parameters
            .select { |type, _| %i[key keyreq].include?(type) }
            .map { |_, name| name.to_s }
    end

    def option_token?(token)
      token =~ /\A-{1,2}([a-zA-Z0-9_-]+)(?:=(.*))?\z/
    end

    def assignment_token?(token)
      !split_assignment_token(token).nil?
    end

    def process_option_token(
      token,
      args,
      current_index,
      kw_param_names,
      kw_args,
      cli_aliases,
      option_lookup,
      type_converters
    )
      token =~ /\A-{1,2}([a-zA-Z0-9_-]+)(?:=(.*))?\z/
      cli_key = Regexp.last_match(1).tr('-', '_')
      embedded_value = Regexp.last_match(2)

      resolved_cli_key = cli_aliases.fetch(cli_key, cli_key)
      debug_log "Processing option '#{Regexp.last_match(1)}' -> '#{resolved_cli_key}'"

      resolved_key = resolve_keyword_parameter(resolved_cli_key, kw_param_names)
      final_key = resolved_key || resolved_cli_key
      final_key_sym = final_key.to_sym

      option_meta = option_lookup[final_key_sym]
      requires_value = option_meta ? option_meta[:requires_value] : nil
      option_label = option_meta&.long || "--#{final_key.tr('_', '-')}"

      value_capture, current_index = if embedded_value
                                       [embedded_value, current_index]
                                     elsif option_meta
                                       capture_option_value(
                                         option_meta,
                                         args,
                                         current_index,
                                         requires_value
                                       )
                                     elsif current_index + 1 < args.size && !looks_like_option?(args[current_index + 1])
                                       current_index += 1
                                       [args[current_index], current_index]
                                     else
                                       ['true', current_index]
                                     end

      if requires_value && (value_capture.nil? || value_capture == 'true')
        raise ArgumentError, "Option '#{option_label}' requires a value"
      end

      converted_value = convert_option_value(
        final_key_sym,
        value_capture,
        option_meta,
        type_converters
      )

      kw_args[final_key_sym] = converted_value
      current_index
    end

    def capture_option_value(option_meta, args, current_index, requires_value)
      new_index = current_index
      value = if option_meta[:boolean_flag]
                if new_index + 1 < args.size && TypeUtils.boolean_string?(args[new_index + 1])
                  new_index += 1
                  args[new_index]
                else
                  'true'
                end
              elsif option_meta[:optional_value]
                if new_index + 1 < args.size && !looks_like_option?(args[new_index + 1])
                  new_index += 1
                  args[new_index]
                else
                  true
                end
              elsif requires_value == false
                'true'
              elsif requires_value
                if new_index + 1 >= args.size
                  raise ArgumentError, "Option '#{option_meta.long}' requires a value"
                end
                new_index += 1
                args[new_index]
              elsif new_index + 1 < args.size && !looks_like_option?(args[new_index + 1])
                new_index += 1
                args[new_index]
              else
                'true'
              end
      [value, new_index]
    end

    def process_assignment_token(token, kw_args)
      key, value = split_assignment_token(token)
      kw_args[key.to_sym] = convert_arg(value)
    end

    def split_assignment_token(token)
      return nil unless token&.include?('=')

      key, value = token.split('=', 2)
      return nil if key.nil? || key.empty? || value.nil?
      return nil unless key.match?(/\A[a-zA-Z_]\w*\z/)

      [key, value]
    end

    def resolve_keyword_parameter(cli_key, kw_param_names)
      exact_match = kw_param_names.find { |name| name == cli_key }
      return exact_match if exact_match

      matching_keys = kw_param_names.select { |name| name.start_with?(cli_key) }
      debug_log "Prefix matching for '#{cli_key}': found #{matching_keys.inspect}"

      if matching_keys.size == 1
        debug_log "Unambiguous prefix match found: '#{matching_keys.first}'"
        matching_keys.first
      else
        debug_log "No unique match found for '#{cli_key}'"
        nil
      end
    end

    def convert_arg(arg)
      return arg if Rubycli.eval_mode? || Rubycli.json_mode?
      return arg unless arg.is_a?(String)

      trimmed = arg.strip
      return arg if trimmed.empty?

      if literal_like?(trimmed)
        literal = try_literal_parse(arg)
        return literal unless literal.equal?(LITERAL_PARSE_FAILURE)
      end

      return nil if null_literal?(trimmed)

      lower = trimmed.downcase
      return true if lower == 'true'
      return false if lower == 'false'
      return arg.to_i if integer_string?(trimmed)
      return arg.to_f if float_string?(trimmed)

      arg
    end

    def integer_string?(str)
      str =~ /\A-?\d+\z/
    end

    def float_string?(str)
      str =~ /\A-?\d+\.\d+\z/
    end

    LITERAL_PARSE_FAILURE = Object.new

    def try_literal_parse(value)
      return LITERAL_PARSE_FAILURE unless value.is_a?(String)

      trimmed = value.strip
      return value if trimmed.empty?

      literal = Psych.safe_load(trimmed, aliases: false)
      return literal unless literal.nil? && !null_literal?(trimmed)

      LITERAL_PARSE_FAILURE
    rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::Exception
      LITERAL_PARSE_FAILURE
    end

    def null_literal?(value)
      return false unless value

      %w[null ~].include?(value.downcase)
    end

    def literal_like?(value)
      return false unless value
      return true if value.start_with?('[', '{', '"', "'")
      return true if value.start_with?('---')
      return true if value.match?(/\A(?:true|false|null|nil)\z/i)

      false
    end


    def build_cli_alias_map(option_defs)
      option_defs.each_with_object({}) do |opt, memo|
        next unless opt.short

        key = opt.short.delete_prefix('-')
        memo[key] = opt.keyword.to_s
      end
    end

    def build_option_lookup(option_defs)
      option_defs.each_with_object({}) do |opt, memo|
        memo[opt.keyword] = opt
      end
    end

    def build_type_converter_map(option_defs)
      option_defs.each_with_object({}) do |opt, memo|
        next if opt.types.nil? || opt.types.empty?

        converter = build_converter_for_types(opt.types)
        memo[opt.keyword] = converter if converter
      end
    end

    def build_converter_for_types(types)
      return nil if types.empty?

      allow_nil = types.any? { |type| nil_type?(type) }
      converters = types.map { |type| converter_for_single_type(type) }.compact

      return nil if converters.empty? && !allow_nil

      lambda do |value|
        return nil if value.nil? && allow_nil

        if allow_nil && value.is_a?(String) && value.strip.casecmp('nil').zero?
          next nil
        end

        if converters.empty?
          value
        else
          last_error = nil
          converters.each do |converter|
            begin
              result = converter.call(value)
              return result
            rescue StandardError => e
              last_error = e
            end
          end
          raise last_error || ArgumentError.new("Could not convert value '#{value}'")
        end
      end
    end

    def converter_for_single_type(type)
      normalized = type.to_s.strip

      return nil if nil_type?(normalized)

      case normalized
      when 'String'
        ->(value) { value }
      when 'Integer', 'Fixnum'
        ->(value) { Integer(value) }
      when 'Float'
        ->(value) { Float(value) }
      when 'Numeric'
        ->(value) { Float(value) }
      when 'Boolean', 'TrueClass', 'FalseClass'
        ->(value) { TypeUtils.convert_boolean(value) }
      when 'Symbol'
        ->(value) { value.to_sym }
      when 'BigDecimal', 'Decimal'
        require 'bigdecimal'
        ->(value) { BigDecimal(value) }
      when 'Date'
        require 'date'
        ->(value) { Date.parse(value) }
      when 'Time', 'DateTime'
        require 'time'
        ->(value) { Time.parse(value) }
      when 'JSON', 'Hash'
        ->(value) { JSON.parse(value) }
      else
        if normalized.start_with?('Array<') && normalized.end_with?('>')
          inner = normalized[6..-2].strip
          element_converter = converter_for_single_type(inner)
          ->(value) { TypeUtils.parse_list(value).map { |item| element_converter ? element_converter.call(item) : item } }
        elsif normalized.end_with?('[]')
          inner = normalized[0..-3]
          element_converter = converter_for_single_type(inner)
          ->(value) { TypeUtils.parse_list(value).map { |item| element_converter ? element_converter.call(item) : item } }
        elsif normalized == 'Array'
          ->(value) { TypeUtils.parse_list(value) }
        else
          nil
        end
      end
    end

    def convert_option_value(keyword, value, option_meta, type_converters)
      if Rubycli.eval_mode? || Rubycli.json_mode?
        return convert_arg(value)
      end

      converter = type_converters[keyword]
      converted_value = convert_arg(value)
      return converted_value unless converter

      original_input = value if value.is_a?(String)
      expects_list = option_meta && option_meta.types.any? { |type|
        type.to_s.end_with?('[]') || type.to_s.start_with?('Array<')
      }

      value_for_converter = converted_value
      if expects_list && original_input && converted_value.is_a?(Numeric) && original_input.include?(',')
        value_for_converter = original_input
      end

      converter.call(value_for_converter)
    rescue StandardError => e
      option_label = option_meta&.long || option_meta&.short || keyword
      raise ArgumentError, "Value '#{value}' for option '#{option_label}' is invalid: #{e.message}"
    end

    def looks_like_option?(token)
      return false unless token
      return false if token == '--'

      token.start_with?('-') && !(token =~ /\A-?\d+(\.\d+)?\z/)
    end
  end
end
