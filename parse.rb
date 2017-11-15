require 'open-uri'
require 'pdf/reader'
require 'time'
require 'json'

def extract_first_column(table)
  table.split("\n").map {|line| line.match(/\d+\s+([A-Z\s]+)/)}.compact.map {|x| x[1].strip}
end

def extract_second_column(table)
  table.split("\n").map {|line| line.match(/\d+\s+[A-Z\s]+\d+\s+([A-Z\s]+)/)}.compact.map {|x| x[1].strip}
end

def parse_column(column:, paddings:)

  column.map do |line|
    {
      name: line.match(/([A-Z\s]+)[XSN]/)[1].strip,
      was_present: line.length == 'COMPONENTE'.length + paddings[0],
    }
  end
end

def parse_table(table:, paddings:)
  columns = [
    parse_column(column: extract_first_column(table), paddings: paddings[0..1]),
    parse_column(column: extract_second_column(table), paddings: paddings[2..3]),
  ].flatten
end

def extract_votes(text:, type:)
  result = text.downcase.match(/#{type}\sn\.\s?(\d+)/m)
  return 0 if !result
  result = result[1]
  return 0 if !result
  result.to_i
end

def extract_named_votes(text:, type:)
  result = text.downcase.match(/#{type}\sn\.\s?(\d+)/m)
  return [] if !result
  result = result[1]
  return [] if !result
  count = result.to_i
  result = text.downcase.match(/#{type}\sn\.\s?(\d+)\s?\(([a-z,\s]+)?\)/m)
  return [] if !result
  result[2].gsub(' e ', ', ').split(', ').sort
end

def parse(filename)
  puts "Filename: #{filename}"
  reader = PDF::Reader.new(filename)
  text = reader.pages.map(&:text).join

  paddings = text.
    match(/^N\s+COMPONENTE(\s+)P(\s+)A\s+N\s+COMPONENTE(\s+)P(\s+)A.*$/)[1..4].
    map(&:length).
    map {|padding| padding + 1}

  matches = text.match(/DELIBERAZIONE DEL CONSIGLIO COMUNALE\n\n\n\s+Numero (\d+) Del (\d{2}\/\d{2}\/\d{4})\n\nOGGETTO: (.+)\n+\s+Il giorno/m)
  data = {
    number: matches[1],
    date: matches[2],
    subject: matches[3]
  }

  table = text.match(/CONSIGLIERI COMUNALI\n+N\s+COMPONENTE\s+P\s+A\s+N\s+COMPONENTE\s+P\s+A\n(.+)\n+Risultano presenti/m)[1]

  data[:people] = parse_table(table: table, paddings: paddings)
  data[:people].each do |person|
    if person[:name].downcase.include?('commatteo')
      person[:name] = 'commatteo daniele mario'
    end
  end

  data[:votes] = {
    in_favor: extract_votes(text: text, type: "favorevoli"),
    opposed: extract_votes(text: text, type: "contrari"),
    abstained: extract_votes(text: text, type: "astenuti"),
  }

  data[:named_votes] = {
    in_favor: extract_named_votes(text: text, type: "favorevoli"),
    opposed: extract_named_votes(text: text, type: "contrari"),
    abstained: extract_named_votes(text: text, type: "astenuti"),
  }
  already_counted = []
  [:in_favor, :opposed, :abstained].each do |type|
    data[:named_votes][type].map! do |vote_name|
      data[:people].
        map {|person| person[:name].downcase}.
        find do |name|
          name.include?(vote_name)
        end
    end

    if data[:votes][type] > 0 && data[:named_votes][type].any?
      already_counted << data[:named_votes][type]
    end
  end

  if already_counted.any?
    already_counted.flatten!.map! do |vote_name|
      data[:people].
        map {|person| person[:name].downcase}.
        find do |name|
          name.include?(vote_name)
        end
    end
  end
  missing = data[:people].map do |person|
    person[:name].downcase
  end - already_counted

  [:in_favor, :opposed, :abstained].each do |type|
    if data[:votes][type] > 0 && data[:named_votes][type].empty?
      data[:named_votes][type] = missing
    end
  end

  data[:passed] = data[:votes][:in_favor] > data[:votes][:opposed]
  data
end

Dir['pdfs/*.pdf'].each do |source|
  data = parse(source)
  date = Time.parse(data[:date])
  filename = date.strftime("%Y") + "_" + data[:number] + ".json"
  File.write("output/#{filename}", JSON.pretty_generate(data))
end
