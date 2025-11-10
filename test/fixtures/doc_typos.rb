# frozen_string_literal: true

module DocTypoSamples
  module_function

  # --bang [Booalean] Toggle an imaginary boolean flag
  def toggle(bang: false)
    bang
  end

  # LEVEL [:info, WARNNING] Severity level
  def set_level(level: :info)
    level
  end
end
