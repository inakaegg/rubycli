module Rubycli
  class EvalCoercer
    THREAD_KEY = :rubycli_eval_mode
    EVAL_BINDING = Object.new.instance_eval { binding }

    def eval_mode?
      Thread.current[THREAD_KEY] == true
    end

    def with_eval_mode(enabled = true)
      previous = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = enabled
      yield
    ensure
      Thread.current[THREAD_KEY] = previous
    end

    def coerce_eval_value(value)
      case value
      when String
        evaluate_string(value)
      when Array
        value.map { |item| coerce_eval_value(item) }
      when Hash
        value.transform_values { |item| coerce_eval_value(item) }
      else
        value
      end
    rescue StandardError => e
      raise Rubycli::ArgumentError, "Failed to evaluate Ruby code: #{e.message}"
    end

    private

    def evaluate_string(expression)
      trimmed = expression.strip
      return trimmed if trimmed.empty?

      EVAL_BINDING.eval(trimmed)
    end
  end
end
