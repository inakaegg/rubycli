# frozen_string_literal: true

require 'psych'

module Rubycli
  module Arguments
    # Converts raw CLI tokens into Ruby primitives when safe to do so.
    class ValueConverter
      LITERAL_PARSE_FAILURE = Object.new

      def convert(value)
        return value if Rubycli.eval_mode? || Rubycli.json_mode?
        return value unless value.is_a?(String)

        trimmed = value.strip
        return value if trimmed.empty?

        if symbol_literal?(trimmed)
          symbol_value = trimmed.delete_prefix(':')
          return symbol_value.to_sym unless symbol_value.empty?
        end

        if literal_like?(trimmed)
          literal = try_literal_parse(value)
          return literal unless literal.equal?(LITERAL_PARSE_FAILURE)
        end

        return nil if null_literal?(trimmed)

        lower = trimmed.downcase
        return true if lower == 'true'
        return false if lower == 'false'
        return value.to_i if integer_string?(trimmed)
        return value.to_f if float_string?(trimmed)

        value
      end

      private

      def symbol_literal?(value)
        return false unless value

        value.start_with?(':') && value.length > 1 && value[1..].match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      end

      def integer_string?(str)
        str =~ /\A-?\d+\z/
      end

      def float_string?(str)
        str =~ /\A-?\d+\.\d+\z/
      end

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
    end
  end
end
