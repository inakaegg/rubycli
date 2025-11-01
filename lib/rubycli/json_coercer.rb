module Rubycli
  class JsonCoercer
    THREAD_KEY = :rubycli_json_mode

    def json_mode?
      Thread.current[THREAD_KEY] == true
    end

    def with_json_mode(enabled = true)
      previous = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = enabled
      yield
    ensure
      Thread.current[THREAD_KEY] = previous
    end

    def coerce_json_value(value)
      case value
      when String
        JSON.parse(value)
      when Array
        value.map { |item| coerce_json_value(item) }
      when Hash
        value.transform_values { |item| coerce_json_value(item) }
      else
        value
      end
    rescue JSON::ParserError => e
      raise Rubycli::ArgumentError, "Failed to parse as JSON: #{e.message}"
    end
  end
end
