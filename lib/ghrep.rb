# TODO:
# - Implement updated parser
# - Implement /i search and /g replace modifiers
# - Implement Topics add/subtract functionality
# - Consider adding Slack notifications for pull request submission
# - Consider adding pre-fetch/thread pool layer for blocking loops
#
module Ghrep
  require 'benchmark'
  require 'io/console'
  require 'pp'

  #GHREP#
  require_relative 'ghrep/parse_command_line_args.rb'
  require_relative 'ghrep/git_command.rb'
  require_relative 'ghrep/github.rb'
  require_relative 'ghrep/github_error_message.rb'
  require_relative 'ghrep/log.rb'
  require_relative 'ghrep/parse_command_line_args.rb'
  require_relative 'ghrep/parse_terms.rb'
  require_relative 'ghrep/repo.rb'
  require_relative 'ghrep/repo_spec.rb'
  require_relative 'ghrep/repos.rb'

  # https://tools.ietf.org/html/rfc7231#section-6.1
  GITHUB_ERRORS = {
    401 => 'Unauthorized',
    404 => 'Not Found',
  }

  GIT_COMMAND = 'git'

  # Log levels
  QUIET       = 0
  NORMAL      = 1
  VERBOSE     = 2
  DEBUG       = 3

  def self.get_term_width
    STDOUT.winsize.last
  rescue Errno::EINVAL, Errno::ENOTTY
    240
  end

  def self.log(log_level=NORMAL, message)
    Log.instance().log(log_level, message)
  end

  def log(log_level=NORMAL, message)
    Log.instance().log(log_level, message)
  end
end
