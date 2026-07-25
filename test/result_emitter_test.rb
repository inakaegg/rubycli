# frozen_string_literal: true

require 'test_helper'

class ResultEmitterTest < Minitest::Test
  def test_emits_pretty_json_for_hash_when_print_enabled
    environment = Rubycli::Environment.new(env: { 'RUBYCLI_PRINT_RESULT' => 'true' })
    emitter = Rubycli::ResultEmitter.new(environment: environment)

    output, _err = capture_io do
      emitter.emit({ name: 'Ruby', level: 3 })
    end

    assert_includes output, '"name": "Ruby"'
    assert_includes output, '"level": 3'
  end

  def test_suppresses_output_when_print_flag_disabled
    environment = Rubycli::Environment.new(env: {})
    emitter = Rubycli::ResultEmitter.new(environment: environment)

    output, _err = capture_io do
      emitter.emit('quiet')
    end

    assert_equal '', output
  end

  def test_skips_nil_and_class_results
    environment = Rubycli::Environment.new(env: { 'RUBYCLI_PRINT_RESULT' => 'true' })
    emitter = Rubycli::ResultEmitter.new(environment: environment)

    output, _err = capture_io do
      emitter.emit(nil)
      emitter.emit(Rubycli)
    end

    assert_equal '', output
  end

  def test_circular_array_falls_back_to_inspect
    environment = Rubycli::Environment.new(env: { 'RUBYCLI_PRINT_RESULT' => 'true' })
    emitter = Rubycli::ResultEmitter.new(environment: environment)
    result = []
    result << result

    output, _err = capture_io do
      emitter.emit(result)
    end

    assert_equal "[[...]]\n", output
  end

  def test_emits_scalars_as_plain_text
    environment = Rubycli::Environment.new(env: { 'RUBYCLI_PRINT_RESULT' => 'true' })
    emitter = Rubycli::ResultEmitter.new(environment: environment)

    output, _err = capture_io do
      emitter.emit('text')
      emitter.emit(42)
      emitter.emit(true)
      emitter.emit(false)
    end

    assert_equal "text\n42\ntrue\nfalse\n", output
  end

  def test_suppresses_empty_string_result
    environment = Rubycli::Environment.new(env: { 'RUBYCLI_PRINT_RESULT' => 'true' })
    emitter = Rubycli::ResultEmitter.new(environment: environment)

    output, _err = capture_io do
      emitter.emit('')
    end

    assert_equal '', output
  end

  def test_serializes_objects_through_to_h_or_to_ary
    environment = Rubycli::Environment.new(env: { 'RUBYCLI_PRINT_RESULT' => 'true' })
    emitter = Rubycli::ResultEmitter.new(environment: environment)
    hash_like = Struct.new(:name).new('Ruby')
    array_like = Class.new do
      def to_ary
        %w[alpha beta]
      end
    end.new

    output, _err = capture_io do
      emitter.emit(hash_like)
      emitter.emit(array_like)
    end

    assert_includes output, '"name": "Ruby"'
    assert_includes output, '"alpha"'
    assert_includes output, '"beta"'
  end

  def test_falls_back_to_inspect_for_plain_objects
    environment = Rubycli::Environment.new(env: { 'RUBYCLI_PRINT_RESULT' => 'true' })
    emitter = Rubycli::ResultEmitter.new(environment: environment)
    result = Object.new

    output, _err = capture_io do
      emitter.emit(result)
    end

    assert_equal "#{result.inspect}\n", output
  end
end
