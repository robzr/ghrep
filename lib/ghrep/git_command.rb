module Ghrep
  class GitCommand
    attr_reader :output, :exitstatus

    def initialize(args:, path: false, stdout: false)
      @args, @path = args, path
      stdout ? run_via_system : run_via_popen
    end

    private

    def command_line
      if @args.is_a?(Array)
        [GIT_COMMAND, *@args]
      else
        "#{GIT_COMMAND} #{@args}"
      end
    end

    def environment
     {
       'GIT_DIR'       => @path ? "#{@path}/.git" : nil,
       'GIT_WORK_TREE' => @path,
       'LC_ALL'        => 'C',
     }
    end

    def run_via_popen
      IO.popen(environment, command_line) do |io|
        @output = io.readlines
        io.close
        @exitstatus = $?.exitstatus
      end
    end

    def run_via_system
      system(environment, [*command_line].join(' '))
      @exitstatus = $?.exitstatus
    end
  end
end
