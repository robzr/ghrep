module Ghrep
  require 'singleton'

  class Log
    include Singleton

    def log(log_level=NORMAL, message)
      if log_level == :set_log_level
        @set_log_level = message
      else
        print message if log_level <= (@set_log_level || NORMAL)
      end
    end
  end
end
