module Ghrep
  require 'csv'
  require 'digest'
  require 'fileutils'
  require 'set'

  class Repos < Hash
    def initialize(options)
      @options = options
      @github = GitHub.new(base_url: @options[:base_url],
                           user:     @options[:github_user],
                           token:    @options[:github_token])
      define_struct_output_format
      populate!
    end
  
    def clone!
      effective_repos.each do |repo|
        if repo.state != :not_present and @options[:force]
          log "#{repo.name} -> Destroying local copy\n"
          FileUtils.rm_rf repo.path
        end
        if repo.state == :not_present
          log "#{repo.name} -> "
          repo.git(['clone', repo.ssh_url, repo.path], no_path: true)
        else
          log "#{repo.name} -> Skipping existing repo\n"
        end
      end
    end
    
    def commit!
      effective_repos.each do |repo|
        if repo.current_branch == 'master'
          log VERBOSE, "#{repo} - Skipping repo - branch is master\n"
        elsif repo.uncommitted_changes?
          if @options[:message]
            log "#{repo} -> Committing changes..."
            repo.git ['commit', '-m', @options[:message]]
            log "\n"
          else
            log "#{repo} -> Committing changes...\n"
            repo.git('commit', stdout: true)
          end
        elsif repo.unstaged_changes?
          log "Unstaged changes but no staged changes to commit in #{repo}\n"
        else
          log VERBOSE, "No changes changes in #{repo}\n"
        end
      end
    end
  
    def diff!
      effective_repos.select { |repo| repo.is_present? }.each do |repo|
        log VERBOSE, "#{repo} - Calculating diff\n"
        repo.git(['diff', '-U0', '--word-diff'], stdout: true)
      end
    end
  
    def list!
      output = Struct::OutputFormat.new(@options[:csv], list_fields, @options[:output_width])
  
      log QUIET, output.header
  
      effective_repos.each do |repo|
        log QUIET, output.line(
          repo.name,
          repo.current_branch,
          repo.state_description,
          repo.description,
        )
      end
    end
  
    def pull_request!
      effective_repos.select do |repo|
        repo.state == :not_master and repo.current_branch == op_branch
      end.each do |repo|
        begin
          log "Processing PR for #{repo}..."
          response = github_create_pull_request repo
          log "Success - #{response.content['html_url']}\n"
        rescue GitHubError => mesg
          if mesg.message == '422'
            puts "#{mesg.backtrace[1]} - skipping."
          else
            raise
          end
        end
      end
    end
  
    def push!
      effective_repos.each do |repo|
        if repo.current_branch != op_branch
          log VERBOSE, "#{repo} -> Skipping, branch is not #{op_branch}\n"
          next
        end
        log "#{repo} -> Pushing #{op_branch}"
        repo.git ['push', '--set-upstream', 'origin', @options[:branch]]
        log "\n"
      end
    end
  
    def reset_to_master!
      effective_repos.each do |repo|
        log "#{repo} -> resetting..."
        repo.git(['checkout', 'master', '-q']) if repo.current_branch != 'master'
        repo.branches.grep_v('master').each do |branch|
          log "deleting branch #{branch}..."
          repo.git ['branch', '-D', branch]
        end
        repo.git ['reset', '--hard']
        repo.git ['clean', '-fxd']
        log "\n"
      end
    end
  
    def search!
      output = Struct::OutputFormat.new(
        @options[:csv],
        {
          repo_name: {
            min: 9,
            max: keys.reduce(0) { |a, e| e.length > a ? e.length : a },
          },
          file:      { min: 12, max:  30 },
          line:      { min:  4, max:   7, format: '%%%<actual>d.%<actual>ds' },
          context:   { min: 10, max: 100 },
        },
        @options[:output_width]
      )
      log QUIET, output.header
  
      targets = ParseTerms.new(
        input:      @options[:remaining_args],
        tactic:     :search,
        white_list: keys.sort,
      )
      old_pwd = Dir.pwd
      Dir.chdir @options[:repo_dir]
      targets.each do |repo_name, searches|
        command = search_command(repo_name,
                                 self[repo_name].path,
                                 searches.map { |e| e.search },
                                 searches.map { |e| e.modifier })
        log VERBOSE, "Running command: #{command}\n"
        log VERBOSE, "#{repo_name} -> searching...\n"
        IO.popen({ 'LC_ALL' => 'C' }, command) do |io|
          while line = io.gets
            repo_file, line, string = line.chomp.split(/[\000:]/, 3)
            repo, file = repo_file.sub(@options[:repo_dir], '').split('/', 3)[1,2]
            log QUIET, output.line(repo, file, line, string)
          end
          io.close
        end
      end
      Dir.chdir(old_pwd)
    end
  
    def search_and_replace!
      targets = ParseTerms.new(
        input:      @options[:remaining_args],
        tactic:     :search_replace,
        white_list: keys.sort,
      )
      old_pwd = Dir.pwd
      Dir.chdir @options[:repo_dir]
      targets.each do |repo_name, searches|
        command = sar_command(repo_name, self[repo_name].path, searches)
        log VERBOSE, "Running command: #{command}\n"
        log "#{repo_name} -> searching..."
        original_branch = self[repo_name].current_branch
        self[repo_name].git ['checkout', '-B', op_branch, '-q']
        md5_before = Digest::MD5.digest(self[repo_name].git(['diff', '--shortstat']).output.join)
        system({ 'LC_ALL' => 'C' }, command)
        md5_after = Digest::MD5.digest(self[repo_name].git(['diff', '--shortstat']).output.join)
        if md5_before == md5_after
          log "no changes\n"
          self[repo_name].git ['checkout', '-B', original_branch, '-q']
        else
          log self[repo_name].git(['diff', '--shortstat']).output.first
        end
      end
      Dir.chdir(old_pwd)
    end
  
    def stage!
      effective_repos.each do |repo|
        if repo.current_branch == 'master'
          log VERBOSE, "#{repo} -> Skipping, branch is master\n"
        elsif repo.state == :unstaged_changes
          log "#{repo} -> Staging changes..."
          repo.git ['add', '-A']
          log "\n"
        end
      end
    end
  
    def topics!
      targets = ParseTerms.new(input:      @options[:remaining_args],
                               tactic:     :plus_minus,
                               white_list: keys.sort)
      topics = {}
      targets.each do |target|
        repo_name, plus_minus = target.first, target.last
        topic_set = self[repo_name].topics.to_set + plus_minus.plus - plus_minus.minus
        topics[repo_name] = topic_set.to_a
        topic_plus = (topic_set - self[repo_name].topics.to_set).to_a
        topic_minus = (self[repo_name].topics.to_set - topic_set).to_a
        if [topic_plus.length, topic_minus.length].max > 0
          log "Updating topics on #{repo_name} (%s)..." % [
            (topic_plus.map { |e| "+#{e}" } + topic_minus.map { |e| "-#{e}" }).join(',')
          ]
          begin
            response = github_update_topics self[repo_name], topic_set.to_a
            log "Updated.\n"
          rescue GitHubError => mesg
            if mesg.message == '422'
              puts "#{mesg.backtrace[1]} - skipping."
              topics[repo_name] = self[repo_name].topics
            else
              raise
            end
          end
        end
      end

      output = Struct::OutputFormat.new(
        @options[:csv],
        {
          repo_name: {
            min: 9,
            max: targets.keys.reduce(0) { |a, e| e.length > a ? e.length : a },
          },
          topics: {
            min: 10,
            max: topics.values.reduce(0) { |a, e| e.join(',').length > a ? e.join(',').length : a },
          },
        },
        @options[:output_width]
      )
      log QUIET, output.header

      targets.each do |target|
        repo_name, plus_minus = target.first, target.last
        log QUIET, output.line(repo_name, topics[repo_name].join(','))
      end
    end
  
    def update!
      effective_repos.each do |repo|
        log "#{repo} -> "
        unless [:clean, :not_master].include? repo.state
          log "Skipping (#{repo.state_description})...\n"
          next
        end
        log "updating..."
        repo.git 'remote update origin --prune >/dev/null 2>/dev/null'
        log "resetting..."
        repo.git %w(reset --hard --quiet)
        log "\n"
      end
    end
  
    def update_old!
      effective_repos.each do |repo|
        if repo.state == :not_present
          log "#{repo} -> Skipping missing repo..."
        else
          log "#{repo} -> "
          ['master', @options[:branch]].each do |branch|
            next unless remote_branches_of(repo).key? branch
            unless repo.current_branch == branch
              repo.git ['checkout', '-B', branch, '-q']
            end
            log "Pulling #{branch}..."
            pp %W(pull origin --quiet --rebase --stat +#{branch}:#{branch})
            repo.git %W(pull origin --quiet --rebase --stat +#{branch}:#{branch})
          end
        end
        if repo.current_branch == @options[:branch] and remote_branches_of(repo).key? 'master'
          old_pwd = Dir.pwd
          Dir.chdir(repo.path)
          log "Rebasing..."
          repo.git %w(rebase origin/master)
          Dir.chdir(old_pwd)
        end
        log "\n"
      end
    end
  
    private
  
    def define_struct_output_format
      Struct.new('OutputFormat', :csv, :fields, :width) do
        def field_names
          fields.keys.map do |field| 
            field.to_s
              .split('_')
              .map(&:capitalize)
              .join(' ')
          end
        end
  
        def header
          if csv
            field_names.to_csv
          else
            [string_format % field_names,
             string_format % sub_header].join
          end
        end
  
        def line(*args)
          if csv
            args.to_csv
          else
            string_format % args
          end
        end
  
        private
  
        def default_field_format
          '%%-%<actual>d.%<actual>ds'
        end
  
        # TODO: apply reduction proportionally to min-max size diff instead of max only
        #   this will bias reduction to more dynamic fields
        def generate_string_format
          fields_min = fields.reduce(0) { |a, e| a + e.last[:min] } + fields.length
          fields_max = fields.reduce(0) { |a, e| a + e.last[:max] } + fields.length
          max_factor = [width.to_f / fields_max, 1].min
          total = fields.values.reduce(0) { |a, size|
            (size[:actual] = [
              size[:min], (size[:max] * max_factor).to_i
            ].max) + a + 1
          }
          rounding_offset = [total - width, 0].max
          fields.values.last[:actual] -= rounding_offset
          fields.values.map do |size|
            sprintf(size[:format] || default_field_format, {
              actual: size[:actual],
              min:    size[:min],
              max:    size[:max],
            })
          end.join(' ') + "\n"
        end
  
        def string_format
          @string_format ||= generate_string_format
        end
  
        def sub_header
          fields.values.map { |field| '-' * field[:actual] }
        end
      end
    end
  
    def effective_repos
      effective_repo_names.map { |repo_name| self[repo_name] }
    end
  
    def effective_repo_names
      RepoSpec.instance().match(@options[:remaining_args])
    end
  
    def github_create_pull_request(repo)
      # https://developer.github.com/v3/pulls/#create-a-pull-request
      @github.post(url:  "#{repo.url}/pulls",
                   body: { 'title': @options[:title], 'body':  @options[:message] || pull_request_message,
                           'head':  @options[:branch],
                           'base':  'master' }.to_json)
    end
  
    def github_update_topics(repo, topics)
      # https://developer.github.com/v3/repos/#replace-all-topics-for-a-repository
      @github.put(url:  "#{repo.url}/topics",
                  body: { 'names': topics }.to_json)
    end

    def list_fields
      fields = {
        repo_name: {
          min: 9,
          max: effective_repo_names.reduce(0) { |a, e| e.length > a ? e.length : a },
        },
        branch: {
          min: 7,
          max: [@options[:branch].length, 'master'.length].max,
        },
        state: {
          min: 10,
          max: values.first.state_description_max_length,
        },
        description: {
          min: 20,
          max: values.reduce(0) { |a, repo| repo.description.to_s.length > a ? repo.description.length : a }, },
      }
    end
  
    def log(log_level = 1, message)
      print message if log_level <= @options[:log_level]
    end
  
    def op_branch
      @options[:branch]
    end
  
    def populate!
      @github.get_all_pages("/repos?type=all&per_page=100")
        .each do |repo_list|
          repo_list.content.each do |repo|
              repo_obj = Repo.new(github_object: repo,
                                  path_prefix:   @options[:repo_dir],
                                  ssh_host:      @options[:ssh_host])
            self[repo_obj.name] = repo_obj
          end
        end
      RepoSpec.instance().repo_list = keys
    end
  
    def pull_request_message
      'This PR was submitted by ghrep, and likely contains the result ' +
      'of a bulk search and replace operation.'
    end
  
    def remote_branches_of(repo)
      @remote_branches ||= {}
      @remote_branches[repo.name] ||= get_remote_branches_of(repo)
    end
  
    def get_remote_branches_of(repo)
      pages = @github.get_all_pages(repo.branches_url.sub('{/branch}', "?per_page=100"))
      pages.reduce({}) do |a, e|
        new_hash = Hash[e.content.map { |b| [b['name'], b['commit']['sha']] }]
        a.merge new_hash
      end
    end
  
    def find_command(repo_path)
      case RUBY_PLATFORM
      when /-darwin\d+$/
        %(find -E '#{repo_path}' -type f -not \\( -regex '.*/(\.git|\.xcodeproj)/.*' -or -regex '.*\\.(#{@options[:exclude].join('|')})$' \\) -print0)
      else
        %(find '#{repo_path}' -regextype posix-extended -type f -not \\( -regex '.*/(\.git|\.xcodeproj)/.*' -or -regex '.*\\.(#{@options[:exclude].join('|')})$' \\) -print0)
      end 
    end
  
    def sar_command(repo_name, repo_path, sar_terms)
      commands = {
        find:  find_command(repo_path),
        xargs: %(xargs -0 -n64 -P#{@options[:threads]}),
        perl:  %(perl -pi -e '#{sar_regex(sar_terms, repo_name)}')
      }
      "#{commands[:find]} \\\n | #{commands[:xargs]} #{commands[:perl]}"
    end
  
    def sar_regex(sar_terms, repo_name)
      sar_terms.map do |term|
        search = @options[:regex] ? term.search : term.search.gsub('.', '\.')
        sar_regex_single(@options[:search_boundary], search, term.replace, term.modifier)
      end.join(',')
    end
  
    def sar_regex_single(boundary, search, replace, modifier)
      ["s/(?<front>#{boundary})#{search}(?<back>#{boundary})/$+{front}#{replace}$+{back}/#{modifier}",
       "s/(?<front>#{boundary})#{search}$/$+{front}#{replace}/#{modifier}",
       "s/^#{search}(?<back>#{boundary})/#{replace}$+{back}/#{modifier}",
       "s/^#{search}$/#{replace}/#{modifier}"].join(',')
    end
  
    def search_command(repo_name, repo_path, search_terms, modifier)
      commands = {
        find:  find_command(repo_path),
        xargs: %(xargs -0),
        egrep: %(egrep --null -nE '#{search_regex(search_terms, repo_name, modifier)}'),
      }
      "#{commands[:find]} \\\n | #{commands[:xargs]} #{commands[:egrep]}"
    end
  
    def search_regex(search_terms, repo_name, modifier)
      search_terms.map do |term|
        search = @options[:regex] ? term : term.gsub('.', '\.')
        search_regex_single(@options[:search_boundary], term, modifier)
      end.join('|')
    end
  
    # TODO: convert from egrep to perl for consistency with sar
    def search_regex_single(boundary, search, modifier)
      ["#{boundary}#{search}#{boundary}",
       "#{boundary}#{search}$",
       "^#{search}#{boundary}",
       "^#{search}$"].join('|')
    end
  end
end
