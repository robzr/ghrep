#
module Ghrep
  require 'singleton'
  require 'optparse'

  class ParseCommandLineArgs
    include Singleton

    def parse(args)
      options = {
        branch:          ENV['GIT_BRANCH'] || 'GHREP/search-and-replace',
        command:         :list,
        csv:             false,
        exclude:         %w(a gz icns ico jar png zip),
        force:           false,
        github_token:    ENV['GITHUB_TOKEN'], 
        github_user:     ENV['GITHUB_USER'], 
        log_level:       NORMAL,
        message:         nil,
        org:             DEFAULT[:org],
        regex:           false,
        repo_dir:        ENV['REPO_DIR'] || './github',
        search_boundary: '[^a-zA-Z0-9.-]',
        ssh_host:        ENV['GITHUB_HOST'],
        threads:         8,
        title:           "[ghrep] #{ENV['GIT_BRANCH'] || 'GitHub Global Search & Replace'}",
        output_width:    Ghrep::get_term_width,
      }

      op = OptionParser.new do |opts|
        opts.banner = 'Usage: ghrep [options] (--<command> [repo_spec|sar_spec|search_spec ...])'
        opts.separator "\nCommands available (default is --list):"
        opts.on('-C', '--clone', 'Clone repos - skips existing local repos by default, overwrites with --force') do
          options[:command] = :clone
        end
        opts.on('--commit', 'Commit staged changes (requires changes to be staged)') do
          options[:command] = :commit
        end
        opts.on('-D', '--diff', 'Display a concise git diff') do
          options[:command] = :diff
        end
        opts.on('-L', '--list', 'List local repos, status, branch and description') do
          options[:command] = :list
        end
        opts.on('--pull-request', 'Submit pull request (requires branch to be pushed)') do
          options[:command] = :pull_request
        end
        opts.on('--push', 'Push commits upstream (requires changes committed)') do
          options[:command] = :push
        end
        opts.on('-R', '--reset', 'Reset repos to origin/master branch') do
          options[:command] = :reset_to_master
        end
        opts.on('-S', '--search', 'Search - requires one or more search_spec - searches current branch') do
          options[:command] = :search
        end
        opts.on('--sar', '--search-and-replace', 'Search and replace - requires one or more sar_spec') do
          options[:command] = :search_and_replace
        end
        opts.on('--stage', 'Stage changes (will not stage in master)') do
          options[:command] = :stage
        end
        opts.on('-T', '--topics', 'View or modify repo topics') do
          options[:command] = :topics
        end
        opts.on('-U', '--update', 'Update repos (pull or fetch/rebase); checks out branch if exists') do
          options[:command] = :update
        end
        opts.separator ''
        opts.separator '    repo_spec is a comma-separated list of repo name and/or regexs used to match repo names.'
        opts.separator '      ex: "legacy-prod,service-.*"'
        opts.separator ''
        opts.separator '    search_spec is [repo_spec,][s]/search[/,s/...] - search term(s) are static or a regex (with --regex)'
        opts.separator '      ex: "s/hostname"'
        opts.separator '      ex: "legacy.*,s/old_hostname,s/other_hostname/i"'
        opts.separator ''
        opts.separator '    sar_spec is [repo_spec,]s/search_string/replace_string/[modifier(s)] - Perl syntax named backrefs can be used.'
        opts.separator '      ex: "service.*,s/old_hostname/new_hostname/gi"'
        opts.separator '      ex: "legacy.*,service-.*,s/old(?<inc>\d\d).domain/new-$+{inc}.domain.name/gi"'
        opts.separator ''
        opts.separator 'Options:'
        opts.on('-b', '--branch=BRANCH', 'Branch operated on (will be created for destructive actions)',
                "(or use GIT_BRANCH env variable; current: #{options[:branch]})") do |arg|
          options[:branch] = arg
        end
        opts.on('--csv', "Use CSV output") do |arg|
          options[:csv] = true
        end
        opts.on('--debug', 'Debug log output') do
          options[:log_level] = DEBUG
        end
        opts.on('-d', '--dir=DIR', "Target directory for repos (or use REPO_DIR env variable; current: #{options[:repo_dir]})") do |arg|
          options[:repo_dir] = arg.sub(/\/*$/, '')
        end
        opts.on('--exclude=EXTENSIONS', "Exclude file extensions (default: #{options[:exclude].join(",")})") do |ext|
          options[:exclude] = ext.split(',')
        end
        opts.on('-f', '--force', 'Action differs based on command') do
          options[:force] = true
        end
        opts.on('--github-host=HOST', 'GitHub SSH Host string (or use GITHUB_HOST env variable) (current: git@github.com)') do |arg|
          options[:ssh_host] = arg
        end
        opts.on('-h', '--help', 'Display this help') do
          puts opts
          exit 1
        end
        opts.on('-m', '--message=MESSAGE', 'Commit message; use with --commit or --pull-request') do |mesg|
          options[:message] = mesg
        end
        opts.on('-q', '--quiet', 'Quiet log output') do
          options[:log_level] = QUIET
        end
        opts.on('-r', '--regex', 'Use regex search strings') do
          options[:regex] = true
        end
        opts.on('--search-boundary=BOUNDARY', "Search boundary (default: #{options[:search_boundary]})") do |arg|
          options[:search_boundary] = arg
        end
        opts.on('-t', '--github-token=TOKEN', 'GitHub Personal Access Token (or use GITHUB_TOKEN env variable)',
               'Obtain a Personal Access Token from GitHub -> Settings -> Developer Settings ') do |arg|
          options[:github_token] = arg
        end
        opts.on('--threads=THREADS', "Max number of threads (default: #{options[:threads]})") do |arg|
          options[:threads] = arg
        end
        opts.on('--title=TITLE', "Pull request title (default: \"#{options[:title]}\")") do |arg|
          options[:title] = arg
        end
        opts.on('-u', '--github-user=USER', 'GitHub user name (or use GITHUB_USER env variable)') do |arg|
          options[:github_user] = arg
        end
        opts.on('-v', '--verbose', 'Verbose log output') do
          options[:log_level] = VERBOSE
        end
        opts.on('--width=COLUMNS', "Format output to this width (does not affect --csv, current: #{options[:output_width]})") do |arg|
          options[:output_width] = arg
        end
        opts.separator ''
        opts.separator '    This tool is designed around a particular git workflow. The set branch (see --branch) is used when available, and created'
        opts.separator '    when destructive operations occur (ie: --search-and-replace), otherwise, master is used. Search (and replace) operations'
        opts.separator '    are regex based, and are constructed with the supplied search (and replace) terms escaped (unless --regex is used), and'
        opts.separator '    boundaried with all permutations of line start, line end and --boundary on both front and back.'
        opts.separator ''
        opts.separator '    Example usage:'
        opts.separator '      ghrep --search --regex "AKIA.{16}" --csv      <- searches all repos AWS keys, output in CSV'
        opts.separator '      ghrep --search --regex "aud.*,c,AKIA.{16}"    <- searches all repos starting with aud or c for AWS keys'
        opts.separator '      ghrep --sar s/old_host/new_host/gi            <- searches and replace across all repos'
        opts.separator '      ghrep --topics                                <- displays topics for all repos'
      end
      
      op.parse!(args)

      Ghrep::log :set_log_level, options[:log_level]

      options[:base_url] = DEFAULT[:base_url] % options[:org]

      if options[:branch] == 'master' and !options[:force]
        Ghrep::log QUIET, "Error: operations not allowed on master branch.\n"
        exit(-1)
      end

      options.merge({ remaining_args: args })
    end      
  end      
end
