require 'mailchimp'
require 'json'
require 'erb'
require 'httparty'
require 'rubygems'
require 'date'
require 'yaml'
require 'github_api'
require 'pry'

template = ERB.new IO.read('template.html')
yesterday = (DateTime.now - 1).strftime('%Y%m%d')
yesterday_dataset = "githubarchive:day.events_#{yesterday}"
TOPNEW_CACHE = "topnew_#{yesterday}.cache"
TOPWATCHED_CACHE = "topwatched_#{yesterday}.cache"

## Read app credentials from a file
credentials = YAML.load_file('credentials.yml')
MAILCHIMP_API_KEY = credentials['mailchimp_api']
MAILCHIMP_LIST = credentials['mailchimp_list']

top_new_repos = <<-SQL
SELECT repo.id, repo.name, COUNT(repo.name) as starringCount 
FROM #{yesterday_dataset}
WHERE type = 'WatchEvent' 
  AND repo.id IN (
    SELECT repo.id FROM (
      SELECT repo.id, 
        JSON_EXTRACT(payload, '$.ref_type') as ref_type,
      FROM #{yesterday_dataset}
      WHERE type='CreateEvent'
    )
    WHERE ref_type CONTAINS 'repository'
  )
GROUP BY repo.id, repo.name
HAVING starringCount >= 5
ORDER BY starringCount DESC 
LIMIT 25
SQL

top_watched_repos = <<-SQL
SELECT repo.id, repo.name, COUNT(repo.name) as starringCount 
FROM #{yesterday_dataset}
WHERE type = 'WatchEvent' 
GROUP BY repo.id, repo.name
HAVING starringCount >= 10
ORDER BY starringCount DESC 
LIMIT 25
SQL

def run_query(q)
  q = q.gsub(/\/\*.*/,'').gsub(/'/m,'"').strip
  JSON.parse(`$(which bq) -q --format=prettyjson --credential_file ~/.bigquery.v2.token query '#{q}'`)
end

def read_api(url)
  options = { 
    :headers => { 'User-Agent' => 'hnq90', 'Content-Type' => 'application/json', 'Accept' => 'application/json'}
  }
  response = HTTParty.get(url, options)
  return JSON.parse(response.body)
end

def get_repos_info(repo_hashes)
  repos = []
  repo_hashes.each do |repo|
    repo_api_url = "https://api.github.com/repos/#{repo['repo_name']}"
    repo_info = read_api repo_api_url
    repo['name'] = repo_info['name']
    repo['desc'] = repo_info['description']
    repo['url']  = repo_info['html_url']
    repo['lang'] = repo_info['language']
    repo['total_count'] = repo_info['stargazers_count']
    repos.push repo
  end
  repos
end

def send_email(title, html)
  mailchimp = Mailchimp::API.new(MAILCHIMP_API_KEY)
  campaign = mailchimp.campaigns.create('regular', {
    :list_id => MAILCHIMP_LIST,
    :subject => title,
    :from_email => 'huy+gha@huynq.net',
    :from_name => 'GitHub Archive'
   },{
    :html => html.to_s.encode('ascii', 'binary', :invalid => :replace, :undef => :replace, :replace => '')
  })

  mailchimp.send campaign
  mailchimp.campaigns.delete campaign
end

def read_cache(file, query)
  @data = nil
  if File.exists? file
    File.open(file) do |file|
      @data = Marshal.load(file)
    end
  else
    @data = get_repos_info(run_query query)
    File.open(file, 'w') do |file|
      Marshal.dump(@data, file)
    end
  end
  @data
end

today = Time.now.strftime('%b %d')
github = Github.new

topwatched =  read_cache(TOPWATCHED_CACHE, top_watched_repos)
topnew = read_cache(TOPNEW_CACHE, top_new_repos)

output = template.result(binding)

puts "Sending top new & watched: " + send_email("GitHub Archive: Top new & watched repos - #{today}", output).to_s