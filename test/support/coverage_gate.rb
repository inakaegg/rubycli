# frozen_string_literal: true

require 'open3'

module CoverageGate
  CoverageStats = Struct.new(:covered, :total, :uncovered, keyword_init: true)
  Error = Class.new(StandardError)

  module_function

  def changed_lines(diff, path_prefix: 'lib/')
    lines_by_path = Hash.new { |hash, path| hash[path] = [] }
    current_path = nil
    current_new_line = nil

    diff.each_line do |line|
      if line.start_with?('+++ ')
        path = line.delete_prefix('+++ ').strip
        current_path = path == '/dev/null' ? nil : path.delete_prefix('b/')
        current_path = nil unless current_path&.start_with?(path_prefix)
        next
      end

      if (match = line.match(/\A@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
        current_new_line = match[1].to_i
        next
      end

      next unless current_new_line

      case line
      when /\A\+(?!\+\+)/
        lines_by_path[current_path] << current_new_line if current_path
        current_new_line += 1
      when /\A-(?!--)/
        next
      when /\A /
        current_new_line += 1
      end
    end

    lines_by_path.transform_values { |lines| lines.uniq.sort }
  end

  def coverage_stats(changed_lines_by_path, line_hits_by_path)
    covered = 0
    total = 0
    uncovered = []

    changed_lines_by_path.each do |path, line_numbers|
      line_hits = line_hits_by_path[path]
      next unless line_hits

      line_numbers.each do |line_number|
        hits = line_hits[line_number - 1]
        next if hits.nil?

        total += 1
        if hits.positive?
          covered += 1
        else
          uncovered << [path, line_number]
        end
      end
    end

    CoverageStats.new(covered: covered, total: total, uncovered: uncovered)
  end

  def diff_against(base_ref, chdir:)
    merge_base, merge_error, merge_status = Open3.capture3(
      'git', 'merge-base', 'HEAD', base_ref,
      chdir: chdir
    )
    unless merge_status.success?
      raise Error, "cannot resolve coverage base #{base_ref.inspect}: #{merge_error.strip}"
    end

    diff, diff_error, diff_status = Open3.capture3(
      'git', 'diff', '--unified=0', '--no-color', merge_base.strip, '--', 'lib',
      chdir: chdir
    )
    raise Error, "cannot read changed lines: #{diff_error.strip}" unless diff_status.success?

    diff
  end
end
