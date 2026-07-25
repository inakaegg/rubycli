# frozen_string_literal: true

module Rubycli
  # Observes constants defined while loading a file.
  class ConstantCapture
    def initialize
      @captured = Hash.new { |hash, key| hash[key] = [] }
    end

    def capture(file)
      normalized_file = normalize(file)
      @captured[normalized_file] = []
      before_snapshot = constant_snapshot(normalized_file)
      trace = TracePoint.new(:class) do |tp|
        location = tp.path
        next unless location && same_file?(normalized_file, location)

        constant_name = qualified_name_for(tp.self)
        next unless constant_name

        @captured[normalized_file] << constant_name
      end

      trace.enable
      yield
    ensure
      trace&.disable
      if normalized_file && before_snapshot
        after_snapshot = constant_snapshot(normalized_file)
        changed_names = after_snapshot.keys.select do |name|
          before_snapshot[name] != after_snapshot[name]
        end
        @captured[normalized_file].concat(changed_names)
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
  end
end
