module Ghrep
  require 'json'
  require 'net/http'

  class GitHub
    def initialize(base_url:, user:, token:)
      @user, @token = user, token
      @base_url = base_url
      create_struct_githubresponse
    end

    def get(url)
      uri = URI.parse(fluff_url url)
      request = Net::HTTP::Get.new(uri.request_uri, default_headers)
      request.basic_auth(@user, @token)
      make_github_request(http(uri).request request)
    end

    def get_all_pages(url)
      return [] unless url
      response = get url
      [response] + get_all_pages(response.next_link)
    end

    def post(url: nil, body: nil, form: nil)
      uri = URI.parse(fluff_url url)
      request = Net::HTTP::Post.new(uri.request_uri, default_headers)
      request.basic_auth(@user, @token)
      if body
        request.body = body 
      elsif form
        request.set_form_data form
      end
      make_github_request(http(uri).request request)
    end

    def put(url: nil, body: nil, form: nil)
      uri = URI.parse(fluff_url url)
      request = Net::HTTP::Put.new(uri.request_uri, default_headers)
      request.basic_auth(@user, @token)
      if body
        request.body = body 
      elsif form
        request.set_form_data form
      end
      make_github_request(http(uri).request request)
    end

    private

    def make_github_request(request, tries = 0)
      Struct::GitHubResponse.new(request)
    rescue GitHubError => exc
      is_a_retry_code = GITHUB_RETRY_CODES.reduce(false) { |a, i| a || i === exc.message }
      if is_a_retry_code and (tries += 1) <= GITHUB_RETRY_MAX_COUNT
        sleep GITHUB_RETRY_DELAY
        warn "Received GitHub result code #{exc.message}, retrying..."
        retry
      else
        raise
      end
    end

    def create_struct_githubresponse
      Struct.new('GitHubResponse', :response) do
        def initialize(*args)
          super
          unless [200, 201].include? code
            raise GitHubError, code, prepend_details_to_backtrace
          end
        end

        def code
          response.code.to_i
        end

        def content
          JSON.parse(response.body)
        rescue JSON::ParserError
          response.body
        end

        def links
          response['link'].to_s.split(/,\s*/).map do |link|
            url, rel = /<([^>]*)>;\s*rel="(.*)"/.match(link)[1, 2]
            [rel.to_sym, url]
          end.flatten
        end

        def next_link
          Hash[*links][:next]
        end

        private

        def prepend_details_to_backtrace
          bt = []
          if content.is_a?(Hash)
            bt << "Message: #{content['message']}" if content.key?('message')
            bt += content['errors'].to_a.map do |error|
                    if error['code'] == 'custom'            
                      "Resource => #{error['resource']} Message => #{error['message']}"
                    elsif error['code'] == 'invalid' and error['field'] == 'head'
                      'Branch not pushed, or was already deleted.'
                    else
                      "Unknown: #{error.inspect}"
                    end
                  end
          end
          bt + Kernel.caller
        end
      end
    end

    def default_headers
      { 
        'Accept': 'application/vnd.github.mercy-preview+json',
        'Content-Type': 'text/json'
      }
    end

    # manages a (probably unnecessary) hash of persistent connections
    def http(uri)
      stream = [uri.host, uri.port]
      @http ||= {}
      unless @http.key?(stream) && @http[stream].active?
        @http[stream] = Net::HTTPSession.new(uri.host, uri.port)
        @http[stream].use_ssl = true
        @http[stream].start
      end
      @http[stream]
    end

    def fluff_url(url)
      %r{^/}.match(url) ? "#{@base_url}#{url}" : url
    end
  end

  class GitHubError < StandardError ; end
end
