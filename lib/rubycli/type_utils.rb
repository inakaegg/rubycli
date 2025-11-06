module Rubycli
  module TypeUtils
    module_function

    def nil_type?(type)
      %w[nil NilClass].include?(type)
    end

    def boolean_type?(type)
      %w[Boolean TrueClass FalseClass].include?(type)
    end

    def normalize_type_list(types)
      Array(types).compact.flat_map { |type| normalize_type_token(type) }.map(&:strip).reject(&:empty?).uniq
    end

    def normalize_type_token(token)
      trimmed = token.to_s.strip
      trimmed = trimmed.delete_prefix('@')
      return '' if trimmed.empty?

      trimmed = trimmed[1..-2].strip if trimmed.start_with?('(') && trimmed.end_with?(')')
      trimmed = trimmed.sub(/\Atype\s*:\s*/i, '').strip
      return '' if trimmed.empty?

      if trimmed.include?('<') && trimmed.end_with?('>')
        trimmed
      elsif trimmed.end_with?('[]')
        base = trimmed[0..-3]
        base = base.capitalize if base == base.downcase
        "#{base}[]"
      else
        trimmed
      end
    end

    def analyze_placeholder(value_placeholder)
      return { optional: false, list: false, base: nil } unless value_placeholder

      trimmed = value_placeholder.strip
      optional = trimmed.start_with?('[') && trimmed.end_with?(']')
      core = optional ? trimmed[1..-2].strip : trimmed.dup
      sanitized = core.gsub(/\[|\]/, '')
      sanitized = sanitized.gsub(/\.\.\./, '')
      list = sanitized.include?(',') || core.include?('...') || core.include?('[,')
      token = sanitized.split(',').first.to_s.strip
      token = token.gsub(/[^A-Za-z0-9_]/, '')
      token = nil if token.empty?

      { optional: optional, list: list, base: token }
    end

    def infer_types_from_placeholder(types, placeholder_info, include_optional_boolean: true)
      working = types.dup

      if working.empty?
        if placeholder_info[:optional]
          inferred = if placeholder_info[:list]
                       include_optional_boolean ? ['Boolean', 'String[]'] : ['String[]']
                     else
                       include_optional_boolean ? ['Boolean', 'String'] : ['String']
                     end
          working.concat(inferred)
        elsif placeholder_info[:list]
          working << 'String[]'
        elsif placeholder_info[:base]
          working << 'String'
        end
      elsif placeholder_info[:optional] && include_optional_boolean
        working.unshift('Boolean') unless working.any? { |type| boolean_type?(type) }
      end

      working.uniq
    end

    def determine_requires_value(value_placeholder:, types:, boolean_flag:, optional_value:)
      return nil if optional_value
      return false if boolean_flag

      value_present = !value_placeholder.nil?
      non_boolean_types = types.reject { |type| boolean_type?(type) || nil_type?(type) }

      if value_present
        true
      elsif non_boolean_types.any?
        true
      else
        false
      end
    end

    def normalize_long_option(option)
      return nil unless option
      option.start_with?('--') ? option : "--#{option.delete_prefix('-')}"
    end

    def normalize_short_option(option)
      return nil unless option
      option.start_with?('-') ? option : "-#{option}"
    end

    def default_placeholder_for(keyword)
      keyword.to_s.upcase
    end

    def parse_list(value)
      return [] if value.nil?

      value.to_s.split(',').map(&:strip).reject(&:empty?)
    end

    def convert_boolean(value)
      return value if [true, false].include?(value)

      str = value.to_s.strip.downcase
      case str
      when 'true', 't', 'yes', 'y', '1'
        true
      when 'false', 'f', 'no', 'n', '0'
        false
      else
        raise ArgumentError, "Cannot convert to boolean: #{value}"
      end
    end

    def boolean_string?(value)
      return false if value.nil?

      %w[true false t f yes no y n 1 0].include?(value.to_s.strip.downcase)
    end
  end
end
