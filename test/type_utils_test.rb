# frozen_string_literal: true

require 'test_helper'

class TypeUtilsTest < Minitest::Test
  def test_placeholder_inference_adds_boolean_for_optional_values_by_default
    types = Rubycli::TypeUtils.infer_types_from_placeholder([], { optional: true, list: false, base: 'VALUE' })

    assert_equal %w[Boolean String], types
  end

  def test_placeholder_inference_can_skip_the_optional_boolean_for_lists
    types = Rubycli::TypeUtils.infer_types_from_placeholder(
      [],
      { optional: true, list: true, base: 'VALUE' },
      include_optional_boolean: false
    )

    assert_equal ['String[]'], types
  end
end
