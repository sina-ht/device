#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require "google_drive"
require "pit"
require "csv"

class PartSheet

  attr_reader :spreadsheet

  def initialize(spreadsheet)
    @spreadsheet = spreadsheet
  end

  def url
    @spreadsheet.human_url
  end

  def self.open(username, password, title)
    session     = GoogleDrive.login(username, password)
    spreadsheet = session.spreadsheet_by_title(title)
    new(spreadsheet)
  end

  def merge_csv( csv_string )
    csv_keys         = []
    worksheet        = @spreadsheet.worksheets.first
    spreadsheet_rows = worksheet.list.to_hash_array

    def update_row_id( worksheet, row_id, row_data )
      if worksheet.list[ row_id ][ "Used" ] != "1"
        puts "update row[ #{row_id + 2} ] Part: #{ row_data["Parts"]}?"
        puts "  before: Used=#{ worksheet.list[ row_id ][ "Used" ] }"
        puts "  after:  Used=1"
        puts "(Y/n)"
        input = STDIN.gets.chomp
        if input != "n"
          worksheet.list[ row_id ][ "Used" ] = "1"
        end
      end

      row_data.each do |key,value|
        if key && ! key.empty? && ( worksheet.list[ row_id ][ key ] != value )
          puts "updating row[ #{row_id} ][ #{key} ] = #{value}"
          worksheet.list[ row_id ][ key ] = value
        end
      end
    end

    csv = CSV.new( csv_string, {
        headers:        :first_row,
        return_headers: true,
      })
    csv.each do |csv_row|
      if csv_row.header_row?
        # nil terminated
        csv_keys = csv_row.fields
        csv_keys.select! {|key| key && ! key.empty? }

        # update keys if new ones appear
        newlistkeys         = worksheet.list.keys | csv_keys
        if worksheet.list.keys.length != newlistkeys.length
          worksheet.list.keys = newlistkeys
          puts "updated header row"
        end

        next
      end

      found = spreadsheet_rows.index { |r|
        (csv_row.field("Value") == r["Value"]) &&
        (csv_row.field("Parts") == r["Parts"])
      }

      if found != nil
        # update
        puts "found row[ #{found} ]"
        update_row_id( worksheet, found, csv_row )
      else

        found_similar = spreadsheet_rows.index { |r|
          (csv_row.field("Parts") == r["Parts"]) ||
         ((csv_row.field("Device") == r["Device"]) && (csv_row.field("Value") == r["Value"]))
        }

        if found_similar != nil
          found_row = worksheet.list[found_similar]
          puts "update row[ #{found_similar + 2} ] Part: #{ found_row["Parts"]}?"
          puts "  before: Value=#{ found_row["Value"] } Device=#{ found_row["Device"] } Parts=#{ found_row["Parts"] }"
          puts "  after:  Value=#{ csv_row["Value"]   } Device=#{ csv_row["Device"]   } Parts=#{ csv_row["Parts"]   }"
          puts "(Y/n)"
          input = STDIN.gets.chomp
          if input != "n"
            update_row_id( worksheet, found_similar, csv_row )
            next
          end
        end

        new_row = {}
        new_row[ "Used" ] = "1"
        csv_row.each do |key,value|
          new_row[ key ] = value if (key && ! key.empty?)
        end

        puts "insert Part: #{ new_row["Parts"]} ?"
        puts "  Value=#{ new_row["Value"] } Device=#{ new_row["Device"] } Parts=#{ new_row["Parts"] }"
        puts "(Y/n)"
        input = STDIN.gets.chomp
        if input != "n"
          worksheet.list.push( new_row )
          puts "created new row: #{new_row}"
          next
        end
      end
    end

    puts "saving..."
    worksheet.save
    puts "saved!"
  end

end

def main
  if ARGV.size < 2 then
    abort "usage: 1st, File -> Export -> BOM -> List type (values), Output format (CSV) -> Save\nruby #{$0} spreadsheet-title semi-collon-separated-csvfile"
  end
  title               = ARGV[ 0 ]
  semicollon_csv_file = ARGV[ 1 ]

  config = Pit.get( "partlist2googlespreadsheet - #{title}",
    :require => {
      "username" => "your email in google spreadsheet for #{title}",
      "password" => "your password in google spreadsheet for #{title}",
    }
  )
  sheet = PartSheet.open( config["username"], config["password"], title )

  puts "writing spreadsheet at URL: #{sheet.url}"

  csv = IO.read( semicollon_csv_file ).gsub( /\";/, "\"," )

  sheet.merge_csv( csv )
end

main()
