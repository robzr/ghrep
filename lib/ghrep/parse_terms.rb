module Ghrep
  class ParseTerms < Hash
    REGEX_SEARCH = %r{^s?/([^/]+)(/i?)?$}
    REGEX_SEARCH_REPLACE = %r{^s?/([^/]+)/(.*)(/[ig]*)$}

    def initialize(
      tactic:,
      delim:      ',',
      input:      [:all],
      white_list: [:any]
    )
      unless [String, Regexp].include? (@delim = delim).class
        raise ArgumentError.new("Invalid delimiter type: #{@delim.class}")
      end
      @errors = false
      @white_list = white_list
      case @tactic = tactic
      when :plus_minus
        Struct.new('PlusMinus', :plus, :minus)
        input.each { |i| parse_plus_minus!(i) }
      when :search, :search_replace
        Struct.new('SearchReplace', :search, :replace, :modifier)
        input.each { |i| parse_search_replace!(i) }
      else
        raise ArgumentError => "Invalid parse tactic :#{@tactic.to_s}"
      end
      raise ParseTermsError.new(@errors.join("\n")) if @errors
      super()
    end

    def self.autodetect(args)
      words = args.join(',').split(',')
      if words.reduce(false) { |a, e| a || /^[\+\-]/.match(e) }
        :plus_minus
      elsif words.reduce(false) { |a, e| a || REGEX_SEARCH.match(e) }
        :search
      elsif words.reduce(false) { |a, e| a || REGEX_SEARCH_REPLACE.match(e) }
        :search_replace
      end
    end

    private

    def log_error(error) (@errors ||= []) << error ; end

    def parse_plus_minus!(input)
      targets, plus, minus = [], [], []
      first = true
      input.split(@delim).each do |word|
        case word
        when /^\+/
          plus << word.sub(/^\+/, '')
        when /^-/
          minus << word.sub(/^-/, '')
        else
          begin
            targets, first = parse_word(targets, word, first)
          rescue ParseTermsError => error
            log_error "Invalid repo or topic string: #{word}"
            next
          end
        end
      end
      targets.uniq.each do |target|
        if key? target
          self[target].plus += plus
          self[target].minus += minus
        else
          self[target] = Struct::PlusMinus.new(plus, minus)
        end
      end
    end

    def parse_search_replace!(input)
      targets, search_replace = [], []
      first = true
      input.split(@delim).each do |word|
        if @tactic == :search && search_matches = word.match(REGEX_SEARCH)
          modifier = search_matches[2] ? search_matches[2].sub(%r{^/}, '') : ''
          search_replace << [search_matches[1], nil, modifier]
        elsif @tactic == :search_replace && search_matches = word.match(REGEX_SEARCH_REPLACE)
          modifier = search_matches[3].sub(%r{^/}, '')
          search_replace << [search_matches[1], search_matches[2], modifier]
        else
          begin
            targets, first = parse_word(targets, word, first)
          rescue ParseTermsError => error
            log_error "Invalid repo or %s string: #{word}" % [@tactic.to_s]
            next
          end
        end
      end
      targets = validate_word(:all) if first
      targets.uniq.each do |target|
        self[target] ||= []
        self[target] += search_replace.map do |sr|
          Struct::SearchReplace.new(*sr)
        end
        self[target].uniq!
      end
    end

    def parse_word(targets, word, first)
      if word =~ /^\^/
        targets = validate_word(:all) if targets.empty? and first
        # TODO: add regexp support
        validate_word(word.sub('^', '')).each { |x| targets.delete x }
      else
        targets += validate_word word
        first = false
      end
      [targets, first]
    end

    def validate_word(word)
      if word == :all
        @white_list.dup
      elsif word =~ /^\^/
        word
      elsif @white_list.include?(word) or @white_list.include?(:any)
        [word]
      elsif (matched = @white_list.select { |i| /^#{word}$/.match i }).length > 0
        matched
      else
        raise ParseTermsError.new
      end
    end
  end

  class ParseTermsError < StandardError ; end
end
