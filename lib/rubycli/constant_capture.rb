# frozen_string_literal: true

require 'digest'
require 'ripper'

module Rubycli
  # Observes constants defined while loading a file.
  class ConstantCapture
    def initialize
      @captured = Hash.new { |hash, key| hash[key] = [] }
      @source_fingerprints = {}
      @assignment_definitions = {}
    end

    def capture(file)
      normalized_file = normalize(file)
      source_fingerprint = Digest::SHA256.file(normalized_file).hexdigest
      source_unchanged = @source_fingerprints[normalized_file] == source_fingerprint
      previous_names = @captured[normalized_file].dup
      previous_assignment_definitions = @assignment_definitions.fetch(normalized_file, {})
      current_assignment_definitions = assigned_constant_definitions(normalized_file)
      executed_lines = []
      observed_events = []
      @captured[normalized_file] = []
      before_snapshot = constant_snapshot(normalized_file)
      trace = TracePoint.new(:class, :line, :c_return) do |tp|
        location = tp.path
        next unless location && same_file?(normalized_file, location)

        observed_events << [tp.event, tp.self, tp.lineno, tp.method_id]
      end

      trace.enable
      yield
    ensure
      trace&.disable
      if normalized_file && before_snapshot
        apply_trace_events(observed_events, executed_lines, normalized_file)
        after_snapshot = constant_snapshot(normalized_file)
        changed_names = after_snapshot.keys.select do |name|
          before_snapshot[name] != after_snapshot[name]
        end
        retained_names = previous_names.select do |name|
          previous_definitions = previous_assignment_definitions.fetch(name, [])
          current_definitions = current_assignment_definitions.fetch(name, [])
          definition_active = active_definition_retained?(
            previous_definitions,
            current_definitions,
            executed_lines
          )
          after_snapshot.key?(name) && (source_unchanged || definition_active)
        end
        @captured[normalized_file].concat(changed_names).concat(retained_names)
        @source_fingerprints[normalized_file] = source_fingerprint
        @assignment_definitions[normalized_file] = current_assignment_definitions
      end
    end

    def constants_for(file)
      Array(@captured[normalize(file)]).uniq
    end

    private

    def same_file?(target, candidate)
      normalize(target) == normalize(candidate)
    end

    def normalize(file)
      File.expand_path(file.to_s)
    end

    def qualified_name_for(target)
      return nil unless target.respond_to?(:name)

      name = target.name
      return nil unless name && !name.empty? && !name.start_with?('#<')

      name
    end

    def constant_snapshot(file)
      ObjectSpace.each_object(Module).each_with_object({}) do |owner, snapshot|
        owner_name = owner.equal?(Object) ? '' : owner.name
        next if owner_name.nil? || owner_name.start_with?('#<')

        safe_module_constants(owner).each do |constant_name|
          next if safe_autoload?(owner, constant_name)

          location = safe_const_source_location(owner, constant_name)
          next unless location && same_file?(file, location[0])

          value = safe_const_get(owner, constant_name)
          next unless value.is_a?(Module)

          name = qualified_constant_name(owner_name, constant_name)
          snapshot[name] = [location, value.object_id]
        end
      end
    rescue StandardError
      {}
    end

    def safe_module_constants(owner)
      owner.constants(false)
    rescue StandardError
      []
    end

    def safe_autoload?(owner, constant_name)
      owner.autoload?(constant_name, false)
    rescue StandardError
      false
    end

    def safe_const_source_location(owner, constant_name)
      owner.const_source_location(constant_name, false)
    rescue StandardError
      nil
    end

    def safe_const_get(owner, constant_name)
      owner.const_get(constant_name, false)
    rescue StandardError
      nil
    end

    def qualified_constant_name(owner_name, constant_name)
      return constant_name.to_s if owner_name.empty?

      "#{owner_name}::#{constant_name}"
    end

    def apply_trace_events(events, executed_lines, file)
      events.each do |event, target, line, method_id|
        case event
        when :line
          executed_lines << line
        when :c_return
          @captured[file].concat(constants_set_at(target, file, line)) if method_id == :const_set
        when :class
          constant_name = qualified_name_for(target)
          @captured[file] << constant_name if constant_name
        end
      end
    end

    def constants_set_at(owner, file, line)
      owner_name = owner.equal?(Object) ? '' : owner.name
      return [] if owner_name.nil? || owner_name.start_with?('#<')

      safe_module_constants(owner).filter_map do |constant_name|
        location = safe_const_source_location(owner, constant_name)
        next unless location && same_file?(file, location[0]) && location[1] == line

        value = safe_const_get(owner, constant_name)
        next unless value.is_a?(Module)

        qualified_constant_name(owner_name, constant_name)
      end
    end

    def active_definition_retained?(previous_definitions, current_definitions, executed_lines)
      previous_definitions.any? do |previous|
        current_definitions.any? do |current|
          next false unless previous[:signature] == current[:signature]

          !current[:ambiguous_line] && executed_lines.include?(current[:line])
        end
      end
    end

    def assigned_constant_definitions(file)
      syntax_tree = Ripper.sexp(File.read(file))
      return {} unless syntax_tree

      collect_assigned_constant_definitions(syntax_tree, [], [], {})
    end

    def collect_assigned_constant_definitions(node, namespace, contexts, definitions)
      return definitions unless node.is_a?(Array)

      case node.first
      when :module
        nested_name = constant_name_from_node(node[1], namespace)
        collect_assigned_constant_definitions(node[2], Array(nested_name&.split('::')), contexts, definitions)
      when :class
        nested_name = constant_name_from_node(node[1], namespace)
        collect_assigned_constant_definitions(node[3], Array(nested_name&.split('::')), contexts, definitions)
      when :assign, :opassign
        signature = [node.first, assignment_operator(node), contexts.map(&:first)]
        collect_assignment_targets(node[1], namespace, definitions, signature, contexts)
        node.drop(2).each do |child|
          collect_assigned_constant_definitions(child, namespace, contexts, definitions)
        end
      when :massign
        signature = [node.first, nil, contexts.map(&:first)]
        collect_assignment_targets(node[1], namespace, definitions, signature, contexts)
        node.drop(2).each do |child|
          collect_assigned_constant_definitions(child, namespace, contexts, definitions)
        end
      when :if, :unless
        collect_assigned_constant_definitions(node[1], namespace, contexts, definitions)
        condition = canonical_syntax(node[1])
        condition_line = source_line(node[1])
        then_context = contexts + [[[node.first, :then, condition], condition_line]]
        else_context = contexts + [[[node.first, :else, condition], condition_line]]
        collect_assigned_constant_definitions(node[2], namespace, then_context, definitions)
        collect_assigned_constant_definitions(node[3], namespace, else_context, definitions)
      when :while, :until
        collect_assigned_constant_definitions(node[1], namespace, contexts, definitions)
        body_context = contexts + [[[node.first, canonical_syntax(node[1])], source_line(node[1])]]
        collect_assigned_constant_definitions(node[2], namespace, body_context, definitions)
      when :if_mod, :unless_mod, :while_mod, :until_mod
        collect_assigned_constant_definitions(node[1], namespace, contexts, definitions)
        branch_context = contexts + [[[node.first, canonical_syntax(node[1])], source_line(node[1])]]
        collect_assigned_constant_definitions(node[2], namespace, branch_context, definitions)
      when :ifop
        collect_assigned_constant_definitions(node[1], namespace, contexts, definitions)
        condition = canonical_syntax(node[1])
        condition_line = source_line(node[1])
        then_context = contexts + [[[node.first, :then, condition], condition_line]]
        else_context = contexts + [[[node.first, :else, condition], condition_line]]
        collect_assigned_constant_definitions(node[2], namespace, then_context, definitions)
        collect_assigned_constant_definitions(node[3], namespace, else_context, definitions)
      when :binary
        collect_assigned_constant_definitions(node[1], namespace, contexts, definitions)
        right_contexts = contexts
        if %i[&& ||].include?(node[2])
          right_contexts += [[[node.first, node[2], canonical_syntax(node[1])], source_line(node[1])]]
        end
        collect_assigned_constant_definitions(node[3], namespace, right_contexts, definitions)
      when :case
        collect_assigned_constant_definitions(node[1], namespace, contexts, definitions)
        case_context = contexts + [[[node.first, canonical_syntax(node[1])], source_line(node[1])]]
        collect_assigned_constant_definitions(node[2], namespace, case_context, definitions)
      when :for
        collect_assigned_constant_definitions(node[2], namespace, contexts, definitions)
        body_context = contexts + [[[node.first, canonical_syntax(node[2])], source_line(node[1])]]
        collect_assigned_constant_definitions(node[3], namespace, body_context, definitions)
      when :lambda, :do_block, :brace_block
        lazy_context = contexts + [[[node.first], source_line(node)]]
        node.drop(1).each do |child|
          collect_assigned_constant_definitions(child, namespace, lazy_context, definitions)
        end
      else
        node.each do |child|
          collect_assigned_constant_definitions(child, namespace, contexts, definitions)
        end
      end

      definitions
    end

    def collect_assignment_targets(node, namespace, definitions, signature, contexts)
      assigned_name = constant_name_from_node(node, namespace)
      if assigned_name
        line = source_line(node)
        # A line event can precede a skipped postfix/short-circuit assignment.
        ambiguous_line = contexts.any? { |context| context[1] == line }
        definition = { signature: signature, line: line, ambiguous_line: ambiguous_line }
        definitions[assigned_name] = Array(definitions[assigned_name]) | [definition]
      elsif node.is_a?(Array)
        node.each { |child| collect_assignment_targets(child, namespace, definitions, signature, contexts) }
      end
    end

    def assignment_operator(node)
      node.first == :opassign ? node.dig(2, 1) : nil
    end

    def canonical_syntax(node)
      return node unless node.is_a?(Array)
      return [node[0], node[1]] if node.first.to_s.start_with?('@')

      node.map { |child| canonical_syntax(child) }
    end

    def source_line(node)
      return nil unless node.is_a?(Array)
      return node.dig(2, 0) if node.first.to_s.start_with?('@')

      node.each do |child|
        line = source_line(child)
        return line if line
      end
      nil
    end

    def constant_name_from_node(node, namespace)
      return nil unless node.is_a?(Array)

      case node.first
      when :var_field, :const_ref, :var_ref
        constant_name_from_node(node[1], namespace)
      when :@const
        (namespace + [node[1]]).join('::')
      when :const_path_field, :const_path_ref
        parent_name = constant_name_from_node(node[1], namespace)
        child_name = node.dig(2, 1)
        [parent_name, child_name].compact.join('::')
      when :top_const_field, :top_const_ref
        node.dig(1, 1)
      end
    end

  end
end
