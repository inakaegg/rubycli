# frozen_string_literal: true

# Example showing how comments beyond the live signature are treated.
module FallbackExampleWithExtraDocs
  module_function

  # AMOUNT [Integer] Base amount to process
  # CLAMP [Integer] (unused placeholder)
  # --ghost [Boolean] Imaginary toggle that is not implemented
  def scale(amount)
    amount * 2
  end
end
