module Ghrep
  require 'singleton'

  class RepoSpec
    include Singleton

    attr_accessor :repo_list

    def initialize
      @cache = {}
      @repo_list = []
    end

    def match(spec)
      @cache[spec] ||= build_match(spec)
    end

    private

    def build_match(raw_list)
      return @repo_list.sort if raw_list.to_a.length == 0
      bad_repo_specs = false
      repos = []
      raw_list.to_a.map do |raw_clause|
        raw_clause.split(',')
      end.flatten
        .each do |repo_spec|
        matching_repos = @repo_list.select { |repo_name| repo_name =~ /^#{repo_spec}$/ }
        if matching_repos.length == 0
          puts "Error: repo_spec has no matches: #{repo_spec}\n"
          bad_repo_specs = true
        end
        matching_repos.each { |repo_name| repos << repo_name }
      end
      raise RepoSpecError, 'Invalid repo_spec' if bad_repo_specs
      repos.sort.uniq
    end
  end

  class RepoSpecError < StandardError ; end
end
