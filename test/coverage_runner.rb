# frozen_string_literal: true

require 'coverage'
require_relative 'support/coverage_gate'

MIN_LINE_COVERAGE = 90.0
MIN_BRANCH_COVERAGE = 70.0
MIN_CHANGED_LINE_COVERAGE = 90.0

Coverage.start(lines: true, branches: true)

require_relative 'test_helper'

def coverage_percentage(covered, total)
  return 100.0 if total.zero?

  covered.fdiv(total) * 100
end

Minitest.after_run do
  library_root = File.expand_path('../lib', __dir__) + File::SEPARATOR
  rows = Coverage.result.filter_map do |path, data|
    next unless path.start_with?(library_root)

    line_hits = Array(data[:lines])
    line_counts = line_hits.compact
    branch_counts = (data[:branches] || {}).values.flat_map(&:values)
    {
      file: path.delete_prefix(library_root),
      line_hits: line_hits,
      covered_lines: line_counts.count(&:positive?),
      total_lines: line_counts.size,
      covered_branches: branch_counts.count(&:positive?),
      total_branches: branch_counts.size
    }
  end.sort_by { |row| row[:file] }

  covered_lines = rows.sum { |row| row[:covered_lines] }
  total_lines = rows.sum { |row| row[:total_lines] }
  covered_branches = rows.sum { |row| row[:covered_branches] }
  total_branches = rows.sum { |row| row[:total_branches] }
  line_coverage = coverage_percentage(covered_lines, total_lines)
  branch_coverage = coverage_percentage(covered_branches, total_branches)
  coverage_base_ref = ENV.fetch('COVERAGE_BASE_REF', 'origin/main')
  changed_stats = nil
  changed_error = nil

  begin
    diff = CoverageGate.diff_against(coverage_base_ref, chdir: File.expand_path('..', __dir__))
    changed_line_numbers = CoverageGate.changed_lines(diff)
    line_hits = rows.to_h { |row| ["lib/#{row[:file]}", row[:line_hits]] }
    changed_stats = CoverageGate.coverage_stats(changed_line_numbers, line_hits)
  rescue CoverageGate::Error => e
    changed_error = e.message
  end

  puts
  puts 'Coverage by file:'
  rows.each do |row|
    file_line_coverage = coverage_percentage(row[:covered_lines], row[:total_lines])
    file_branch_coverage = coverage_percentage(row[:covered_branches], row[:total_branches])
    puts format(
      '  %-45s lines %6.2f%% (%d/%d), branches %6.2f%% (%d/%d)',
      row[:file],
      file_line_coverage,
      row[:covered_lines],
      row[:total_lines],
      file_branch_coverage,
      row[:covered_branches],
      row[:total_branches]
    )
  end

  puts format(
    'Total coverage: lines %.2f%% (%d/%d), branches %.2f%% (%d/%d)',
    line_coverage,
    covered_lines,
    total_lines,
    branch_coverage,
    covered_branches,
    total_branches
  )
  if changed_stats
    changed_line_coverage = coverage_percentage(changed_stats.covered, changed_stats.total)
    puts format(
      'Changed-line coverage against %s: %.2f%% (%d/%d)',
      coverage_base_ref,
      changed_line_coverage,
      changed_stats.covered,
      changed_stats.total
    )
    unless changed_stats.uncovered.empty?
      puts "Uncovered changed lines: #{changed_stats.uncovered.map { |path, line| "#{path}:#{line}" }.join(', ')}"
    end
  else
    puts "Changed-line coverage unavailable: #{changed_error}"
  end

  failures = []
  failures << format('line coverage %.2f%% is below %.2f%%', line_coverage, MIN_LINE_COVERAGE) if line_coverage < MIN_LINE_COVERAGE
  if branch_coverage < MIN_BRANCH_COVERAGE
    failures << format('branch coverage %.2f%% is below %.2f%%', branch_coverage, MIN_BRANCH_COVERAGE)
  end
  if changed_stats
    if changed_line_coverage < MIN_CHANGED_LINE_COVERAGE
      failures << format(
        'changed-line coverage %.2f%% is below %.2f%%',
        changed_line_coverage,
        MIN_CHANGED_LINE_COVERAGE
      )
    end
  else
    failures << "changed-line coverage unavailable: #{changed_error}"
  end

  abort "Coverage gate failed: #{failures.join('; ')}" unless failures.empty?
end

Dir[File.expand_path('*_test.rb', __dir__)].sort.each { |file| require file }
