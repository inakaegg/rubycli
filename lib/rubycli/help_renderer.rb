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

      params = method_obj.parameters
      return "(no arguments)" if params.empty?

      param_desc = params.map { |type, name|
        case type
        when :req then "<#{name}>"
        when :opt then "[<#{name}>]"
        when :rest then "[<#{name}>...]"
        when :keyreq then "--#{name.to_s.tr("_", "-")}=<value>"
        when :key then "[--#{name.to_s.tr("_", "-")}=<value>]"
        when :keyrest then "[--<option>...]"
        end
      }.compact.join(" ")

      param_desc.empty? ? "(no arguments)" : param_desc
    end

    def usage_for_method(command, method)
      metadata = @documentation_registry.metadata_for(method)
      params_str = format_method_parameters(method.parameters, metadata)
      usage_lines = ["Usage: #{File.basename($PROGRAM_NAME)} #{command} #{params_str}".strip]

      options = metadata[:options] || []
      positionals_in_order = ordered_positionals(method, metadata)

      if positionals_in_order.any?
        labels = positionals_in_order.map { |info| info[:label] }
        max_label_length = labels.map(&:length).max || 0

        usage_lines << ""
        usage_lines << "Positional arguments:"
        positionals_in_order.each do |info|
          definition = info[:definition]
          description_parts = []
          if definition&.inline_type_annotation && definition.inline_type_text
            description_parts << definition.inline_type_text
          end
          type_info = positional_type_display(definition)
          if type_info && type_info_first?(definition)
            description_parts << type_info
          end
          description_parts << info[:description] if info[:description]
          description_parts << type_info if type_info && !type_info_first?(definition)
          default_text = positional_default_display(definition)
          description_parts << default_text if default_text
          description_text = description_parts.join(' ')
          line = "  #{info[:label].ljust(max_label_length)}"
          line += "  #{description_text}" unless description_text.empty?
          usage_lines << line
        end
      end

      if options.any?
        option_labels = options.map { |opt| option_flag_with_placeholder(opt) }
        max_label_length = option_labels.map(&:length).max || 0

        usage_lines << "" unless usage_lines.last == ""
        usage_lines << "Options:"
        options.each_with_index do |opt, idx|
          label = option_labels[idx]
          description_parts = []
          if opt.inline_type_annotation && opt.inline_type_text
            description_parts << opt.inline_type_text
          end
          type_info = option_type_display(opt)
          if type_info && type_info_first?(opt)
            description_parts << type_info
          end
          description_parts << opt.description if opt.description
          description_parts << type_info if type_info && !type_info_first?(opt)
          default_info = option_default_display(opt)
          description_parts << default_info if default_info
          description_text = description_parts.join(' ')
          line = "  #{label.ljust(max_label_length)}"
          line += "  #{description_text}" unless description_text.empty?
          usage_lines << line
        end
      end

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
          doc = positional_map[name]
          label = doc&.label || name.to_s.upcase
          "<#{label}>"
        when :opt
          doc = positional_map[name]
          label = doc&.label || name.to_s.upcase
          "[<#{label}>]"
        when :rest then "[<#{name}>...]"
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
      }.reject(&:empty?).join(" ")
    end

    def auto_generated_option_usage_label(name, opt)
      base_flag = "--#{name.to_s.tr('_', '-')}"
      return base_flag if opt.boolean_flag

      "#{base_flag}=<value>"
    end

    def ordered_positionals(method, metadata)
      positional_map = metadata[:positionals_map] || {}
      method.parameters.each_with_object([]) do |(type, name), memo|
        next unless %i[req opt].include?(type)

        definition = positional_map[name]
        label = if definition
            type == :opt ? "[#{definition.label}]" : definition.label
          else
            base = name.to_s.upcase
            type == :opt ? "[#{base}]" : base
          end
        description = definition&.description
        memo << { label: label, description: description, definition: definition }
      end
    end

    def positional_type_display(definition)
      return nil unless definition
      return nil if definition.inline_type_annotation
      return nil if definition.types.nil? || definition.types.empty?

      unique_types = definition.types.reject(&:empty?).uniq
      return nil if unique_types.empty?

      if definition.respond_to?(:doc_format) && definition.doc_format == :rubycli
        "[#{unique_types.join(', ')}]"
      else
        "(type: #{unique_types.join(' | ')})"
      end
    end

    def positional_default_display(definition)
      return nil unless definition && definition.default_value
      return nil if definition.default_value.to_s.empty?

      "(default: #{definition.default_value})"
    end

    def option_flag_with_placeholder(opt)
      flags = [opt.short, opt.long].compact
      flags = ["--#{opt.keyword.to_s.tr("_", "-")}"] if flags.empty?
      flag_label = flags.join(", ")
      placeholder = option_value_placeholder(opt)
      if placeholder
        "#{flag_label} #{placeholder}"
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

    def option_type_display(opt)
      return nil if opt.inline_type_annotation
      return nil if opt.types.nil? || opt.types.empty?

      unique_types = opt.types.reject(&:empty?).uniq
      return nil if unique_types.empty?

      if opt.respond_to?(:doc_format) && opt.doc_format == :rubycli
        "[#{unique_types.join(', ')}]"
      else
        "(type: #{unique_types.join(' | ')})"
      end
    end

    def option_default_display(opt)
      return nil if opt.default_value.nil? || opt.default_value.to_s.empty?

      "(default: #{opt.default_value})"
    end

    def type_info_first?(definition)
      definition.respond_to?(:doc_format) && definition.doc_format == :rubycli
    end
  end
end
