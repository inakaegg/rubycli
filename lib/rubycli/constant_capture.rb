# frozen_string_literal: true

module Rubycli
  # Observes constants defined while loading a file.
  class ConstantCapture
    def initialize
      @captured = Hash.new { |hash, key| hash[key] = [] }
    end

    def capture(file)
      trace = TracePoint.new(:class) do |tp|
        location = tp.path
        next unless location && same_file?(file, location)

        constant_name = qualified_name_for(tp.self)
        next unless constant_name

        @captured[file] << constant_name
      end

      trace.enable
      yield
    ensure
      trace&.disable
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
  end
end
