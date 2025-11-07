# frozen_string_literal: true

module Rubycli
  module Arguments
    # Lightweight mutable cursor over CLI tokens.
    class TokenStream
      def initialize(tokens)
        @tokens = Array(tokens).dup
        @index = 0
      end

      def current
        @tokens[@index]
      end

      def peek(offset = 1)
        @tokens[@index + offset]
      end

      def advance(count = 1)
        @index += count
      end

      def consume
        value = current
        advance
        value
      end

      def consume_remaining
        remaining = @tokens[@index..] || []
        @index = @tokens.length
        remaining
      end

      def finished?
        @index >= @tokens.length
      end
    end
  end
end
