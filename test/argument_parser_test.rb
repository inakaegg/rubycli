# frozen_string_literal: true

require 'test_helper'

class ArgumentParserTest < Minitest::Test
  def setup
    @environment = Rubycli::Environment.new(env: {}, argv: [])
    @registry = Rubycli::DocumentationRegistry.new(environment: @environment)
    @parser = Rubycli::ArgumentParser.new(
      environment: @environment,
      documentation_registry: @registry,
      json_coercer: Rubycli::JsonCoercer.new,
      debug_logger: nil
    )
  end

  def test_parses_tagged_options_and_booleans
    method = DocExamples::TaggedSamples.new.method(:greet)
    args = ['Alice', '--greeting', 'Hi', '-s', '--punctuation', '!']

    pos_args, kw_args = @parser.parse(args, method)

    assert_equal ['Alice'], pos_args
    assert_equal({ greeting: 'Hi', shout: true, punctuation: '!' }, kw_args)
  end

  def test_parses_concise_options_with_short_alias_and_array_conversion
    method = DocExamples::ConciseSamples.new.method(:describe)
    args = ['subject', '2', '-s', 'dramatic', '--tags', 'alpha,beta']

    pos_args, kw_args = @parser.parse(args, method)

    assert_equal ['subject', 2], pos_args
    assert_equal({ style: 'dramatic', tags: %w[alpha beta] }, kw_args)
  end

  def test_optional_value_option_without_argument_defaults_to_true
    method = DocExamples::ConciseSamples.new.method(:toggle)
    args = ['runner', '--enable', '--limit']

    pos_args, kw_args = @parser.parse(args, method)

    assert_equal ['runner'], pos_args
    assert_equal({ enable: true, limit: true }, kw_args)
  end

  def test_optional_value_option_with_numeric_argument_is_converted
    method = DocExamples::ConciseSamples.new.method(:toggle)
    args = ['runner', '--limit', '5']

    pos_args, kw_args = @parser.parse(args, method)

    assert_equal ['runner'], pos_args
    assert_equal({ limit: 5 }, kw_args)
  end

  def test_positional_literal_array_is_parsed_by_default
    pos_args, kw_args = @parser.parse(['["Alice","Bob"]'])

    assert_equal [%w[Alice Bob]], pos_args
    assert_equal({}, kw_args)
  end

  def test_positional_literal_hash_is_parsed_by_default
    method = DocExamples::TaggedSamples.new.method(:process)
    args = ['{"feature":true}', '--verbose']

    pos_args, kw_args = @parser.parse(args, method)

    assert_equal([{ 'feature' => true }], pos_args)
    assert_equal({ verbose: true }, kw_args)
  end
end
