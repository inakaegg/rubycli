require_relative "type_utils"

module Rubycli
  class HelpRenderer
    include TypeUtils

    def initialize(documentation_registry:)
      @documentation_registry = documentation_registry
    end

    def print_help(target, catalog)
      puts "Usage: #{File.basename($PROGRAM_NAME)} COMMAND [arguments]"
      puts

      instance_entries = catalog.entries_for(:instance)
      class_entries = catalog.entries_for(:class)
      groups = []
      groups << { label: "Instance methods", entries: instance_entries } unless instance_entries.empty?
      groups << { label: "Class methods", entries: class_entries } unless class_entries.empty?

      if groups.empty?
        puts "No commands available."
        return
      end

      puts "Available commands:"
      groups.each do |group|
        puts "  #{group[:label]}:"
        group[:entries].each do |entry|
          description = method_description(entry.method)
          line = "    #{entry.command.ljust(20)}"
          line += " #{description}" unless description.empty?
          puts line.rstrip

          unless entry.aliases.empty?
            puts "      Aliases: #{entry.aliases.join(", ")}"
          end
        end
        puts unless group.equal?(groups.last)
      end

      if catalog.duplicates.any?
        puts "Methods with the same name can be invoked via instance::NAME / class::NAME."
      end

      puts
      puts "Detailed command help: #{File.basename($PROGRAM_NAME)} COMMAND help"
      puts "Enable debug logging: --debug or RUBYCLI_DEBUG=true"
    end

    def method_description(method_obj)
      metadata = @documentation_registry.metadata_for(method_obj)
      summary = metadata[:summary]
      return summary if summary && !summary.empty?

      params_str = format_method_parameters(method_obj.parameters, metadata)
      params_str.empty? ? "(no arguments)" : params_str
    end

    def usage_for_method(command, method)
      metadata = @documentation_registry.metadata_for(method)
      params_str = format_method_parameters(method.parameters, metadata)
      usage_lines = ["Usage: #{File.basename($PROGRAM_NAME)} #{command} #{params_str}".strip]

      options = metadata[:options] || []
      positionals_in_order = ordered_positionals(method, metadata)

      usage_lines.concat(render_positionals(positionals_in_order)) if positionals_in_order.any?
      usage_lines.concat(render_options(options, required_keyword_names(method))) if options.any?

      returns = metadata[:returns] || []
      if returns.any?
        usage_lines << "" unless usage_lines.last == ""
        usage_lines << "Return values:"
        returns.each do |ret|
          type_label = (ret.types || []).join(" | ")
          line = "  #{type_label}"
          line += "  #{ret.description}" if ret.description && !ret.description.empty?
          usage_lines << line
        end
      end

      usage_lines.pop while usage_lines.last == ""
      usage_block = usage_lines.join("\n")

      sections = []
      summary_lines = metadata[:summary_lines] || []
      summary_block = summary_lines.join("\n").rstrip
      sections << summary_block unless summary_block.empty?
      sections << usage_block unless usage_block.empty?
      detail_lines = metadata[:detail_lines] || []
      detail_block = detail_lines.join("\n").rstrip
      sections << detail_block unless detail_block.empty?

      sections.join("\n\n")
    end

    private

    def format_method_parameters(parameters, metadata)
      option_map = (metadata[:options] || []).each_with_object({}) { |opt, h| h[opt[:keyword]] = opt }
      positional_map = metadata[:positionals_map] || {}

      parameters.map { |type, name|
        case type
        when :req
          positional_usage_token(type, name, positional_map[name])
        when :opt
          positional_usage_token(type, name, positional_map[name])
        when :rest
          positional_usage_token(type, name, positional_map[name])
        when :keyreq
          opt = option_map[name]
          if opt
            if opt.doc_format == :auto_generated
              auto_generated_option_usage_label(name, opt)
            else
              option_flag_with_placeholder(opt)
            end
          else
            "--#{name.to_s.tr('_', '-')}=<value>"
          end
        when :key
          opt = option_map[name]
          label = if opt
            if opt.doc_format == :auto_generated
              auto_generated_option_usage_label(name, opt)
            else
              option_flag_with_placeholder(opt)
            end
          else
            "--#{name.to_s.tr('_', '-')}=<value>"
          end
          "[#{label}]"
        when :keyrest then "[--<option>...]"
        else ""
        end
      }.compact.reject(&:empty?).join(" ")
    end

    def auto_generated_option_usage_label(name, opt)
      base_flag = "--#{name.to_s.tr('_', '-')}"
      return base_flag if opt.boolean_flag

      value_name = opt.value_name
      formatted = if value_name && !value_name.to_s.strip.empty?
                    ensure_angle_bracket_placeholder(value_name)
                  else
                    "<value>"
                  end
      "#{base_flag}=#{formatted}"
    end

    def render_positionals(positionals_in_order)
        rows = positionals_in_order.map do |info|
        definition = info[:definition]
        label = info[:label]
        type = type_display(definition)
        requirement = positional_requirement(info[:kind])
        description_parts = []
        description_parts << info[:description] if info[:description]
        default_text = positional_default(definition)
        description_parts << default_text if default_text
        [label, type, requirement, description_parts.join(' ')]
      end
      table_block("Positional arguments:", rows)
    end

    def render_options(options, required_keywords)
      rows = options.map do |opt|
        label = option_flag_with_placeholder(opt)
        type = type_display(opt)
        requirement = required_keywords.include?(opt.keyword) ? 'required' : 'optional'
        description_parts = []
        description_parts << opt.description if opt.description
        default_text = option_default(opt)
        description_parts << default_text if default_text
        [label, type, requirement, description_parts.join(' ').strip]
      end
      table_block("Options:", rows)
    end

    def table_block(header, rows)
      return [] if rows.empty?

      cols = rows.transpose
      widths = cols.map { |col| col.map { |value| value.to_s.length }.max || 0 }

      lines = ["", header]
      rows.each do |row|
        padded = row.each_with_index.map do |value, idx|
          text = value.to_s
          idx < row.length - 1 ? text.ljust(widths[idx]) : text
        end
        lines << "  #{padded.join('  ')}".rstrip
      end
      lines
    end

    def formatted_types(types)
      type_list = Array(types).compact.map { |token| token.to_s.strip }.reject(&:empty?)
      type_list = type_list.each_with_object([]) do |token, acc|
        acc << token unless acc.include?(token)
      end
      return '' if type_list.empty?

      nil_tokens, rest = type_list.partition { |token| token.casecmp('nil').zero? }
      ordered = rest + nil_tokens
      "[#{ordered.join(', ')}]"
    end

    def type_display(definition)
      return formatted_types(definition&.types) unless definition

      literal_entries = Array(definition.allowed_values).map { |entry| format_allowed_value(entry[:value]) }
      type_tokens = Array(definition.types).map { |token| token.to_s.strip }.reject(&:empty?)
      type_tokens.reject! { |token| literal_token?(token) }

      combined = (literal_entries + type_tokens).uniq
      return formatted_types(definition.types) if combined.empty?

      "[#{combined.join(', ')}]"
    end

    def format_allowed_value(value)
      case value
      when Symbol
        ":#{value}"
      when String
        %("#{value}")
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

    def literal_token?(token)
      return true if token.start_with?('%')
      return true if token.include?('[')
      return true if token.start_with?(':')

      false
    end

    def positional_requirement(kind)
      kind == :opt ? 'optional' : 'required'
    end

    def positional_default(definition)
      return nil unless definition
      value = definition.default_value
      return nil if value.nil? || value.to_s.empty?

      "(default: #{value})"
    end

 def option_default(opt)
   value = opt.default_value
   return nil if value.nil? || value.to_s.empty?

   "(default: #{value})"
 end

 def required_keyword_names(method)
   method.parameters.select { |type, _| type == :keyreq }.map { |_, name| name }
 end

    def ordered_positionals(method, metadata)
      positional_map = metadata[:positionals_map] || {}
      method.parameters.each_with_object([]) do |(type, name), memo|
        next unless %i[req opt].include?(type)

        definition = positional_map[name]
        label = display_label_for(definition, name)
        description = definition&.description
        memo << { label: label, description: description, definition: definition, kind: type }
      end
    end

    def display_label_for(definition, name)
      return definition.label if definition&.label && !definition.label.to_s.empty?

      name.to_s.upcase
    end

    def positional_usage_token(type, name, definition)
      placeholder = extract_positional_placeholder(definition)
      case type
      when :req
        required_placeholder(placeholder, definition, name)
      when :opt
        optional_placeholder(placeholder, definition, name)
      when :rest
        rest_placeholder(placeholder, definition, name)
      else
        nil
      end
    end

    def extract_positional_placeholder(definition)
      return nil unless definition
      return nil if definition.doc_format.nil?

      token = definition.placeholder.to_s.strip
      token.empty? ? nil : token
    end

    def required_placeholder(placeholder, definition, name)
      unless placeholder.nil? || placeholder.strip.empty? || auto_generated_placeholder?(placeholder, definition, name)
        return placeholder.strip
      end

      default_positional_label(definition, name, uppercase: true)
    end

    def optional_placeholder(placeholder, definition, name)
      unless placeholder.nil? || placeholder.strip.empty? || auto_generated_placeholder?(placeholder, definition, name)
        return placeholder.strip
      end

      "[#{default_positional_label(definition, name, uppercase: true)}]"
    end

    def rest_placeholder(placeholder, definition, name)
      unless placeholder.nil? || placeholder.strip.empty? || auto_generated_placeholder?(placeholder, definition, name)
        return placeholder.strip
      end

      base = default_positional_label(definition, name, uppercase: true)
      "[#{base}...]"
    end

    def default_positional_label(definition, name, uppercase:)
      label = definition&.label
      label = label.to_s.strip unless label.nil?
      label = nil if label.respond_to?(:empty?) && label.empty?
      base = label || name.to_s
      uppercase ? base.upcase : base
    end

    def option_flag_with_placeholder(opt)
      flags = [opt.short, opt.long].compact
      flags = ["--#{opt.keyword.to_s.tr("_", "-")}"] if flags.empty?
      flag_label = flags.join(", ")
      placeholder = option_value_placeholder(opt)
      if placeholder
        formatted = ensure_angle_bracket_placeholder(placeholder)
        if formatted.start_with?('[') && formatted.end_with?(']')
          inner = formatted[1..-2]
          "#{flag_label}[=#{inner}]"
        else
          "#{flag_label}=#{formatted}"
        end
      else
        flag_label
      end
    end

    def option_value_placeholder(opt)
      return nil if opt.boolean_flag
      return opt.value_name if opt.value_name && !opt.value_name.empty?

      first_non_nil_type = opt.types&.find { |type| !nil_type?(type) && !boolean_type?(type) }
      first_non_nil_type
    end

    def auto_generated_placeholder?(placeholder, definition, name)
      return false unless definition
      return false unless definition.respond_to?(:doc_format) && definition.doc_format == :auto_generated

      placeholder.strip.casecmp(name.to_s).zero?
    end

    def ensure_angle_bracket_placeholder(placeholder)
      raw = placeholder.to_s.strip
      return raw if raw.empty?

      optional = raw.start_with?('[') && raw.end_with?(']')
      core = optional ? raw[1..-2].strip : raw
      return raw if core.empty?

      ellipsis = core.end_with?('...')
      core = core[0..-4] if ellipsis

      formatted_core = if core.start_with?('<') && core.end_with?('>')
                         core
                       else
                         "<#{core}>"
                       end

      formatted_core = "#{formatted_core}..." if ellipsis
      optional ? "[#{formatted_core}]" : formatted_core
    end
  end
end
