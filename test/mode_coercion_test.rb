# frozen_string_literal: true

require 'test_helper'

class ModeCoercionTest < Minitest::Test
  def test_apply_argument_coercions_with_json_mode
    pos_args = ['{"name":"Ruby"}', '2']
    kw_args = { options: '{"verbose":true}' }

    Rubycli.with_json_mode(true) do
      Rubycli.apply_argument_coercions(pos_args, kw_args)
    end

    assert_equal([{ 'name' => 'Ruby' }, 2], pos_args)
    assert_equal({ options: { 'verbose' => true } }, kw_args)
    refute Rubycli.json_mode?, 'json mode should be reset after block'
  end

  def test_apply_argument_coercions_with_eval_mode
    pos_args = ['[1, 2, 3]']
    kw_args = { config: '{ greeting: "hello", times: 2 }' }

    Rubycli.with_eval_mode(true) do
      Rubycli.apply_argument_coercions(pos_args, kw_args)
    end

    assert_equal([[1, 2, 3]], pos_args)
    assert_equal({ config: { greeting: 'hello', times: 2 } }, kw_args)
    refute Rubycli.eval_mode?, 'eval mode should be reset after block'
  end

  def test_apply_argument_coercions_rejects_json_and_eval_mix
    pos_args = []
    kw_args = {}

    Rubycli.with_json_mode(true) do
      error = assert_raises(Rubycli::ArgumentError) do
        Rubycli.with_eval_mode(true) do
          Rubycli.apply_argument_coercions(pos_args, kw_args)
        end
      end
      assert_match(/cannot be used together/, error.message)
    end
  end

  def test_json_coercion_invalid_payload
    error = assert_raises(Rubycli::ArgumentError) do
      Rubycli.json_coercer.coerce_json_value('{"oops": ')
    end
    assert_match(/Failed to parse as JSON/, error.message)
  end
end
