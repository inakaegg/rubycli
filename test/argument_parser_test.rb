# frozen_string_literal: true

require 'test_helper'
require_relative '../examples/documentation_style_showcase'
require 'date'
require 'time'
require 'bigdecimal'
require 'pathname'

module ValidationSamples
  module_function

  # LEVEL [:info, :warn] Severity level
  # --accept SOURCE [:official, :linked_content]
  def check(level, accept: :official)
    [level, accept]
  end

  # KIND %i[info warn] severity short-hand
  def choose(kind)
    kind
  end

  # NAME ["alpha", "beta"] string-only choices
  def label(name)
    name
  end
end

module StdTypeSamples
  module_function

  # --date DATE [Date]   Planned date
  # --moment TIME [Time] Execution timestamp
  # --budget AMOUNT [BigDecimal] Budget amount
  # --input FILE [Pathname] Input file
  def ingest(date:, moment:, budget:, input:)
    {
      date: date,
      moment: moment,
      budget: budget,
      input: input
    }
  end
end

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

  def test_list_option_accepts_yaml_array_in_default_mode
    method = DocumentationStyleShowcase.method(:canonical)
    args = ['subject', '--tags', '[1,2]']

    pos_args, kw_args = @parser.parse(args, method)

    assert_equal ['subject'], pos_args
    assert_equal({ tags: [1, 2] }, kw_args)
  end

  def test_list_option_accepts_comma_values_in_default_mode
    method = DocumentationStyleShowcase.method(:canonical)
    args = ['subject', '--tags', 'alpha,beta']

    pos_args, kw_args = @parser.parse(args, method)

    assert_equal ['subject'], pos_args
    assert_equal({ tags: %w[alpha beta] }, kw_args)
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

  def test_comma_delimited_string_stays_literal
    pos_args, _kw_args = @parser.parse(['1,2,3'])

    assert_equal(['1,2,3'], pos_args)
  end

  def test_basic_literal_conversions_for_positional_arguments
    pos_args, kw_args = @parser.parse(['nil', 'true', 'false', '42', '3.14', 'plain'])

    assert_equal ['nil', true, false, 42, 3.14, 'plain'], pos_args
    assert_equal({}, kw_args)
  end

  def test_preserves_raw_expressions_when_eval_mode_is_enabled
    Rubycli.with_eval_mode(true) do
      pos_args, kw_args = @parser.parse(['"a"+"b"'])
      assert_equal(['"a"+"b"'], pos_args)
      assert_equal({}, kw_args)
    end
  end

  def test_preserves_raw_values_when_json_mode_is_enabled
    Rubycli.with_json_mode(true) do
      pos_args, kw_args = @parser.parse(['"a"'])
      assert_equal(['"a"'], pos_args)
      assert_equal({}, kw_args)
    end
  end

  def test_preserves_keyword_values_under_json_mode
    method = DocExamples::ConciseSamples.new.method(:describe)

    Rubycli.with_json_mode(true) do
      pos_args, kw_args = @parser.parse(['subject', '--tags', '["alpha","beta"]'], method)
      assert_equal('subject', pos_args.first)
      assert_equal({ tags: '["alpha","beta"]' }, kw_args)
    end
  end

  def test_preserves_keyword_values_under_eval_mode
    method = DocExamples::ConciseSamples.new.method(:describe)

    Rubycli.with_eval_mode(true) do
      pos_args, kw_args = @parser.parse(['subject', '--tags', '[:alpha, :beta]'], method)
      assert_equal('subject', pos_args.first)
      assert_equal({ tags: '[:alpha, :beta]' }, kw_args)
    end
  end

  def test_validate_inputs_warns_when_values_outside_choices
    method = ValidationSamples.method(:check)
    warnings = []
    @environment.stub(:handle_input_violation, ->(msg) { warnings << msg }) do
      @parser.validate_inputs(method, ['invalid'], { accept: 'unknown' })
    end

    refute_empty warnings
    assert warnings.all? { |msg| msg.include?('invalid') || msg.include?('unknown') }
  end

  def test_validate_inputs_raises_when_strict_input_enabled
    method = ValidationSamples.method(:check)
    @environment.enable_strict_input!

    assert_raises(Rubycli::ArgumentError) do
      @parser.validate_inputs(method, ['invalid'], { accept: 'unknown' })
    end
  end

  def test_percent_i_literals_are_captured
    metadata = @registry.metadata_for(ValidationSamples.method(:choose))
    values = metadata[:positionals].first.allowed_values.map { |entry| entry[:value] }
    assert_equal %i[info warn], values
  end

  def test_percent_i_literals_validate_input
    method = ValidationSamples.method(:choose)
    warnings = []
    @environment.stub(:handle_input_violation, ->(msg) { warnings << msg }) do
      @parser.validate_inputs(method, ['oops'], {})
    end
    refute_empty warnings
    assert_includes warnings.first, 'oops'
  end

  def test_symbol_literal_accepts_symbol_input_only
    method = ValidationSamples.method(:choose)
    ok_args, = @parser.parse([':info'], method)
    assert_equal [:info], ok_args
    assert_silent { @parser.validate_inputs(method, ok_args, {}) }

    warnings = []
    @environment.stub(:handle_input_violation, ->(msg) { warnings << msg }) do
      bad_args, = @parser.parse(['info'], method)
      @parser.validate_inputs(method, bad_args, {})
    end
    refute_empty warnings
    assert_includes warnings.first, 'info'
    refute_includes warnings.first, '%i'
  end

  def test_string_literals_reject_symbols
    method = ValidationSamples.method(:label)
    ok_args, = @parser.parse(['alpha'], method)
    assert_equal ['alpha'], ok_args
    assert_silent { @parser.validate_inputs(method, ok_args, {}) }

    warnings = []
    @environment.stub(:handle_input_violation, ->(msg) { warnings << msg }) do
      bad_args, = @parser.parse([':alpha'], method)
      @parser.validate_inputs(method, bad_args, {})
    end
    refute_empty warnings
    assert_includes warnings.first, ':alpha'
  end

  def test_standard_type_hints_convert_to_stdlib_classes
    method = StdTypeSamples.method(:ingest)
    args = [
      '--date', '2024-12-25',
      '--moment', '2024-12-25T10:00:00Z',
      '--budget', '123.45',
      '--input', '/tmp/data.txt'
    ]
    pos_args, kw_args = @parser.parse(args, method)

    assert_empty pos_args
    assert_instance_of Date, kw_args[:date]
    assert_instance_of Time, kw_args[:moment]
    assert_instance_of BigDecimal, kw_args[:budget]
    assert_instance_of Pathname, kw_args[:input]
  end
end
