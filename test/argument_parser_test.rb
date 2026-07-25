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
  # --occurred-at MOMENT [DateTime] Calendar timestamp
  # --budget AMOUNT [BigDecimal] Budget amount
  # --input FILE [Pathname] Input file
  def ingest(date:, moment:, occurred_at:, budget:, input:)
    {
      date: date,
      moment: moment,
      occurred_at: occurred_at,
      budget: budget,
      input: input
    }
  end
end

module UndocumentedKeywordSamples
  module_function

  def call(name:, verbose: false)
    [name, verbose]
  end
end

module RestParameterSamples
  module_function

  # VALUES... [Symbol] Values to collect
  def collect(*values)
    values
  end

  # LEVELS... [:info, :warn] Allowed levels
  def choose(*levels)
    levels
  end

  # HEAD [String] Required head
  # VALUES... [Symbol] Remaining values
  def with_head(head, *values)
    [head, values]
  end

  # HEAD [String] Required head
  # VALUES... [Symbol] Middle values
  # TAIL [Integer] Required tail
  def with_tail(head, *values, tail)
    [head, values, tail]
  end

  # PREFIX [Symbol] Optional prefix
  # VALUE [Integer] Required value
  def optional_before_required(prefix = :default, value)
    [prefix, value]
  end
end

module JsonTypeSamples
  module_function

  # --payload VALUE [JSON] JSON payload
  def accept(payload:)
    payload
  end

  # --payload VALUE [Hash] Hash payload
  def accept_hash(payload:)
    payload
  end
end

module ScalarTypeSamples
  module_function

  # CODE [String] Positional code
  # --label VALUE [String] Label code
  def strings(code, label:)
    [code, label]
  end

  # VALUE [Symbol] Symbol value
  def symbol(value)
    value
  end

  # --codes VALUES... [String] String codes
  def string_list(codes:)
    codes
  end

  # --codes VALUES... [Array<String>] Generic string codes
  def generic_string_list(codes:)
    codes
  end

  # ITEMS [String[]] Positional string codes
  def positional_string_list(items)
    items
  end

  # ITEMS [Array<String>] Generic positional string codes
  def generic_positional_string_list(items)
    items
  end

  # --flags VALUES... [Boolean] Boolean flags
  def boolean_list(flags:)
    flags
  end

  # VALUE [String] Assignment-like text
  def text(value)
    value
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

  def test_required_option_rejects_following_option_as_its_value
    method = DocExamples::TaggedSamples.new.method(:greet)

    error = assert_raises(Rubycli::ArgumentError) do
      @parser.parse(['Alice', '--greeting', '--shout'], method)
    end

    assert_includes error.message, "Option '--greeting' requires a value"
  end

  def test_required_option_accepts_true_as_an_explicit_value
    method = DocExamples::TaggedSamples.new.method(:greet)

    pos_args, kw_args = @parser.parse(['Alice', '--greeting', 'true'], method)

    assert_equal ['Alice'], pos_args
    assert_equal({ greeting: true }, kw_args)
  end

  def test_required_option_accepts_lone_dash_as_its_value
    method = StdTypeSamples.method(:ingest)

    pos_args, kw_args = @parser.parse(['--input', '-'], method)

    assert_empty pos_args
    assert_equal Pathname.new('-'), kw_args[:input]
  end

  def test_double_dash_preserves_following_option_like_values_as_positionals
    callable = ->(*values) { values }

    pos_args, kw_args = @parser.parse(['--', '--literal', 'name=value'], callable)

    assert_equal ['--literal', 'name=value'], pos_args
    assert_empty kw_args
  end

  def test_undocumented_required_keyword_rejects_following_option_as_its_value
    method = UndocumentedKeywordSamples.method(:call)

    error = assert_raises(Rubycli::ArgumentError) do
      @parser.parse(['--name', '--verbose'], method)
    end

    assert_includes error.message, "Option '--name' requires a value"
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
      '--occurred-at', '2024-12-25T10:00:00+09:00',
      '--budget', '123.45',
      '--input', '/tmp/data.txt'
    ]
    pos_args, kw_args = @parser.parse(args, method)

    assert_empty pos_args
    assert_instance_of Date, kw_args[:date]
    assert_instance_of Time, kw_args[:moment]
    assert_instance_of DateTime, kw_args[:occurred_at]
    assert_instance_of BigDecimal, kw_args[:budget]
    assert_instance_of Pathname, kw_args[:input]
    @environment.enable_strict_input!
    assert_silent { @parser.validate_inputs(method, pos_args, kw_args) }
  end

  def test_required_option_accepts_negative_exponent_value
    method = StdTypeSamples.method(:ingest)

    pos_args, kw_args = @parser.parse(['--budget', '-1e3'], method)

    assert_empty pos_args
    assert_equal BigDecimal('-1e3'), kw_args[:budget]
  end

  def test_json_type_accepts_an_array_literal
    method = JsonTypeSamples.method(:accept)

    pos_args, kw_args = @parser.parse(['--payload', '[1,2]'], method)

    assert_empty pos_args
    assert_equal({ payload: [1, 2] }, kw_args)
    @environment.enable_strict_input!
    assert_silent { @parser.validate_inputs(method, pos_args, kw_args) }
  end

  def test_json_type_rejects_scalar_json
    method = JsonTypeSamples.method(:accept)

    error = assert_raises(Rubycli::ArgumentError) do
      @parser.parse(['--payload', '1'], method)
    end

    assert_includes error.message, 'JSON value must be an object or array'
  end

  def test_hash_type_rejects_an_array_literal
    method = JsonTypeSamples.method(:accept_hash)

    error = assert_raises(Rubycli::ArgumentError) do
      @parser.parse(['--payload', '[1,2]'], method)
    end

    assert_includes error.message, 'Hash value must be an object'
  end

  def test_string_annotations_preserve_numeric_looking_tokens
    method = ScalarTypeSamples.method(:strings)

    pos_args, kw_args = @parser.parse(['00123', '--label', '00456'], method)

    assert_equal ['00123'], pos_args
    assert_equal({ label: '00456' }, kw_args)
    @environment.enable_strict_input!
    assert_silent { @parser.validate_inputs(method, pos_args, kw_args) }
  end

  def test_symbol_annotation_converts_numeric_looking_token
    method = ScalarTypeSamples.method(:symbol)

    pos_args, kw_args = @parser.parse(['123'], method)

    assert_equal [:"123"], pos_args
    assert_empty kw_args
  end

  def test_symbol_annotation_preserves_symbol_literal_value
    method = ScalarTypeSamples.method(:symbol)

    pos_args, kw_args = @parser.parse([':foo'], method)

    assert_equal [:foo], pos_args
    assert_empty kw_args
  end

  def test_string_array_annotation_preserves_numeric_looking_token
    method = ScalarTypeSamples.method(:string_list)

    pos_args, kw_args = @parser.parse(['--codes', '001'], method)

    assert_empty pos_args
    assert_equal({ codes: ['001'] }, kw_args)
  end

  def test_string_array_annotation_preserves_quoted_boolean_and_null_tokens
    method = ScalarTypeSamples.method(:string_list)

    pos_args, kw_args = @parser.parse(['--codes', '["true","null"]'], method)

    assert_empty pos_args
    assert_equal({ codes: %w[true null] }, kw_args)
    @environment.enable_strict_input!
    assert_silent { @parser.validate_inputs(method, pos_args, kw_args) }
  end

  def test_generic_string_array_annotation_preserves_quoted_boolean_and_null_tokens
    method = ScalarTypeSamples.method(:generic_string_list)

    pos_args, kw_args = @parser.parse(['--codes', '["true","null"]'], method)

    assert_empty pos_args
    assert_equal({ codes: %w[true null] }, kw_args)
    @environment.enable_strict_input!
    assert_silent { @parser.validate_inputs(method, pos_args, kw_args) }
  end

  def test_positional_string_array_preserves_quoted_boolean_and_null_tokens
    method = ScalarTypeSamples.method(:positional_string_list)

    pos_args, kw_args = @parser.parse(['["true","null"]'], method)

    assert_equal [%w[true null]], pos_args
    assert_empty kw_args
    @environment.enable_strict_input!
    assert_silent { @parser.validate_inputs(method, pos_args, kw_args) }
  end

  def test_generic_positional_string_array_preserves_quoted_boolean_and_null_tokens
    method = ScalarTypeSamples.method(:generic_positional_string_list)

    pos_args, kw_args = @parser.parse(['["true","null"]'], method)

    assert_equal [%w[true null]], pos_args
    assert_empty kw_args
    @environment.enable_strict_input!
    assert_silent { @parser.validate_inputs(method, pos_args, kw_args) }
  end

  def test_required_repeated_boolean_option_consumes_and_converts_its_value
    method = ScalarTypeSamples.method(:boolean_list)
    metadata = @registry.metadata_for(method)

    assert_equal ['Boolean[]'], metadata[:options].first.types

    pos_args, kw_args = @parser.parse(['--flags', 'true,false'], method)

    assert_empty pos_args
    assert_equal({ flags: [true, false] }, kw_args)
    assert_raises(Rubycli::ArgumentError) do
      @parser.parse(['--flags', 'true,nope'], method)
    end
  end

  def test_assignment_like_token_remains_positional_without_matching_keyword
    method = ScalarTypeSamples.method(:text)

    pos_args, kw_args = @parser.parse(['name=value'], method)

    assert_equal ['name=value'], pos_args
    assert_empty kw_args
  end

  def test_assignment_token_still_sets_a_matching_keyword
    method = UndocumentedKeywordSamples.method(:call)

    pos_args, kw_args = @parser.parse(['name=Ruby'], method)

    assert_empty pos_args
    assert_equal({ name: 'Ruby' }, kw_args)
  end

  def test_assignment_token_uses_matching_keyword_type_conversion
    method = ScalarTypeSamples.method(:strings)

    pos_args, kw_args = @parser.parse(['code', 'label=00456'], method)

    assert_equal ['code'], pos_args
    assert_equal({ label: '00456' }, kw_args)
  end

  def test_rest_parameter_metadata_converts_every_remaining_positional
    method = RestParameterSamples.method(:collect)
    metadata = @registry.metadata_for(method)

    assert_equal [:values], metadata[:positionals_map].keys
    assert_equal ['Symbol[]'], metadata[:positionals_map][:values].types

    pos_args, kw_args = @parser.parse(%w[alpha beta], method)

    assert_equal %i[alpha beta], pos_args
    assert_empty kw_args
  end

  def test_rest_parameter_strict_validation_checks_every_remaining_positional
    method = RestParameterSamples.method(:choose)
    pos_args, kw_args = @parser.parse([':info', 'oops'], method)
    @environment.enable_strict_input!

    error = assert_raises(Rubycli::ArgumentError) do
      @parser.validate_inputs(method, pos_args, kw_args)
    end

    assert_includes error.message, 'oops'
  end

  def test_rest_parameter_conversion_allows_no_remaining_values
    method = RestParameterSamples.method(:with_head)

    pos_args, kw_args = @parser.parse(['head'], method)

    assert_equal ['head'], pos_args
    assert_empty kw_args
  end

  def test_rest_parameter_reserves_trailing_required_arguments
    method = RestParameterSamples.method(:with_tail)

    pos_args, kw_args = @parser.parse(%w[head alpha beta 7], method)

    assert_equal ['head', :alpha, :beta, 7], pos_args
    assert_empty kw_args
    assert_equal ['head', %i[alpha beta], 7], method.call(*pos_args)
    @environment.enable_strict_input!
    assert_silent { @parser.validate_inputs(method, pos_args, kw_args) }
  end

  def test_optional_positional_reserves_a_following_required_argument
    method = RestParameterSamples.method(:optional_before_required)

    pos_args, kw_args = @parser.parse(['7'], method)

    assert_equal [7], pos_args
    assert_empty kw_args
    assert_equal [:default, 7], method.call(*pos_args)
    @environment.enable_strict_input!
    assert_silent { @parser.validate_inputs(method, pos_args, kw_args) }
  end
end
