# frozen_string_literal: true

require 'test_helper'
require_relative 'support/coverage_gate'

class CoverageGateTest < Minitest::Test
  def test_changed_lines_extracts_added_and_replaced_new_lines
    diff = <<~DIFF
      diff --git a/lib/example.rb b/lib/example.rb
      --- a/lib/example.rb
      +++ b/lib/example.rb
      @@ -1 +1,2 @@
      -old
      +replacement
      +added
      @@ -5,0 +7 @@
      +tail
    DIFF

    assert_equal(
      { 'lib/example.rb' => [1, 2, 7] },
      CoverageGate.changed_lines(diff)
    )
  end

  def test_changed_lines_ignores_deleted_files_and_non_library_paths
    diff = <<~DIFF
      diff --git a/lib/removed.rb b/lib/removed.rb
      --- a/lib/removed.rb
      +++ /dev/null
      @@ -1 +0,0 @@
      -removed
      diff --git a/README.md b/README.md
      --- a/README.md
      +++ b/README.md
      @@ -1 +1 @@
      -old
      +new
    DIFF

    assert_equal({}, CoverageGate.changed_lines(diff, path_prefix: 'lib/'))
  end

  def test_coverage_stats_count_only_executable_changed_lines
    changed_lines = { 'lib/example.rb' => [1, 2, 3, 4, 8] }
    line_hits = {
      'lib/example.rb' => [nil, 1, 0, 2]
    }

    stats = CoverageGate.coverage_stats(changed_lines, line_hits)

    assert_equal 2, stats.covered
    assert_equal 3, stats.total
    assert_equal [['lib/example.rb', 3]], stats.uncovered
  end

  def test_coverage_stats_treat_unloaded_changed_files_as_uncovered
    changed_lines = { 'lib/unloaded.rb' => [1, 2] }

    stats = CoverageGate.coverage_stats(changed_lines, {})

    assert_equal 0, stats.covered
    assert_equal 2, stats.total
    assert_equal(
      [['lib/unloaded.rb', 1], ['lib/unloaded.rb', 2]],
      stats.uncovered
    )
  end
end
