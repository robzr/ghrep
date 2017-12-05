#!/usr/bin/env ruby
#
require 'optparse'
require 'pp'

require_relative '../lib/ghrep/parse_terms.rb'

tactic = nil

parser = OptionParser.new do |opts|
  opts.banner = "test_parser [-s|-S|-T]"
  opts.on('-s', "Search")             { tactic = :search }
  opts.on('-S', "Search and Replace") { tactic = :search_replace }
  opts.on('-T', "Topics")             { tactic = :plus_minus }
end

begin
  parser.parse!
rescue OptionParser::InvalidOption => error
  puts error.message
  puts parser
  exit(-1)
end

unless tactic
  unless tactic = Ghrep::ParseTerms.autodetect(ARGV)
    puts 'Error: Could not autodetect tactic'
    puts parser
    exit(-1)
  end
  print 'Autodetected '
end

puts "Tactic: #{tactic}"

white_list = %w(one two three four five six seven eight nine ten)

begin
  targets = Ghrep::ParseTerms.new(
    input:      ARGV,
    tactic:     tactic,
    white_list: white_list
  )
  targets.each do |name, target|
    case tactic
    when :search
      target.each do |sar|
        puts "Target: #{name} Search: #{sar.search.inspect} Modifier: #{sar.modifier.inspect}"
      end
    when :search_replace
      target.each do |sar|
        puts "Target: #{name} Search: #{sar.search.inspect} Replace: #{sar.replace.inspect} Modifier: #{sar.modifier.inspect}"
      end
    when :plus_minus
      puts "Target: #{name} Topics Plus: #{target.plus.inspect} Topics Minus: #{target.minus.inspect}"
    end
  end
rescue Ghrep::ParseTermsError => error
  puts error.message
  exit(-1)
end
