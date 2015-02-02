require 'rubygems'
require 'optparse'
require 'ostruct'
require 'yaml'
require 'json'
require 'erb'
require 'mailchimp'
require 'httparty'
require 'github_api'
require 'date'
require 'fileutils'
require 'pry'

option = OpenStruct.new
OptionParser.new do |opt|
  opt.on('-f', '--type TYPE', '1 - daily / 2 - 3 days / 3 - weekly') { |o| option.type = o }
end.parse!

## Common variables
template = ERB.new IO.read('template.html')
time_format = '%Y-%m-%d'
today = Time.now.strftime('%b %d')
yesterday = (DateTime.now - 1).strftime('%Y%m%d')
yesterday_ts = (DateTime.now - 1).strftime(time_format)
threedays_ago = (DateTime.now - 3).strftime(time_format)
sevendays_ago = (DateTime.now - 7).strftime(time_format)
TOPNEW_CACHE = "topnew_#{yesterday}_type_#{option.type}.cache"
TOPWATCHED_CACHE = "topwatched_#{yesterday}_type_#{option.type}.cache"

## Read app credentials from a file
credentials = YAML.load_file('credentials.yml')
MAILCHIMP_API_KEY = credentials['mailchimp_api']
MAILCHIMP_DAILY_LIST = credentials['mailchimp_daily_list']
MAILCHIMP_3DAYS_LIST = credentials['mailchimp_3days_list']
MAILCHIMP_WEEKLY_LIST = credentials['mailchimp_weekly_list']
PERSONAL_TOKEN = credentials['github_personal_token']

if option.type == '1'
  dataset = <<-T
  githubarchive:day.events_#{yesterday}
  T
  time_range = "#{today}"
  title = "GitHub Archive: Top new & watched repos - " << time_range
  list = MAILCHIMP_DAILY_LIST
elsif option.type == '2'
  dataset = <<-T
  (TABLE_DATE_RANGE(githubarchive:day.events_,
    TIMESTAMP('#{threedays_ago}'),
    TIMESTAMP('#{yesterday_ts}')
  ))
  T
  time_range = "(#{(DateTime.now - 3).strftime('%b %d')} - #{today})"
  title = "GitHub Archive: Top new & watched repos - " << time_range
  list = MAILCHIMP_3DAYS_LIST
elsif option.type == '3'
  dataset = <<-T
  (TABLE_DATE_RANGE(githubarchive:day.events_,
    TIMESTAMP('#{sevendays_ago}'),
    TIMESTAMP('#{yesterday_ts}')
  ))
  T
  time_range = "(#{(DateTime.now - 7).strftime('%b %d')} - #{today})"
  title = "GitHub Archive: Top new & watched repos - " << time_range
  list = MAILCHIMP_WEEKLY_LIST
end

top_new_repos = <<-SQL
SELECT repo.id, repo.name, type, COUNT( repo.name) as starringCount
FROM (
  SELECT repo.id, repo.name, type
  FROM #{dataset}
  WHERE type = 'WatchEvent' 
)
WHERE repo.id IN (
    SELECT repo.id FROM (
      SELECT repo.id,
        JSON_EXTRACT(payload, '$.ref_type') as ref_type,
      FROM #{dataset}
      WHERE type='CreateEvent'
    )
    WHERE ref_type CONTAINS 'repository'
  )
GROUP BY repo.id, repo.name, type
HAVING starringCount >= 5
ORDER BY starringCount DESC
LIMIT 25;
SQL

top_watched_repos = <<-SQL
SELECT repo.id, repo.name, COUNT(repo.name) as starringCount
FROM #{dataset}
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
  auth = {username: PERSONAL_TOKEN, password: "x-oauth-basic"}
  options = {
    :basic_auth => auth,
    :headers => { 'User-Agent' => 'hnq90', 'Content-Type' => 'application/json', 'Accept' => 'application/json'}
  }
  response = HTTParty.get(url, options)
  JSON.parse(response.body)
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

def send_email(title, html, list)
  mailchimp = Mailchimp::API.new(MAILCHIMP_API_KEY)
  campaign = mailchimp.campaigns.create('regular', {
    :list_id => list,
    :subject => title,
    :from_email => 'huy+gha@huynq.net',
    :from_name => 'GitHub Archive'
   },{
    :html => html.to_s.encode('ascii', 'binary', :invalid => :replace, :undef => :replace, :replace => '')
  })

  mailchimp.campaigns.send campaign['id']
end

def read_cache(file, query)
  @data = nil
  FileUtils::mkdir_p 'cached'
  file = 'cached/' << file
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

topwatched =  read_cache(TOPWATCHED_CACHE, top_watched_repos)
topnew = read_cache(TOPNEW_CACHE, top_new_repos)
output = template.result(binding)
puts "Sending top new & watched: " + send_email(title, output, list).to_s
