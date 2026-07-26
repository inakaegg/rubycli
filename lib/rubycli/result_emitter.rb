# frozen_string_literal: true

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
        format_convertible_result(result)
      end
    rescue JSON::GeneratorError, JSON::NestingError
      result.inspect
    end

    # to_h / to_ary are duck-typed: every Enumerable answers to_h, but Set,
    # Range and Enumerator raise TypeError unless their elements are pairs.
    def format_convertible_result(result)
      if result.respond_to?(:to_h)
        JSON.pretty_generate(result.to_h)
      elsif result.respond_to?(:to_ary)
        JSON.pretty_generate(result.to_ary)
      else
        result.inspect
      end
    rescue TypeError
      result.inspect
    end
  end
end
