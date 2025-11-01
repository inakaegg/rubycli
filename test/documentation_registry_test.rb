# frozen_string_literal: true

require 'test_helper'

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
end

class DocumentationRegistryTest < Minitest::Test
  def setup
    @environment = Rubycli::Environment.new(env: {}, argv: [])
    @registry = Rubycli::DocumentationRegistry.new(environment: @environment)
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
    assert_equal [:greeting, :shout, :punctuation], options.map(&:keyword)

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
    assert_equal ['String', 'nil'], punctuation_opt.types
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

  def test_concise_format_includes_inline_annotations
    method = DocExamples::ConciseSamples.instance_method(:describe)
    metadata = @registry.metadata_for(method)

    labels = metadata[:positionals].map(&:label)
    assert_equal ['SUBJECT', 'COUNT'], labels

    count_doc = metadata[:positionals].last
    assert count_doc.inline_type_annotation
    assert_equal '[Integer]', count_doc.inline_type_text
    assert_equal ['Integer'], count_doc.types
    assert_equal 'Number of repetitions', count_doc.description

    options = metadata[:options]
    assert_equal [:style, :tags], options.map(&:keyword)

    style_opt = options.first
    assert_equal '-s', style_opt.short
    assert_equal '--style', style_opt.long
    assert_equal ['String'], style_opt.types
    assert style_opt.inline_type_annotation
    assert_equal '[String]', style_opt.inline_type_text

    tags_opt = options.last
    assert_equal '--tags', tags_opt.long
    assert_equal ['Array<String>'], tags_opt.types
    assert tags_opt.inline_type_annotation
    assert_equal '[Array<String>]', tags_opt.inline_type_text
    assert_equal 'Comma-separated tags', tags_opt.description
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
    assert_equal ['Boolean', 'Integer'], limit_opt.types
    assert limit_opt.inline_type_annotation
    assert_equal '[Boolean, Integer]', limit_opt.inline_type_text
  end

  def test_incomplete_documentation_uses_fallbacks
    method = DocExamples::IncompleteDocs.instance_method(:fallback)
    metadata = @registry.metadata_for(method)

    labels = metadata[:positionals].map(&:label)
    assert_equal ['NAME', 'ATTEMPTS'], labels

    options = metadata[:options]
    assert_equal [:safe_mode, :tag], options.map(&:keyword)

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
end
