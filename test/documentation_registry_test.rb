# frozen_string_literal: true

require 'test_helper'
require_relative '../examples/documentation_style_showcase'

module ExtraDocSamples
  module_function

  # NAME [String] Sample argument
  # EXTRA [Integer] Placeholder not used in implementation
  def greet(name)
    name
  end

  module GhostOption
    module_function

    # NAME [String] Sample argument
    # --ghost [Boolean] Option not implemented
    def greet(name)
      name
    end
  end

  module Choices
    module_function

    # LEVEL [:info, :warn] Severity level
    # --accept SOURCE [:official, :linked_content, Boolean] Sources to include
    def select(level, accept: :official)
      [level, accept]
    end
  end
end

module InlineDocSamples
  module_function

  # --query QUERY Search query passed to DuckDuckGo
  def search(query:); end
end

module TaggedOrderSamples
  module_function

  # @param second [Integer] Second value
  # @param first [String] First value
  def reorder(first, second)
    [first, second]
  end
end

module ReturnShorthandDocSamples
  module_function

  # NAME [String] Who to greet
  # return String Rendered greeting
  def greet(name)
    "Hello, #{name}"
  end
end

module ArticleSummarySamples
  module_function

  # A command that greets the given person.
  # NAME [String] Name to greet
  def greet(name)
    name
  end

  # I keep a counter for you.
  # COUNT [Integer] How many times
  def count(count)
    count
  end

  # A [String] Single letter placeholder with a type
  def typed(value)
    value
  end

  # JSON output formatter for reports.
  # NAME [String] Name to render
  def json_summary(name)
    name
  end

  # NAME Name to greet
  def bare_placeholder(name)
    name
  end
end

class DocumentationRegistryTest < Minitest::Test
  def setup
    @environment = Rubycli::Environment.new(env: {}, argv: [])
    @registry = Rubycli::DocumentationRegistry.new(environment: @environment)
  end

  def test_uppercase_prose_summary_is_kept_out_of_the_positional_table
    metadata = @registry.metadata_for(ArticleSummarySamples.method(:json_summary))

    assert_equal 'JSON output formatter for reports.', metadata[:summary]
    assert_equal ['NAME'], metadata[:positionals].map(&:label)
    assert_equal 'Name to render', metadata[:positionals].first.description
  end

  def test_untyped_placeholder_remains_a_placeholder_when_the_argument_needs_it
    metadata = @registry.metadata_for(ArticleSummarySamples.method(:bare_placeholder))

    assert_nil metadata[:summary]
    assert_equal ['NAME'], metadata[:positionals].map(&:label)
    assert_equal 'Name to greet', metadata[:positionals].first.description
  end

  def test_summary_starting_with_an_article_is_not_parsed_as_a_placeholder
    metadata = @registry.metadata_for(ArticleSummarySamples.method(:greet))

    assert_equal 'A command that greets the given person.', metadata[:summary]
    assert_equal ['NAME'], metadata[:positionals].map(&:label)
    assert_equal 'Name to greet', metadata[:positionals].first.description
  end

  def test_summary_starting_with_a_pronoun_is_not_parsed_as_a_placeholder
    metadata = @registry.metadata_for(ArticleSummarySamples.method(:count))

    assert_equal 'I keep a counter for you.', metadata[:summary]
    assert_equal ['COUNT'], metadata[:positionals].map(&:label)
  end

  def test_single_letter_placeholder_with_a_type_annotation_still_parses
    metadata = @registry.metadata_for(ArticleSummarySamples.method(:typed))

    assert_equal ['A'], metadata[:positionals].map(&:label)
    assert_equal ['String'], metadata[:positionals].first.types
    assert_nil metadata[:summary]
  end

  def test_tagged_param_metadata_parses_options_and_positionals
    method = DocExamples::TaggedSamples.instance_method(:greet)
    metadata = @registry.metadata_for(method)

    expected_summary = 'Compose a friendly greeting. Supports both positional and keyword documentation using YARD tags.'
    assert_equal expected_summary, metadata[:summary]
    assert_equal(
      [
        'Compose a friendly greeting.',
        '',
        'Supports both positional and keyword documentation using YARD tags.'
      ],
      metadata[:summary_lines]
    )

    name_doc = metadata[:positionals].first
    assert_equal 'NAME', name_doc.label
    assert_equal ['String'], name_doc.types
    assert_equal 'Person to greet', name_doc.description
    refute name_doc.inline_type_annotation

    options = metadata[:options]
    assert_equal %i[greeting shout punctuation], options.map(&:keyword)

    greeting_opt = options[0]
    assert_equal '--greeting', greeting_opt.long
    assert_equal '-g', greeting_opt.short
    assert_equal 'GREETING', greeting_opt.value_name
    assert_equal ['String'], greeting_opt.types
    refute greeting_opt.boolean_flag
    assert greeting_opt.requires_value
    assert_equal "'Hello'", greeting_opt.default_value
    assert_equal :tagged_param, greeting_opt.doc_format

    shout_opt = options[1]
    assert_equal '--shout', shout_opt.long
    assert_equal '-s', shout_opt.short
    assert shout_opt.boolean_flag
    refute shout_opt.requires_value
    assert_equal ['Boolean'], shout_opt.types
    assert_equal 'Emit uppercase output', shout_opt.description

    punctuation_opt = options[2]
    assert_equal '--punctuation', punctuation_opt.long
    assert_nil punctuation_opt.short
    assert_equal 'PUNCT', punctuation_opt.value_name
    assert_equal %w[String nil], punctuation_opt.types
    assert punctuation_opt.requires_value
    refute punctuation_opt.boolean_flag
    assert_includes [nil, 'nil'], punctuation_opt.default_value

    returns = metadata[:returns]
    assert_equal 1, returns.size
    assert_equal ['String'], returns.first.types
    assert_equal 'Finalised greeting', returns.first.description
  end

  def test_tagged_param_with_positional_conversion
    method = DocExamples::TaggedSamples.instance_method(:process)
    metadata = @registry.metadata_for(method)

    assert_equal 1, metadata[:positionals].size
    data_doc = metadata[:positionals].first
    assert_equal 'JSON', data_doc.label
    assert_equal ['Hash'], data_doc.types
    assert_equal 'Structured payload', data_doc.description

    assert_equal [:verbose], metadata[:options].map(&:keyword)
    verbose_opt = metadata[:options].first
    assert_equal '--verbose', verbose_opt.long
    assert_equal '-v', verbose_opt.short
    assert verbose_opt.boolean_flag
    refute verbose_opt.requires_value
    assert_equal ['Boolean'], verbose_opt.types
  end

  def test_tagged_positionals_are_aligned_by_parameter_name
    metadata = @registry.metadata_for(TaggedOrderSamples.method(:reorder))

    assert_equal %i[first second], metadata[:positionals_map].keys
    assert_equal ['String'], metadata[:positionals_map][:first].types
    assert_equal 'First value', metadata[:positionals_map][:first].description
    assert_equal ['Integer'], metadata[:positionals_map][:second].types
    assert_equal 'Second value', metadata[:positionals_map][:second].description
  end

  def test_concise_format_includes_inline_annotations
    method = DocExamples::ConciseSamples.instance_method(:describe)
    metadata = @registry.metadata_for(method)

    labels = metadata[:positionals].map(&:label)
    assert_equal ['<subject>', '<count>'], labels

    count_doc = metadata[:positionals].last
    assert count_doc.inline_type_annotation
    assert_equal '[Integer]', count_doc.inline_type_text
    assert_equal ['Integer'], count_doc.types
    assert_equal 'Number of repetitions', count_doc.description

    options = metadata[:options]
    assert_equal %i[style tags], options.map(&:keyword)

    style_opt = options.first
    assert_equal '-s', style_opt.short
    assert_equal '--style', style_opt.long
    assert_equal ['String'], style_opt.types
    assert style_opt.inline_type_annotation
    assert_equal '[String]', style_opt.inline_type_text

    tags_opt = options.last
    assert_equal '--tags', tags_opt.long
    assert_equal ['String[]'], tags_opt.types
    assert tags_opt.inline_type_annotation
    assert_equal '[String[]]', tags_opt.inline_type_text
    assert_equal 'Comma-separated tags', tags_opt.description
  end

  def test_parenthesized_type_annotations
    method = DocExamples::TypeHintSamples.instance_method(:analyse)
    metadata = @registry.metadata_for(method)

    positionals = metadata[:positionals]
    assert_equal 2, positionals.size

    file_doc, pattern_doc = positionals
    assert_equal '<file>', file_doc.label
    assert_equal ['String'], file_doc.types
    assert file_doc.inline_type_annotation
    assert_equal '[String]', file_doc.inline_type_text

    assert_equal '<pattern>', pattern_doc.label
    assert_equal %w[String nil], pattern_doc.types
    assert pattern_doc.inline_type_annotation
    assert_equal '[String, nil]', pattern_doc.inline_type_text

    format_opt = metadata[:options].find { |opt| opt.keyword == :format }
    refute_nil format_opt
    assert_equal '--format', format_opt.long
    assert_equal ['String'], format_opt.types
    assert format_opt.inline_type_annotation
    assert_equal '[String]', format_opt.inline_type_text

    tags_opt = metadata[:options].find { |opt| opt.keyword == :tags }
    refute_nil tags_opt
    assert_equal '--tags', tags_opt.long
    assert_equal ['String[]'], tags_opt.types
    assert tags_opt.inline_type_annotation
    assert_equal '[String[]]', tags_opt.inline_type_text
    assert tags_opt.value_name.start_with?('<tag>')
  end

  def test_boolean_and_optional_value_detection
    method = DocExamples::ConciseSamples.instance_method(:toggle)
    metadata = @registry.metadata_for(method)

    enable_opt = metadata[:options].find { |opt| opt.keyword == :enable }
    assert enable_opt.boolean_flag
    refute enable_opt.requires_value
    assert_equal ['Boolean'], enable_opt.types

    limit_opt = metadata[:options].find { |opt| opt.keyword == :limit }
    assert limit_opt.optional_value
    refute limit_opt.boolean_flag
    refute limit_opt.requires_value
    assert_equal %w[Boolean Integer], limit_opt.types
    assert limit_opt.inline_type_annotation
    assert_equal '[Boolean, Integer]', limit_opt.inline_type_text
  end

  def test_incomplete_documentation_uses_fallbacks
    method = DocExamples::IncompleteDocs.instance_method(:fallback)
    metadata = @registry.metadata_for(method)

    labels = metadata[:positionals].map(&:label)
    assert_equal %w[NAME ATTEMPTS], labels

    options = metadata[:options]
    assert_equal %i[safe_mode tag], options.map(&:keyword)

    safe_mode = options.first
    assert_equal :auto_generated, safe_mode.doc_format
    assert safe_mode.boolean_flag
    refute safe_mode.requires_value
    assert_equal ['Boolean'], safe_mode.types

    tag_opt = options.last
    assert_equal :auto_generated, tag_opt.doc_format
    refute tag_opt.boolean_flag
    assert tag_opt.requires_value
    assert_equal ['String'], tag_opt.types
  end

  def test_list_placeholder_promotes_scalar_type_to_array
    metadata = @registry.metadata_for(DocumentationStyleShowcase.method(:canonical))

    tags_opt = metadata[:options].find { |opt| opt.keyword == :tags }
    refute_nil tags_opt
    assert_equal ['String[]'], tags_opt.types
    assert_equal '[String[]]', tags_opt.inline_type_text
  end

  def test_extra_positional_comments_are_preserved_as_detail_text
    metadata = @registry.metadata_for(ExtraDocSamples.method(:greet))

    labels = metadata[:positionals].map(&:label)
    assert_equal ['NAME'], labels

    detail_lines = metadata[:detail_lines]
    refute_nil detail_lines
    assert_includes detail_lines, 'EXTRA [Integer] Placeholder not used in implementation'
  end

  def test_extra_option_comments_are_preserved_as_detail_text
    metadata = @registry.metadata_for(ExtraDocSamples::GhostOption.method(:greet))

    assert_empty metadata[:options]

    detail_lines = metadata[:detail_lines]
    refute_nil detail_lines
    assert_includes detail_lines, '--ghost [Boolean] Option not implemented'
  end

  def test_literal_choices_are_parsed
    metadata = @registry.metadata_for(ExtraDocSamples::Choices.method(:select))

    level_doc = metadata[:positionals].first
    assert_equal(%i[info warn], level_doc.allowed_values.map { |entry| entry[:value] })

    accept_opt = metadata[:options].find { |opt| opt.keyword == :accept }
    refute_nil accept_opt
    assert_equal(%i[official linked_content], accept_opt.allowed_values.map { |entry| entry[:value] })
    assert_includes accept_opt.types, 'Boolean'
  end

  def test_inline_option_without_type_defaults_to_string
    metadata = @registry.metadata_for(InlineDocSamples.method(:search))
    option = metadata[:options].find { |opt| opt.keyword == :query }
    refute_nil option
    assert_equal ['String'], option.types
    refute option.inline_type_annotation
  end

  def test_minimal_yard_params_infer_string_types
    metadata = @registry.metadata_for(DocumentationStyleShowcase.method(:yard_min))
    subject_doc = metadata[:positionals_map][:subject]
    refute_nil subject_doc
    assert_equal ['String'], subject_doc.types
    refute_includes subject_doc.types, 'Boolean'
  end

  def test_prefix_option_in_showcase_is_parsed_with_description
    metadata = @registry.metadata_for(DocumentationStyleShowcase.method(:typed))
    prefix_opt = metadata[:options].find { |opt| opt.keyword == :prefix }
    refute_nil prefix_opt
    assert_equal '--prefix', prefix_opt.long
    assert_equal %w[String nil], prefix_opt.types
    assert_equal 'Heading for the entry', prefix_opt.description
    assert_equal '[String, nil]', prefix_opt.inline_type_text
  end

  def test_unknown_type_tokens_are_reported_in_doc_check_mode
    @environment.enable_doc_check!
    @environment.clear_documentation_issues!

    method = DocTypoSamples.method(:toggle)
    @registry.metadata_for(method)

    issues = @environment.documentation_issues
    refute_empty issues
    assert(issues.any? { |issue| issue[:message].include?("Unknown type token 'Booalean'") })
  ensure
    @environment.disable_doc_check!
  end

  def test_unknown_allowed_value_tokens_surface_as_documentation_issues
    @environment.enable_doc_check!
    @environment.clear_documentation_issues!

    method = DocTypoSamples.method(:set_level)
    @registry.metadata_for(method)

    issues = @environment.documentation_issues
    refute_empty issues
    assert(issues.any? { |issue| issue[:message].include?("Unknown allowed value token 'WARNNING'") })
  ensure
    @environment.disable_doc_check!
  end

  def test_return_shorthand_line_documents_the_return_value
    metadata = Rubycli.documentation_registry.metadata_for(ReturnShorthandDocSamples.method(:greet))
    returns = metadata[:returns]

    assert_equal 1, returns.size
    assert_equal ['String'], returns.first.types
    assert_equal 'Rendered greeting', returns.first.description
  end
end
