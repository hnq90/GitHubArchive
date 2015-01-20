require 'open-uri'
require 'zlib'
require 'yajl'
require 'pry'
require 'json/ext'

gz = open('http://data.githubarchive.org/2015-01-01-19.json.gz')
js = Zlib::GzipReader.new(gz).read

top_watched = Hash.new
grossing_repos = Hash.new
starred_repo = Hash.new

# name repo | count today starred | language JavaScript
# description
Yajl::Parser.parse(js) do |event|
   if event["payload"]["action"] == "started"
        if starred_repo.has_key?(event["repo"]["name"])
            starred_repo[event["repo"]["name"]][:starred] += 1
        else
            starred_repo[event["repo"]["name"]] = {:name => event["repo"]["name"], :starred => 1, :url => event["repo"]["url"]}
        end    
   end
end

File.open("starred.json", 'a+') { |f| f.write(starred_repo.to_json) }