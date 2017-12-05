module Ghrep
  require 'json'

  class Repo
    attr_reader :description, :name, :path

    def initialize(github_object: nil, path_prefix: nil, ssh_host: nil)
      @github_object = github_object
      @path_prefix   = path_prefix
      @ssh_host      = ssh_host
      @name          = @github_object['name']
      @description   = @github_object['description']
      @path          = "#{@path_prefix}/#{@name}"
      @state_descriptions = {
        :clean               => 'Clean',
        :not_master          => 'Clean (not master)',
        :not_present         => 'Not Present',
        :unstaged_changes    => 'Unstaged Changes',
        :uncommitted_changes => 'Uncommitted Changes',
      }
    end

    def branches(cached: false, raw: false)
      @branch_cache = git('branch').output unless cached and defined? @branch_cache
      if raw
        @branch_cache
      else
        @branch_cache.map { |branch| branch.sub(/^. /, '').chomp }
      end
    end

    def branches_url
      @github_object['branches_url']
    end

    def is_current_branch?(branch)
      current_branch == branch
    end

    def differs_from_origin?(branch=current_branch)
      if branch != current_branch
        :not_current
      elsif git(%W(diff origin/#{branch} --quiet --exit-code)).exitstatus > 0
        true
      else
        false
      end
    end

    def current_branch(cached: true)
      if is_present?
        if branches(cached: cached, raw: true).grep(/^\* /).empty?
          '*NO BRANCHES*'
        else
          branches(cached: true, raw: true).grep(/^\* /)
            .first
            .sub(/^\* /, '')
            .chomp
        end
      else
        'n/a'
      end
    end

    def git(args, no_path: false, stdout: false)
      GitCommand.new(args: args, path: (no_path ? nil : path), stdout: stdout)
    end

    def is_present?
      File.directory? path
    end

    def state_description_max_length
      @state_descriptions.values.reduce(0) { |a, e| e.length > a ? e.length : a }
    end

    def state_description
      @state_descriptions[state]
    end

    def ssh_url
      if @ssh_host
        @github_object['ssh_url'].sub(/^.*:/, "#{@ssh_host}:")
      else
        @github_object['ssh_url']
      end
    end

    def uncommitted_changes?
      git('status --porcelain').output.reduce(false) { |a, e| e =~ /^[^ ?]/ || a }
    end

    def unstaged_changes?
      git('status --porcelain').output.reduce(false) { |a, e| e =~ /^.[^ ?]/ || a }
    end

    def state
      if !is_present?
        :not_present
      elsif unstaged_changes?
        :unstaged_changes
      elsif uncommitted_changes?
        :uncommitted_changes
      elsif !is_current_branch? 'master'
        :not_master
      else
        :clean
      end
    end

    def to_s
      @name
    end

    def topics
      @github_object['topics']
    end

    def url
      @github_object['url']
    end
  end
end
