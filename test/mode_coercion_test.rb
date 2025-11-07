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

  def test_eval_mode_handles_strings_with_embedded_quotes
    pos_args = ['"a" + "b"']
    kw_args = {}

    Rubycli.with_eval_mode(true) do
      Rubycli.apply_argument_coercions(pos_args, kw_args)
    end

    assert_equal(['ab'], pos_args)
    assert_equal({}, kw_args)
  end

  def test_eval_lax_mode_falls_back_to_original_string_on_syntax_error
    pos_args = ['https://example.com/']
    kw_args = { ttl: '60*60*2' }

    Rubycli.with_eval_mode(true, lax: true) do
      _, err = capture_io do
        Rubycli.apply_argument_coercions(pos_args, kw_args)
      end

      assert_match(/Failed to evaluate argument/, err)
    end

    assert_equal(['https://example.com/'], pos_args)
    assert_equal({ ttl: 7200 }, kw_args)
    refute Rubycli.eval_mode?
    refute Rubycli.eval_lax_mode?
  end

  def test_eval_lax_mode_handles_name_error_inputs
    pos_args = ['https://example.com']
    kw_args = {}

    Rubycli.with_eval_mode(true, lax: true) do
      capture_io do
        Rubycli.apply_argument_coercions(pos_args, kw_args)
      end
    end

    assert_equal(['https://example.com'], pos_args)
    assert_equal({}, kw_args)
  end

  def test_json_mode_handles_simple_string_values
    pos_args = ['"a"']
    kw_args = {}

    Rubycli.with_json_mode(true) do
      Rubycli.apply_argument_coercions(pos_args, kw_args)
    end

    assert_equal(['a'], pos_args)
    assert_equal({}, kw_args)
  end

  def test_json_mode_parses_nested_structures_and_keywords
    pos_args = ['[1, 2, 3]']
    kw_args = { payload: '{"flag":true,"count":5}', tags: '["alpha","beta"]' }

    Rubycli.with_json_mode(true) do
      Rubycli.apply_argument_coercions(pos_args, kw_args)
    end

    assert_equal([[1, 2, 3]], pos_args)
    assert_equal({ payload: { 'flag' => true, 'count' => 5 }, tags: %w[alpha beta] }, kw_args)
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
      assert_match(/cannot be combined/, error.message)
    end
  end

  def test_json_coercion_invalid_payload
    error = assert_raises(Rubycli::ArgumentError) do
      Rubycli.json_coercer.coerce_json_value('{"oops": ')
    end
    assert_match(/Failed to parse as JSON/, error.message)
  end
end
