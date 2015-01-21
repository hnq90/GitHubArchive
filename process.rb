require 'rubygems'
require 'date'
require 'yaml'
require 'big_query'
require 'pry'

## Read app credentials from a file
credentials = YAML.load_file('credentials.yml')

opts = {}
opts['client_id']     = credentials['client_id']
opts['service_email'] = credentials['service_account_email']
opts['key']           = credentials['key_file']
opts['project_id']    = credentials['project_id']
opts['dataset']       = credentials['dataset']

prev_day = (DateTime.now - 1).strftime('%Y%m%d')
bq = BigQuery::Client.new(opts)
result = bq.query("SELECT repo.id, repo.name, COUNT(*) as starringCount FROM #{opts['dataset']}.events_#{prev_day} WHERE type = 'WatchEvent' GROUP BY repo.id, repo.name ORDER BY starringCount DESC LIMIT 50")

## TODO Get more info of each repo
## Ping to mailchimp

print result.to_json















