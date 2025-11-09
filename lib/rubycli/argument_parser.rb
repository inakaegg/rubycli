require_relative 'type_utils'
require_relative 'arguments/token_stream'
require_relative 'arguments/value_converter'

module Rubycli
  class ArgumentParser
    include TypeUtils

    def initialize(environment:, documentation_registry:, json_coercer:, debug_logger:)
      @environment = environment
      @documentation_registry = documentation_registry
      @json_coercer = json_coercer
      @debug_logger = debug_logger
      @value_converter = Arguments::ValueConverter.new
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

      stream = Arguments::TokenStream.new(args)

      until stream.finished?
        token = stream.current

        if token == '--'
          stream.advance
          rest_tokens = stream.consume_remaining.map { |value| convert_arg(value) }
          pos_args.concat(rest_tokens)
          break
        elsif option_token?(token)
          stream.advance
          process_option_token(
            token,
            stream,
            kw_param_names,
            kw_args,
            cli_aliases,
            option_lookup,
            type_converters
          )
        elsif assignment_token?(token)
          stream.advance
          process_assignment_token(token, kw_args)
        else
          pos_args << convert_arg(token)
          stream.advance
        end
      end

      debug_log "Final parsed - pos_args: #{pos_args.inspect}, kw_args: #{kw_args.inspect}"
      [pos_args, kw_args]
    end

    def validate_inputs(method_obj, positional_args, keyword_args)
      return unless method_obj

      metadata = @documentation_registry.metadata_for(method_obj)
      validate_positional_arguments(method_obj, metadata, positional_args)
      validate_keyword_arguments(metadata, keyword_args)
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
      stream,
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

      value_capture = if embedded_value
                        embedded_value
                      elsif option_meta
                        capture_option_value(
                          option_meta,
                          stream,
                          requires_value
                        )
                      elsif (next_token = stream.current) && !looks_like_option?(next_token)
                        stream.consume
                      else
                        'true'
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
    end
    def capture_option_value(option_meta, stream, requires_value)
      if option_meta[:boolean_flag]
        if (next_token = stream.current) && TypeUtils.boolean_string?(next_token)
          return stream.consume
        end
        return 'true'
      elsif option_meta[:optional_value]
        if (next_token = stream.current) && !looks_like_option?(next_token)
          return stream.consume
        end
        return true
      elsif requires_value == false
        return 'true'
      elsif requires_value
        next_token = stream.current
        raise ArgumentError, "Option '#{option_meta.long}' requires a value" unless next_token

        return stream.consume
      elsif (next_token = stream.current) && !looks_like_option?(next_token)
        return stream.consume
      else
        return 'true'
      end
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
      @value_converter.convert(arg)
    end

    def validate_positional_arguments(method_obj, metadata, positional_args)
      return if positional_args.nil? || positional_args.empty?

      positional_map = metadata[:positionals_map] || {}
      ordered_params = method_obj.parameters.select { |type, _| %i[req opt].include?(type) }

      ordered_params.each_with_index do |(_, name), index|
        definition = positional_map[name]
        next unless definition
        next if index >= positional_args.size

        label = definition.label || definition.placeholder || name.to_s.upcase
        enforce_value_against_definition(definition, positional_args[index], label)
      end
    end

    def validate_keyword_arguments(metadata, keyword_args)
      return if keyword_args.nil? || keyword_args.empty?

      option_lookup = build_option_lookup(metadata[:options] || [])
      keyword_args.each do |key, value|
        definition = option_lookup[key.to_sym]
        next unless definition

        label = definition.long || "--#{key.to_s.tr('_', '-')}"
        enforce_value_against_definition(definition, value, label)
      end
    end

    def enforce_value_against_definition(definition, value, label)
      return unless definition

      return if type_allowed?(definition.types, value)

      Array(value.is_a?(Array) ? value : [value]).each do |entry|
        next if literal_allowed?(definition.allowed_values, entry)
        next if type_allowed?(definition.types, entry)

        description = allowed_value_description(definition)
        message = "Value #{entry.inspect} for #{label} is not allowed#{description ? ": #{description}" : ''}"
        @environment.handle_input_violation(message)
      end
    end

    def literal_allowed?(allowed_entries, value)
      entries = Array(allowed_entries).compact
      return false if entries.empty?

      entries.any? { |entry| literal_match?(entry[:value], value) }
    end

    def literal_match?(candidate, value)
      case candidate
      when Symbol
        value.is_a?(Symbol) && value == candidate
      when String
        value.is_a?(String) && value == candidate
      when Integer
        value.is_a?(Integer) && value == candidate
      when Float
        value.is_a?(Float) && value == candidate
      when TrueClass, FalseClass
        value == candidate
      when NilClass
        value.nil?
      else
        value == candidate
      end
    end

    def type_allowed?(types, value)
      tokens = Array(types).compact
      return false if tokens.empty?

      tokens.any? { |token| matches_type_token?(token, value) }
    end

    def allowed_value_description(definition)
      literal_descriptions = Array(definition.allowed_values).map { |entry| format_literal_value(entry[:value]) }.reject(&:empty?)
      type_descriptions = Array(definition.types).map(&:to_s).reject { |token| literal_hint_token?(token) }
      combined = (literal_descriptions + type_descriptions).uniq.reject(&:empty?)
      return nil if combined.empty?

      "allowed values are #{combined.join(', ')}"
    end

    def matches_type_token?(token, value)
      normalized = token.to_s.strip
      return true if normalized.empty?

      if (inner = array_inner_type(normalized))
        return false unless value.is_a?(Array)
        return value.all? { |element| matches_type_token?(inner, element) }
      end

      case normalized
      when 'Boolean'
        value.is_a?(TrueClass) || value.is_a?(FalseClass)
      when 'JSON'
        value.is_a?(Hash) || value.is_a?(Array)
      when 'nil', 'NilClass'
        value.nil?
      else
        klass = constant_for_token(normalized)
        return value.is_a?(klass) if klass

        false
      end
    end

    def array_inner_type(token)
      if token.end_with?('[]')
        token[0..-3]
      elsif token.start_with?('Array<') && token.end_with?('>')
        token[6..-2].strip
      else
        nil
      end
    end

    def nil_type_token?(token)
      token.to_s.strip.casecmp('nil').zero? || token.to_s.strip.casecmp('NilClass').zero?
    end

    def safe_constant_lookup(name)
      parts = name.to_s.split('::').reject(&:empty?)
      return nil if parts.empty?

      context = Object
      parts.each do |const_name|
        return nil unless context.const_defined?(const_name, false)

        context = context.const_get(const_name)
      end
      context
    rescue NameError
      nil
    end

    def constant_for_token(token)
      normalized = token.to_s
      case normalized
      when 'Fixnum'
        return Integer
      when 'Date', 'DateTime'
        require 'date'
      when 'Time'
        require 'time'
      when 'BigDecimal', 'Decimal'
        require 'bigdecimal'
      when 'Pathname'
        require 'pathname'
      when 'Struct'
        return Struct
      end

      safe_constant_lookup(normalized)
    rescue LoadError
      safe_constant_lookup(normalized)
    end

    def format_literal_value(value)
      case value
      when Symbol
        ":#{value}"
      when String
        value.inspect
      when Integer, Float
        value.to_s
      when TrueClass, FalseClass
        value.to_s
      when NilClass
        'nil'
      else
        value.inspect
      end
    end

    def literal_hint_token?(token)
      token = token.to_s.strip
      return false if token.empty?

      token.start_with?('%i[', '%I[', '%w[', '%W[')
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
        ->(value) {
          return value if value.is_a?(BigDecimal)

          if value.is_a?(String)
            BigDecimal(value)
          else
            BigDecimal(value.to_s)
          end
        }
      when 'Date'
        require 'date'
        ->(value) { Date.parse(value) }
      when 'Time', 'DateTime'
        require 'time'
        ->(value) { Time.parse(value) }
      when 'JSON', 'Hash'
        ->(value) { JSON.parse(value) }
      when 'Pathname'
        require 'pathname'
        ->(value) {
          return value if value.is_a?(Pathname)

          Pathname.new(value.to_s)
        }
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
