# frozen_string_literal: true

module Rubycli
  module Documentation
    # Extracts contiguous comment blocks that appear immediately before a method.
    class CommentExtractor
      def initialize
        @file_cache = {}
      end

      def extract(file, line_number)
        return [] unless file && line_number

        lines = cached_lines_for(file)
        index = line_number - 2
        block = []

        while index >= 0
          line = lines[index]
          break unless comment_line?(line)

          block << line
          index -= 1
        end

        block.reverse.map { |line| strip_comment_prefix(line) }
      rescue Errno::ENOENT
        []
      end

      def reset!
        @file_cache.clear
      end

      private

      def cached_lines_for(file)
        @file_cache[file] ||= File.readlines(file, chomp: true)
      end

      def comment_line?(line)
        return false unless line

        line.lstrip.start_with?('#')
      end

      def strip_comment_prefix(line)
        line.lstrip.sub(/^#/, '').lstrip
      end
    end
  end
end
