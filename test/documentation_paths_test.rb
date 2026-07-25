# frozen_string_literal: true

require_relative 'test_helper'

# Guards against documentation drifting to files that do not exist: both READMEs
# and the CLI usage text used to reference scripts from other projects.
class DocumentationPathsTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  DOCUMENTS = %w[README.md README.ja.md CHANGELOG.md].freeze
  # Documents that tell readers what to run; the changelog only narrates history.
  INSTRUCTIONAL_DOCUMENTS = %w[README.md README.ja.md].freeze
  TRACKED_PREFIXES = %w[assets examples exe lib test vhs].freeze
  PATH_PATTERN = %r{(?:#{TRACKED_PREFIXES.join('|')})/[\w./-]+}
  FICTIONAL_PREFIX_PATTERN = %r{(?<![\w/])scripts/}

  def test_documents_reference_existing_repository_paths
    DOCUMENTS.each do |document|
      missing = missing_paths(read_document(document))

      assert_empty missing, "#{document} references missing paths: #{missing.join(', ')}"
    end
  end

  def test_cli_usage_references_existing_repository_paths
    missing = missing_paths(Rubycli::CommandLine::USAGE)

    assert_empty missing, "rubycli usage text references missing paths: #{missing.join(', ')}"
  end

  def test_documents_and_usage_avoid_fictional_script_paths
    sources = INSTRUCTIONAL_DOCUMENTS.to_h { |document| [document, read_document(document)] }
    sources['rubycli usage text'] = Rubycli::CommandLine::USAGE

    sources.each do |label, text|
      refute_match(
        FICTIONAL_PREFIX_PATTERN,
        text,
        "#{label} points at a scripts/ path that is not part of this repository; " \
        'use a bundled examples/ file or an obvious placeholder such as path/to/....'
      )
    end
  end

  private

  def read_document(document)
    File.read(File.join(ROOT, document))
  end

  def missing_paths(text)
    text.scan(PATH_PATTERN)
        .map { |path| path.sub(/[^\w]+\z/, '') }
        .reject { |path| path.include?('*') }
        .uniq
        .reject { |path| File.exist?(File.join(ROOT, path)) }
  end
end
