require 'hominid'
require 'json'
require 'erb'
require 'httparty'
require 'rubygems'
require 'date'
require 'pry'

yesterday = (DateTime.now - 1).strftime('%Y%m%d')
template = ERB.new IO.read('template.html')
yesterday_dataset = "githubarchive:day.events_#{yesterday}"

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

def send_email(title, html)
  h = Hominid::API.new(ENV['HOMINID_KEY'])
  c = h.campaign_create('regular', {
    :list_id => ENV['HOMINID_LIST'],
    :subject => title,
    :from_email => 'huy+gha@huynq.net',
    :from_name => 'GitHub Archive'
   },{
    :html => html.to_s.encode('ascii', 'binary', :invalid => :replace, :undef => :replace, :replace => '')
  })

  h.campaign_send_now c
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

today = Time.now.strftime('%b %d')
topwatched = get_repos_info(run_query top_watched_repos)
topnew = get_repos_info(run_query top_new_repos)
output = template.result(binding)

puts "Sending top new & watched: " + send_email("GitHub Archive: Top new & watched repos - #{today}", output).to_s