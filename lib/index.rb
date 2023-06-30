# frozen_string_literal: true

require 'net/http'
require 'json'
require 'time'

class RubocopOffenseException < StandardError
  def initialize(msg = 'Rubocop found offenses')
    super(msg)
  end
end

@GITHUB_SHA = ENV['GITHUB_SHA']
@GITHUB_EVENT_PATH = ENV['GITHUB_EVENT_PATH']
@GITHUB_TOKEN = ENV['GITHUB_TOKEN']
@GITHUB_WORKSPACE = ENV['GITHUB_WORKSPACE']

@RUBOCOP_ARGS = ENV['RUBOCOP_ARGS']
@RUBOCOP_LINT_FILES = ENV['RUBOCOP_LINT_FILES']

@event = JSON.parse(File.read(ENV['GITHUB_EVENT_PATH']))
@repository = @event['repository']
@owner = @repository['owner']['login']
@repo = @repository['name']

@check_name = 'Rubocop'
@rubocop_cmd = "rubocop --format json #{@RUBOCOP_ARGS} #{@RUBOCOP_LINT_FILES}"

@headers = {
  "Content-Type": 'application/json',
  "Accept": 'application/vnd.github.antiope-preview+json',
  "Authorization": "Bearer #{@GITHUB_TOKEN}",
  "User-Agent": 'github-actions-rubocop'
}

def create_check
  body = {
    'name' => @check_name,
    'head_sha' => @GITHUB_SHA,
    'status' => 'in_progress',
    'started_at' => Time.now.iso8601
  }

  http = Net::HTTP.new('api.github.com', 443)
  http.use_ssl = true
  path = "/repos/#{@owner}/#{@repo}/check-runs"

  resp = http.post(path, body.to_json, @headers)

  raise resp.message if resp.code.to_i >= 300

  data = JSON.parse(resp.body)
  data['id']
end

def update_check(id, conclusion, output)
  body = {
    'name' => @check_name,
    'head_sha' => @GITHUB_SHA,
    'status' => 'completed',
    'completed_at' => Time.now.iso8601,
    'conclusion' => conclusion,
    'output' => output
  }

  http = Net::HTTP.new('api.github.com', 443)
  http.use_ssl = true
  path = "/repos/#{@owner}/#{@repo}/check-runs/#{id}"

  resp = http.patch(path, body.to_json, @headers)

  raise resp.message if resp.code.to_i >= 300
end

@annotation_levels = {
  'refactor' => 'failure',
  'convention' => 'failure',
  'warning' => 'warning',
  'error' => 'failure',
  'fatal' => 'failure'
}

def run_rubocop
  annotations = []
  errors = nil

  puts "Running rubocop: #{@rubocop_cmd}"

  Dir.chdir(@GITHUB_WORKSPACE) do
    errors = JSON.parse(`#{@rubocop_cmd}`)
  end
  conclusion = 'success'
  count = 0

  errors['files'].each do |file|
    path = file['path']
    offenses = file['offenses']

    offenses.each do |offense|
      severity = offense['severity']
      message = offense['message']
      location = offense['location']
      annotation_level = @annotation_levels[severity]
      count += 1

      conclusion = 'failure' if annotation_level == 'failure'

      annotations.push(
        'path' => path,
        'start_line' => location['start_line'],
        'end_line' => location['start_line'],
        "annotation_level": annotation_level,
        'message' => message
      )
    end
  end

  output = {
    "title": @check_name,
    "summary": "#{count} offense(s) found",
    'annotations' => annotations
  }

  { 'output' => output, 'conclusion' => conclusion }
end

def run
  # Uncomment for publishing comments on github actions output.
  # id = create_check

  results = run_rubocop
  conclusion = results['conclusion']
  output = results['output']

  # Uncomment for publishing comments on github actions output.
  # update_check(id, conclusion, output)

  # Print offenses
  if conclusion == 'failure'
    puts output[:summary]
    output['annotations'].each do |annotation|
      puts "#{annotation['path']}:L#{annotation['start_line']}-L#{annotation['end_line']}:#{annotation['message']}"
    end
    raise RubocopOffenseException
  end
rescue RubocopOffenseException
  # Uncomment for publishing comments on github actions output.
  # update_check(id, 'failure', nil)
  raise
rescue StandardError
  raise
end

run
