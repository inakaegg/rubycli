# frozen_string_literal: true

module Rubycli
  # Coordinates json/eval argument modes and enforces mutual exclusion.
  class ArgumentModeController
    def initialize(json_coercer:, eval_coercer:)
      @json_coercer = json_coercer
      @eval_coercer = eval_coercer
    end

    def json_mode?
      @json_coercer.json_mode?
    end

    def eval_mode?
      @eval_coercer.eval_mode?
    end

    def with_json_mode(enabled = true, &block)
      enforce_mutual_exclusion!(:json, enabled)
      @json_coercer.with_json_mode(enabled, &block)
    end

    def with_eval_mode(enabled = true, **options, &block)
      enforce_mutual_exclusion!(:eval, enabled)
      @eval_coercer.with_eval_mode(enabled, **options, &block)
    end

    def apply_argument_coercions(positional_args, keyword_args)
      ensure_modes_compatible!

      if json_mode?
        coerce_values!(positional_args, keyword_args) { |value| @json_coercer.coerce_json_value(value) }
      end

      if eval_mode?
        coerce_values!(positional_args, keyword_args) { |value| @eval_coercer.coerce_eval_value(value) }
      end
    rescue ::ArgumentError => e
      raise Rubycli::ArgumentError, e.message
    end

    private

    def enforce_mutual_exclusion!(mode, enabled)
      return unless enabled

      case mode
      when :json
        raise Rubycli::ArgumentError, '--json-args cannot be combined with --eval-args or --eval-lax' if eval_mode?
      when :eval
        raise Rubycli::ArgumentError, '--json-args cannot be combined with --eval-args or --eval-lax' if json_mode?
      end
    end

    def ensure_modes_compatible!
      if json_mode? && eval_mode?
        raise Rubycli::ArgumentError, '--json-args cannot be combined with --eval-args or --eval-lax'
      end
    end

    def coerce_values!(positional_args, keyword_args)
      positional_args.map! { |value| yield(value) }
      keyword_args.keys.each do |key|
        keyword_args[key] = yield(keyword_args[key])
      end
    end
  end
end
