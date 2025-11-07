module Rubycli
  class EvalCoercer
    THREAD_KEY = :rubycli_eval_mode
    LAX_THREAD_KEY = :rubycli_eval_lax_mode
    EVAL_BINDING = Object.new.instance_eval { binding }

    def eval_mode?
      Thread.current[THREAD_KEY] == true
    end

    def eval_lax_mode?
      Thread.current[LAX_THREAD_KEY] == true
    end

    def with_eval_mode(enabled = true, lax: false)
      previous = Thread.current[THREAD_KEY]
      previous_lax = Thread.current[LAX_THREAD_KEY]
      Thread.current[THREAD_KEY] = enabled
      Thread.current[LAX_THREAD_KEY] = enabled && lax
      yield
    ensure
      Thread.current[THREAD_KEY] = previous
      Thread.current[LAX_THREAD_KEY] = previous_lax
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
    rescue SyntaxError, NameError => e
      if eval_lax_mode?
        warn "[rubycli] Failed to evaluate argument as Ruby (#{e.message.strip}). Passing it through because --eval-lax is enabled."
        expression
      else
        raise
      end
    end
  end
end
