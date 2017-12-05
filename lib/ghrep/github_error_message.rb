module Ghrep
  class GitHubErrorMessage
    attr_reader :code, :message

    def initialize(code: nil, message: nil)
      @code, @message = code, message
    end

    def to_s
      @message
    end
  end
end
