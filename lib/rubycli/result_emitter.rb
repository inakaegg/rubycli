module Rubycli
  class ResultEmitter
    def initialize(environment:)
      @environment = environment
    end

    def emit(result)
      return unless @environment.print_result?
      return if result.nil?
      return if result.is_a?(Module) || result.is_a?(Class)

      formatted = format_result_output(result)
      return if formatted.nil? || (formatted.respond_to?(:empty?) && formatted.empty?)

      puts formatted
    end

    private

    def format_result_output(result)
      case result
      when String
        result
      when Numeric, TrueClass, FalseClass
        result.to_s
      when Array, Hash
        JSON.pretty_generate(result)
      else
        if result.respond_to?(:to_h)
          JSON.pretty_generate(result.to_h)
        elsif result.respond_to?(:to_ary)
          JSON.pretty_generate(result.to_ary)
        else
          result.inspect
        end
      end
    rescue JSON::GeneratorError
      result.inspect
    end
  end
end
