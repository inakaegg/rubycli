# frozen_string_literal: true

require_relative '../types'
require_relative '../type_utils'

module Rubycli
  module Documentation
    class MetadataParser
      include TypeUtils

      def initialize(environment:)
        @environment = environment
      end

      def empty_metadata
        {
          options: [],
          returns: [],
          summary: nil,
          summary_lines: [],
          detail_lines: [],
          positionals: [],
          positionals_map: {}
        }
      end

      def parse(comment_lines, method_obj)
        metadata = empty_metadata
        return metadata if comment_lines.empty?

        summary_compact_lines = []
        summary_display_lines = []
        detail_lines = []
        summary_phase = true

        comment_lines.each do |content|
          stripped = content.strip
          if summary_phase && stripped.empty?
            summary_display_lines << ""
            next
          end

          if (option = parse_tagged_param_line(stripped, method_obj))
            if option.is_a?(OptionDefinition)
              if method_accepts_keyword?(method_obj, option.keyword)
                metadata[:options].reject! { |existing| existing.keyword == option.keyword }
                metadata[:options] << option
              else
                metadata[:positionals] << option_to_positional_definition(option)
              end
            elsif option.is_a?(PositionalDefinition)
              metadata[:positionals] << option
            end
            summary_phase = false
            next
          end

          if (return_meta = parse_return_metadata(stripped))
            metadata[:returns] << return_meta
            summary_phase = false
            next
          end

          if (option = parse_tagless_option_line(stripped, method_obj))
            metadata[:options].reject! { |existing| existing.keyword == option.keyword }
            metadata[:options] << option
            summary_phase = false
            next
          end

          if (positional = parse_positional_line(stripped))
            metadata[:positionals] << positional
            summary_phase = false
            next
          end
          if summary_phase
            summary_display_lines << content.rstrip
            summary_compact_lines << stripped unless stripped.empty?
          else
            detail_lines << content.rstrip
          end
        end

        summary_text = summary_compact_lines.join(' ')
        summary_text = nil if summary_text.empty?
        metadata[:summary] = summary_text
        metadata[:summary_lines] = trim_blank_edges(summary_display_lines)
        metadata[:detail_lines] = trim_blank_edges(detail_lines)

        defaults = extract_parameter_defaults(method_obj)
        align_and_validate_parameter_docs(method_obj, metadata, defaults)

        metadata
      end

      def trim_blank_edges(lines)
        return [] if lines.nil? || lines.empty?

        first = lines.index { |line| line && !line.strip.empty? }
        return [] unless first

        last = lines.rindex { |line| line && !line.strip.empty? }
        return [] unless last

        lines[first..last]
      end

      def parse_tagged_param_line(line, method_obj)
        return nil unless line.start_with?('@param')

        source_file = nil
        source_line = nil
        if method_obj.respond_to?(:source_location)
          source_file, source_line = method_obj.source_location
        end
        line_number = source_line ? [source_line - 1, 1].max : nil

        unless @environment.allow_param_comments?
          source_file, source_line = method_obj.source_location
          @environment.handle_documentation_issue(
            '@param notation is disabled. Enable it via ENV RUBYCLI_ALLOW_PARAM_COMMENT=ON.',
            file: source_file,
            line: line_number
          )
          return nil if @environment.doc_check_mode?
        end

        pattern = /\A@param\s+([a-zA-Z0-9_]+)(?:\s+\[([^\]]+)\])?(?:\s+\(([^)]+)\))?(?:\s+(.*))?\z/
        match = pattern.match(line)
        return nil unless match

        param_name = match[1]
        type_str = match[2]
        option_tokens = combine_bracketed_tokens(match[3]&.split(/\s+/) || [])
        description = match[4]&.strip
        description = nil if description&.empty?

        raw_types = parse_type_annotation(type_str)
        types, allowed_values = partition_type_tokens(raw_types)

        long_option = nil
        short_option = nil
        value_name = nil
        type_token = nil

        unless option_tokens.empty?
          normalized = option_tokens.flat_map { |token| token.split('/') }
          normalized.each do |token|
            token_without_at = token.start_with?('@') ? token[1..] : token
            if token.start_with?('--')
              if (eq_index = token.index('='))
                long_option = token[0...eq_index]
                inline_value = token[(eq_index + 1)..]
                if value_name.nil? && inline_value && !inline_value.strip.empty?
                  value_name = inline_value.strip
                  next
                end
              else
                long_option = token
              end
            elsif token.start_with?('-')
              if (eq_index = token.index('='))
                short_option = token[0...eq_index]
                inline_value = token[(eq_index + 1)..]
                if value_name.nil? && inline_value && !inline_value.strip.empty?
                  value_name = inline_value.strip
                  next
                end
              else
                short_option = token
              end
            elsif value_name.nil? && placeholder_token?(token_without_at)
              value_name = token_without_at
            elsif type_token.nil? && type_token_candidate?(token)
              type_token = token
            elsif value_name.nil?
              value_name = token_without_at
            end
          end
        end

        long_option ||= "--#{param_name.tr('_', '-')}"

        if (types.nil? || types.empty?) && type_token
          inline_raw_types = parse_type_annotation(type_token)
          inline_types, inline_allowed = partition_type_tokens(inline_raw_types)
          types = inline_types
          allowed_values = merge_allowed_values(allowed_values, inline_allowed)
        end

        option_def = build_option_definition(
          param_name.to_sym,
          long_option,
          short_option,
          value_name,
          types,
          description,
          inline_type_annotation: !type_token.nil?,
          doc_format: :tagged_param,
          allowed_values: allowed_values
        )

        param_symbol = param_name.to_sym
        role = parameter_role(method_obj, param_symbol)

        if role == :positional
          placeholder = option_def.value_name || default_placeholder_for(option_def.keyword)
          return PositionalDefinition.new(
            placeholder: placeholder,
            label: placeholder,
            types: option_def.types,
            description: option_def.description,
            param_name: param_symbol,
            doc_format: option_def.doc_format,
            allowed_values: option_def.allowed_values
          )
        elsif role == :keyword
          return option_def
        end

        unless method_accepts_keyword?(method_obj, param_symbol)
          placeholder = option_def.value_name || default_placeholder_for(option_def.keyword)
          return PositionalDefinition.new(
            placeholder: placeholder,
            label: placeholder,
            types: option_def.types,
            description: option_def.description,
            param_name: param_symbol,
            doc_format: option_def.doc_format,
            allowed_values: option_def.allowed_values
          )
        end

        option_def
      end

      def parse_tagless_option_line(line, method_obj)
        return nil unless line.start_with?('--') || line.start_with?('-')

        raw_tokens = combine_bracketed_tokens(line.split(/\s+/))
        tokens = raw_tokens.flat_map { |token|
          if token.include?('/') && !token.start_with?('[')
            token.split('/')
          else
            [token]
          end
        }

        long_option = nil
        short_option = nil
        inline_value_from_long = nil
        inline_value_from_short = nil
        remaining = []

        tokens.each do |token|
          if long_option.nil? && token.start_with?('--')
            if (eq_index = token.index('='))
              long_option = token[0...eq_index]
              inline_value_from_long = token[(eq_index + 1)..]
            else
              long_option = token
            end
            next
          end

          if short_option.nil? && token.start_with?('-') && !token.start_with?('--')
            if (eq_index = token.index('='))
              short_option = token[0...eq_index]
              inline_value_from_short = token[(eq_index + 1)..]
            else
              short_option = token
            end
            next
          end

          remaining << token
        end

        return nil unless long_option

        type_token = nil
        value_name = [inline_value_from_long, inline_value_from_short].compact.map(&:strip).find { |val| !val.empty? }
        description_tokens = []

        remaining.each do |token|
          token_without_at = token.start_with?('@') ? token[1..] : token

          if value_name.nil? && placeholder_token?(token_without_at)
            value_name = token_without_at
            next
          end

          if type_token.nil? && type_token_candidate?(token)
            type_token = token
            next
          end

          description_tokens << token
        end

        description = description_tokens.join(' ').strip
        description = nil if description.empty?
        raw_types = parse_type_annotation(type_token)
        types, allowed_values = partition_type_tokens(raw_types)

        keyword = long_option.delete_prefix('--').tr('-', '_').to_sym
        return nil unless method_accepts_keyword?(method_obj, keyword)

        build_option_definition(
          keyword,
          long_option,
          short_option,
          value_name,
          types,
          description,
          inline_type_annotation: !type_token.nil?,
          doc_format: :rubycli,
          allowed_values: allowed_values
        )
      end

      def parse_positional_line(line)
        return nil if line.start_with?('--') || line.start_with?('-')

        tokens = combine_bracketed_tokens(line.split(/\s+/))
        placeholder = tokens.shift
        return nil unless placeholder

        clean_placeholder = placeholder.delete('[]')
        return nil unless placeholder_token?(clean_placeholder)

        type_token = nil
        if tokens.first && type_token_candidate?(tokens.first)
          type_token = tokens.shift
        end

        description = tokens.join(' ').strip
        description = nil if description.empty?

        raw_types = parse_type_annotation(type_token)
        types, allowed_values = partition_type_tokens(raw_types)
        placeholder_info = analyze_placeholder(placeholder)
        inferred_types = infer_types_from_placeholder(
          normalize_type_list(types),
          placeholder_info,
          include_optional_boolean: false
        )

        label = clean_placeholder

        inline_annotation = !type_token.nil?
        inline_text = inline_annotation ? format_inline_type_label(inferred_types) : nil

        PositionalDefinition.new(
          placeholder: placeholder,
          label: label.empty? ? placeholder : label,
          types: inferred_types,
          description: description,
          inline_type_annotation: inline_annotation,
          inline_type_text: inline_text,
          doc_format: :rubycli,
          allowed_values: allowed_values
        )
      end

      def parse_return_metadata(line)
        yard_match = /\A@return\s+\[([^\]]+)\](?:\s+(.*))?\z/.match(line)
        if yard_match
          types = parse_type_annotation(yard_match[1])
          description = yard_match[2]&.strip
          return ReturnDefinition.new(types: types, description: description)
        end

        shorthand_match = /\A=>\s+(\[[^\]]+\]|[^\s]+)(?:\s+(.*))?\z/.match(line)
        if shorthand_match
          types = parse_type_annotation(shorthand_match[1])
          description = shorthand_match[2]&.strip
          return ReturnDefinition.new(types: types, description: description)
        end

        if line.start_with?('return ')
          stripped = line.sub(/\Areturn\s+/, '')
          type_token, description = stripped.split(/\s+/, 2)
          types = parse_type_annotation(type_token)
          description = description&.strip
          return ReturnDefinition.new(types: types, description: description)
        end
      end

      def extract_parameter_defaults(method_obj)
        location = method_obj.source_location
        return {} unless location

        file, line_no = location
        return {} unless file && line_no

        lines = File.readlines(file)
        signature = String.new
        index = line_no - 1
        while index < lines.length
          line = lines[index]
          signature << line
          break if balanced_signature?(signature)
          index += 1
        end

        params_source = extract_params_from_signature(signature)
        return {} unless params_source

        split_parameters(params_source).each_with_object({}) do |param_token, memo|
          case param_token
          when /^\*\*/
            next
          when /^\*/
            next
          when /^&/
            next
          else
            if (match = param_token.match(/\A([a-zA-Z0-9_]+)\s*=\s*(.+)\z/))
              memo[match[1].to_sym] = match[2].strip
            elsif (match = param_token.match(/\A([a-zA-Z0-9_]+):\s*(.+)\z/))
              memo[match[1].to_sym] = match[2].strip
            end
          end
        end
      rescue Errno::ENOENT
        {}
      end

      def balanced_signature?(signature)
        def_index = signature.index(/\bdef\b/)
        return false unless def_index

        open_parens = signature.count('(')
        close_parens = signature.count(')')

        if open_parens.zero?
          !signature.strip.end_with?(',')
        else
          open_parens == close_parens && signature.rindex(')') > signature.index('(')
        end
      end

      def extract_params_from_signature(signature)
        return nil unless (def_match = signature.match(/\bdef\b\s+[^(\s]+\s*(\((.*)\))?/m))
        if def_match[1]
          inner = def_match[1][1..-2]
          inner
        else
          signature_after_def = signature.sub(/.*\bdef\b\s+[^(\s]+\s*/m, '')
          signature_after_def.split(/\n/).first&.strip
        end
      end

      def split_parameters(param_string)
        return [] unless param_string

        tokens = []
        current = String.new
        depth = 0
        param_string.each_char do |char|
          case char
          when '(', '[', '{'
            depth += 1
          when ')', ']', '}'
            depth -= 1 if depth > 0
          when ','
            if depth.zero?
              tokens << current.strip unless current.strip.empty?
              current = String.new
              next
            end
          end
          current << char
        end

        tokens << current.strip unless current.strip.empty?
        tokens
      end

      def align_and_validate_parameter_docs(method_obj, metadata, defaults)
        positional_defs = metadata[:positionals].dup
        positional_map = {}
        existing_options = metadata[:options].dup
        options_by_keyword = existing_options.each_with_object({}) { |opt, memo| memo[opt.keyword] = opt }
        ordered_options = []

        source_file = nil
        source_line = nil
        if method_obj.respond_to?(:source_location)
          source_file, source_line = method_obj.source_location
        end
        line_for_comment = source_line ? [source_line - 1, 1].max : nil

        method_obj.parameters.each do |type, name|
          case type
          when :req, :opt
            doc = positional_defs.shift
            if doc
              doc.param_name = name
              doc.default_value = defaults[name]
              positional_map[name] = doc
            else
              @environment.handle_documentation_issue(
                "Documentation is missing for positional argument '#{name}'",
                file: source_file,
                line: line_for_comment
              )
              unless @environment.doc_check_mode?
                fallback = PositionalDefinition.new(
                  placeholder: name.to_s,
                  label: name.to_s.upcase,
                  types: [],
                  description: nil,
                  param_name: name,
                  default_value: defaults[name],
                  inline_type_annotation: false,
                  inline_type_text: nil,
                  doc_format: :auto_generated,
                  allowed_values: []
                )
                metadata[:positionals] << fallback
                positional_map[name] = fallback
              end
            end
          when :keyreq, :key
            if (option = options_by_keyword[name])
              ordered_options << option unless ordered_options.include?(option)
            else
              @environment.handle_documentation_issue(
                "Documentation is missing for keyword argument ':#{name}'",
                file: source_file,
                line: line_for_comment
              )
              unless @environment.doc_check_mode?
                fallback_option = build_auto_option_definition(name)
                ordered_options << fallback_option if fallback_option
              end
            end
          end
        end

        metadata[:options] = ordered_options + (existing_options - ordered_options)

        unless positional_defs.empty?
          extra = positional_defs.map(&:placeholder).join(', ')
          @environment.handle_documentation_issue(
            "Extra positional argument comments were found: #{extra}",
            file: source_file,
            line: line_for_comment
          )

          metadata[:positionals] -= positional_defs

          positional_defs.each do |doc|
            detail_line = detail_line_for_extra_positional(doc)
            next unless detail_line

            metadata[:detail_lines] ||= []
            metadata[:detail_lines] << detail_line
          end
        end

        metadata[:positionals_map] = positional_map

        metadata[:options].each do |opt|
          if defaults.key?(opt.keyword)
            opt.default_value = defaults[opt.keyword]
            if TypeUtils.boolean_string?(opt.default_value)
              opt.boolean_flag = true
              opt.requires_value = false
              if opt.doc_format == :auto_generated
                opt.value_name = nil
                opt.types = ['Boolean']
              end
            end
          end
        end
      end

      def detail_line_for_extra_positional(doc)
        return nil unless doc

        parts = []
        placeholder = doc.placeholder || doc.label
        placeholder = placeholder.to_s.strip
        parts << placeholder unless placeholder.empty?

        type_text = doc.inline_type_text
        if (!type_text || type_text.empty?) && doc.types && !doc.types.empty?
          type_text = "[#{doc.types.join(', ')}]"
        end
        parts << type_text if type_text && !type_text.empty?

        description = doc.description.to_s.strip
        parts << description unless description.empty?

        text = parts.join(' ').strip
        text.empty? ? nil : text
      end

      INLINE_TYPE_HINTS = %w[
        String
        Integer
        Float
        Numeric
        Boolean
        TrueClass
        FalseClass
        Symbol
        Array
        Hash
        JSON
        Time
        Date
        DateTime
        BigDecimal
        File
        Pathname
        nil
      ].freeze

      def parse_type_annotation(type_str)
        return [] unless type_str

        cleaned = type_str.strip
        cleaned = cleaned.delete_prefix('@')
        cleaned = cleaned[1..-2].strip if cleaned.start_with?('(') && cleaned.end_with?(')')
        cleaned = cleaned[1..-2] if cleaned.start_with?('[') && cleaned.end_with?(']')
        cleaned = cleaned.sub(/\Atype\s*:\s*/i, '')
        cleaned.split(/[,|]/).map { |token| normalize_type_token(token) }.reject(&:empty?)
      end

      def partition_type_tokens(tokens)
        normalized = Array(tokens).dup
        allowed = []

        normalized.each do |token|
          expand_annotation_token(token).each do |expanded|
            literal_entry = literal_entry_from_token(expanded)
            allowed << literal_entry if literal_entry
          end
        end

        [normalized, allowed.compact.uniq]
      end

      def merge_allowed_values(primary, additional)
        return Array(additional) if primary.nil? || primary.empty?
        return Array(primary) if additional.nil? || additional.empty?

        (primary + additional).uniq
      end

      def expand_annotation_token(token)
        return [] unless token

        stripped = token.strip
        return [] if stripped.empty?

        if stripped.start_with?('%i[') && stripped.end_with?(']')
          inner = stripped[3..-2]
          inner.split(/\s+/).map { |entry| ":#{entry}" }
        elsif stripped.start_with?('%I[') && stripped.end_with?(']')
          inner = stripped[3..-2]
          inner.split(/\s+/).map { |entry| ":#{entry}" }
        elsif stripped.start_with?('%w[') && stripped.end_with?(']')
          inner = stripped[3..-2]
          inner.split(/\s+/)
        elsif stripped.start_with?('%W[') && stripped.end_with?(']')
          inner = stripped[3..-2]
          inner.split(/\s+/)
        else
          [stripped]
        end
      end

      def literal_entry_from_token(token)
        return nil unless token

        stripped = token.strip
        return nil if stripped.empty?
        stripped = stripped[1..] if stripped.start_with?('[') && !stripped.end_with?(']')
        if stripped.end_with?(']') && !stripped.include?('[')
          stripped = stripped[0...-1]
        end

        lowered = stripped.downcase
        return { kind: :literal, value: nil } if %w[nil null ~].include?(lowered)
        return { kind: :literal, value: true } if lowered == 'true'
        return { kind: :literal, value: false } if lowered == 'false'

        if stripped.start_with?(':')
          sym_name = stripped[1..]
          return nil if sym_name.nil? || sym_name.empty?

          return { kind: :literal, value: sym_name.to_sym }
        end

        if stripped.start_with?('"') && stripped.end_with?('"') && stripped.length >= 2
          return { kind: :literal, value: stripped[1..-2] }
        end

        if stripped.start_with?("'") && stripped.end_with?("'") && stripped.length >= 2
          return { kind: :literal, value: stripped[1..-2] }
        end

        if stripped.match?(/\A-?\d+\z/)
          return { kind: :literal, value: Integer(stripped) }
        end

        if stripped.match?(/\A-?\d+\.\d+\z/)
          return { kind: :literal, value: Float(stripped) }
        end

        if stripped.match?(/\A[a-z0-9._-]+\z/)
          return { kind: :literal, value: stripped }
        end

        nil
      rescue ArgumentError
        nil
      end


      def placeholder_token?(token)
        return false unless token

        candidate = token.strip.delete_prefix('@')
        return false if candidate.empty?

        optional = candidate.start_with?('[') && candidate.end_with?(']')
        candidate = candidate[1..-2].strip if optional
        return false if candidate.empty?

        candidate = candidate.gsub(/[,\|]/, '')
        return false if candidate.empty?

        ellipsis = candidate.end_with?('...')
        candidate = candidate[0..-4] if ellipsis
        candidate = candidate.strip
        return false if candidate.empty?

        if candidate.start_with?('<') && candidate.end_with?('>')
          inner = candidate[1..-2]
          inner.match?(/\A[0-9A-Za-z][0-9A-Za-z._-]*\z/)
        else
          cleaned = candidate.gsub(/[^A-Za-z0-9_]/, '')
          return false if cleaned.empty?

          cleaned == cleaned.upcase && cleaned.match?(/[A-Z]/)
        end
      end

      def type_token_candidate?(token)
        return false unless token

        stripped = token.strip
        return false if stripped.empty?

        return true if stripped.start_with?('@')

        parsed = parse_type_annotation(stripped)
        !parsed.empty?
      end

      def known_type_token?(token)
        return false unless token

        candidate = token.start_with?('@') ? token[1..] : token
        candidate =~ /\A[A-Z][A-Za-z0-9_:<>\[\]]*\z/
      end

      def inline_type_hint?(token)
        normalized = normalize_type_token(token)
        return false if normalized.empty?

        base = if normalized.include?('<') && normalized.end_with?('>')
                 normalized.split('<').first
               elsif normalized.end_with?('[]')
                 normalized[0..-3]
               else
                 normalized
               end

        INLINE_TYPE_HINTS.include?(base)
      end

      def parameter_role(method_obj, keyword)
        return nil unless method_obj.respond_to?(:parameters)

        symbol = keyword.to_sym
        method_obj.parameters.each do |type, name|
          next unless name == symbol

          case type
          when :req, :opt, :rest
            return :positional
          when :keyreq, :key
            return :keyword
          else
            return nil
          end
        end

        nil
      end

      def combine_bracketed_tokens(tokens)
        combined = []
        buffer = nil
        closing = nil

        tokens.each do |token|
          next if token.nil?

          if buffer
            buffer << ' ' unless token.empty?
            buffer << token
            if closing && token.include?(closing)
              combined << buffer
              buffer = nil
              closing = nil
            end
          elsif token.start_with?('[') && !token.include?(']')
            buffer = token.dup
            closing = ']'
          elsif token.start_with?('(') && !token.include?(')')
            buffer = token.dup
            closing = ')'
          elsif token.start_with?('%') && token.include?('[') && !token.include?(']')
            buffer = token.dup
            closing = ']'
          else
            combined << token
          end
        end

        combined << buffer if buffer
        combined
      end

      def format_inline_type_label(types)
        return nil if types.nil? || types.empty?

        unique_types = types.reject(&:empty?).uniq
        return nil if unique_types.empty?

        "[#{unique_types.join(', ')}]"
      end

      def method_accepts_keyword?(method_obj, keyword)
        params = method_obj.parameters
        keyword_names = params.select { |type, _| %i[key keyreq keyrest].include?(type) }.map { |_, name| name }
        keyword_names.include?(keyword) || params.any? { |type, _| type == :keyrest }
      end

      def build_option_definition(
        keyword,
        long_option,
        short_option,
        value_name,
        types,
        description,
        inline_type_annotation: false,
        doc_format: nil,
        allowed_values: nil
      )
        normalized_long = normalize_long_option(long_option)
        normalized_short = normalize_short_option(short_option)
        value_placeholder = value_name&.strip
        value_placeholder = nil if value_placeholder&.empty?
        description_text = description&.strip
        description_text = nil if description_text&.empty?

        placeholder_info = analyze_placeholder(value_placeholder)
        normalized_types = normalize_type_list(types)
        inferred_types = infer_types_from_placeholder(normalized_types, placeholder_info)
        if inferred_types.empty? && value_placeholder.nil?
          inferred_types = ['Boolean']
        end

        optional_value = placeholder_info[:optional]
        boolean_flag = !optional_value && inferred_types.any? { |type| boolean_type?(type) }
        requires_value = determine_requires_value(
          value_placeholder: value_placeholder,
          types: inferred_types,
          boolean_flag: boolean_flag,
          optional_value: optional_value
        )

        if value_placeholder.nil? && !boolean_flag && requires_value
          value_placeholder = default_placeholder_for(keyword)
          placeholder_info = analyze_placeholder(value_placeholder)
          optional_value = placeholder_info[:optional]
        end

        inline_type_text = inline_type_annotation ? format_inline_type_label(inferred_types) : nil

        OptionDefinition.new(
          keyword: keyword,
          long: normalized_long,
          short: normalized_short,
          value_name: value_placeholder,
          types: inferred_types,
          description: description_text,
          requires_value: requires_value,
          boolean_flag: boolean_flag,
          optional_value: optional_value,
          inline_type_annotation: inline_type_annotation,
          inline_type_text: inline_type_text,
          doc_format: doc_format,
          allowed_values: normalize_allowed_values(allowed_values)
        )
      end

      def normalize_allowed_values(values)
        Array(values).compact.uniq
      end

      def build_auto_option_definition(keyword)
        long_option = "--#{keyword.to_s.tr('_', '-')}"
        placeholder = default_placeholder_for(keyword)
        build_option_definition(
          keyword,
          long_option,
          nil,
          placeholder,
          [],
          nil,
          inline_type_annotation: false,
          doc_format: :auto_generated,
          allowed_values: []
        )
      end

      def option_to_positional_definition(option)
        placeholder = option.value_name || default_placeholder_for(option.keyword)
        PositionalDefinition.new(
          placeholder: placeholder,
          label: placeholder,
          types: option.types,
          description: option.description,
          param_name: option.keyword,
          default_value: option.default_value,
          inline_type_annotation: option.inline_type_annotation,
          inline_type_text: option.inline_type_text,
          doc_format: option.doc_format,
          allowed_values: option.allowed_values
        )
      end
    end
  end
end
