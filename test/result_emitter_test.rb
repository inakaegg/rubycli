# frozen_string_literal: true

require 'test_helper'

class ResultEmitterTest < Minitest::Test
  def test_emits_pretty_json_for_hash_when_print_enabled
    environment = Rubycli::Environment.new(env: { 'RUBYCLI_PRINT_RESULT' => 'true' })
    emitter = Rubycli::ResultEmitter.new(environment: environment)

    output, _err = capture_io do
      emitter.emit({ name: 'Ruby', level: 3 })
    end

    assert_includes output, "\"name\": \"Ruby\""
    assert_includes output, "\"level\": 3"
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
end
