#!/usr/bin/env ruby
#
# Knows how to remove duplicate entries from various collections.
#
# Copyright 2012 Georgios Gousios <gousiosg@gmail.com>
#
# Redistribution and use in source and binary forms, with or
# without modification, are permitted provided that the following
# conditions are met:
#
#   1. Redistributions of source code must retain the above
#      copyright notice, this list of conditions and the following
#      disclaimer.
#
#   2. Redistributions in binary form must reproduce the above
#      copyright notice, this list of conditions and the following
#      disclaimer in the documentation and/or other materials
#      provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
# USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require 'rubygems'
require 'mongo'
require 'github-analysis'

GH = GithubAnalysis.new

# Unique keys per known collection
per_col = {
    :commits => {
        :unq => "commit.id",
        :col => GH.commits_col,
        :rm  => ""
    },
    :events => {
        :unq => "id",
        :col => GH.events_col,
        :rm  => ""
    }
}

# Read a hierarchical value of the type  "foo.bar.baz"
# from a hierarchial map
def read_value(from, key)
  key.split(/\./).reduce({}) do |acc, x|
    if not acc.nil?
      if acc.empty?
        # Initial run
        acc = from[x]
      else
        if acc.has_key?(x)
          acc = acc[x]
        else
          # Some intermediate key does not exist
          return ""
        end
      end
    else
      # Some intermediate key returned a null value
      # This indicates a malformed entry
      return ""
    end
  end
end

# Print MongoDB remove statements that
# remove all but one entries for each commit.
def remove_duplicates(data, col)
  removed = 0
  data.select { |k, v| v.size > 1 }.each do |k, v|
    v.slice(0..(v.size - 2)).map do |x|
      #print "db.#{name}.remove({_id : ObjectId('#{x}')})\n"
      removed += 1 if delete_by_id col, x
    end
  end
  removed
end

def delete_by_id(col, id)
  begin
    col.remove({'_id' => id})
    true
  rescue Mongo::OperationFailure => e
    puts "Cannot remove record with id #{x} from #{col.name}"
    false
  end
end

which = case ARGV[0]
          when "commits" then :commits
          when "events" then :events
          else puts "Not a known collection name: #{ARGV[0]}\n"
        end

from = case ARGV[1]
         when nil then {}
         else
           t = Time.at(ARGV[1].to_i)
           STDERR.puts "Searching for duplicates after #{t}"
           {'_id' => {'$gte' => BSON::ObjectId.from_time(t)}}
       end

# Various counters to report stats
processed = total_processed = removed = 0

data = Hash.new

# The following code needs to save intermediate results to cope
# with large datasets
per_col[which][:col].find(from, :fields => per_col[which][:unq]).each do |r|
  _id = r["_id"]
  commit = read_value(r, per_col[which][:unq])

  # If entries cannot be parsed, remove them
  if commit.empty?
    puts "Deleting unknown entry #{_id}"
    removed += 1 if delete_by_id per_col[which][:col], _id
  else
    data[commit] = [] if data[commit].nil?
    data[commit] << _id
  end

  processed += 1
  total_processed += 1

  print "\rProcessed #{processed} records"

  # Calculate duplicates, save intermediate result
  if processed > 500000
    puts "\nLoaded #{data.size} values, cleaning"
    removed += remove_duplicates data, per_col[which][:col]
    data = Hash.new
    processed = 0
  end
end

removed += remove_duplicates data, per_col[which][:col]

puts "Processed #{total_processed}, deleted #{removed} duplicates"
