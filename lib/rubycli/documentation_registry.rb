# frozen_string_literal: true

require_relative 'types'
require_relative 'type_utils'
require_relative 'documentation/comment_extractor'
require_relative 'documentation/metadata_parser'

module Rubycli
  class DocumentationRegistry
    def initialize(environment:)
      @environment = environment
      @metadata_cache = {}
      @comment_extractor = Documentation::CommentExtractor.new
      @parser = Documentation::MetadataParser.new(environment: environment)
    end

    def metadata_for(method_obj)
      return empty_metadata unless method_obj

      location = method_obj.source_location
      return empty_metadata unless location

      cache_key = [location[0], location[1], @environment.doc_check_mode?, @environment.allow_param_comments?]
      return deep_dup(@metadata_cache[cache_key]) if @metadata_cache.key?(cache_key)

      comment_lines = @comment_extractor.extract(location[0], location[1])
      metadata = @parser.parse(comment_lines, method_obj)
      @metadata_cache[cache_key] = metadata
      deep_dup(metadata)
    rescue Errno::ENOENT
      empty_metadata
    end

    def reset!
      @metadata_cache.clear
      @comment_extractor.reset!
      @parser.reset_type_dictionary_cache! if @parser.respond_to?(:reset_type_dictionary_cache!)
    end

    private

    def empty_metadata
      @parser.empty_metadata
    end

    def deep_dup(metadata)
      Marshal.load(Marshal.dump(metadata))
    end
  end
end
