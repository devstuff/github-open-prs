#!/usr/bin/env ruby
# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/CyclomaticComplexity
# rubocop:disable Metrics/LineLength
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/PerceivedComplexity

#
# github-open-prs.rb
#
# <bitbar.title>GitHub - Show Open PRs</bitbar.title>
# <bitbar.version>v1.0</bitbar.version>
# <bitbar.author>John Bates</bitbar.author>
# <bitbar.author.github>devstuff</bitbar.author.github>
# <bitbar.desc>Lists open PRs that @mention you or one of your teams</bitbar.desc>
# <bitbar.image>http://www.hosted-somewhere/pluginimage</bitbar.image>
# <bitbar.dependencies>gems: curb</bitbar.dependencies>
# <bitbar.abouturl>http://github.com/devstuff/</bitbar.abouturl>
#
# A BitBar plugin that generates a list of open Github Pull Requests; the PRs
# must @mention the Github user or one of the teams they're interested in.
#
# Copy or symlink this script into your BitBar plugins folder (this is usually
# ~/.bitbar/Plugins). For BitBar to execute it, its name in the plugins folder
# must end with two dot extensions; the first is the refresh period (e.g. "5m"
# for every 5 minutes), and the second is the script type ("rb" for a Ruby
# script). For this example, the result would be "github-open-prs.5m.rb".
#
# The script relies on a configuration file located in your $HOME folder
# named ".github-open-prs.yaml". The script expects the following layout:
#
#   ---
#   api_host_url: "https://api.github.com"
#   api_token: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#   search_days: 7
#   teams:
#     - OWNER/TEAM_A
#     - OWNER/TEAM_B
#   user_name: MY_GITHUB_USER_NAME
#
# where all of the fields are required:
#
#   api_host_url  Either the GitHub public API URL (https://api.github.com),
#                 or a GitHub Enterprise host URL.
#
#   api_token     GitHub personal access token; generate this for your account
#                 at: https://github.com/settings/tokens
#
#                 The token must have the following permissions:
#
#                 - "repo" - Full control of private repositories (can be
#                   removed if you only access public/open source repos).
#
#                 - "public_repo" - Accessing public repositories (included in
#                   "repo" by default).
#
#                 - "read:org" - Read organization and team memberships.
#
#   search_days   Number of days to search for recently updated PRs.
#
#   teams         Set of GitHub team names.
#
#   username      GitHub user login name for authenticating api_token.
#

require 'bundler/inline'

gemfile(install = false, :quiet => true) do
  source 'https://rubygems.org'

  gem 'curb'
end

require 'curb'
require 'date'
require 'json'
require 'set'
require 'uri'
require 'yaml'

# Shows the open pull requests relavent to the configured user and groups.
class GithubOpenPRs
  EMOJI_INCOMPLETE     = '⏳'  # "hourglass with flowing sand", Unicode: U+23F3, UTF-8: E2 8F B3
  EMOJI_ACTIONREQUIRED = '⚠️' # "warning", Unicode: U+26A0 U+FE0F, UTF-8: E2 9A A0 EF B8 8F
  EMOJI_CANCELLED      = '❌'  # "cross mark", Unicode: U+274C, UTF-8: E2 9D 8C
  EMOJI_TIMEDOUT       = '❌'  # "cross mark", Unicode: U+274C, UTF-8: E2 9D 8C
  EMOJI_FAILED         = '❌'  # "cross mark", Unicode: U+274C, UTF-8: E2 9D 8C
  EMOJI_NEUTRAL        = '◾️' # "black medium small square", Unicode: U+25FE U+FE0F, UTF-8: E2 97 BE EF B8 8F
  EMOJI_SUCCESS        = '✅'  # "check mark", Unicode: U+2705, UTF-8: E2 9C 85
  EMOJI_WIP            = '🚧'  # "construction sign", Unicode: U+1F6A7, UTF-8: F0 9F 9A A7
  EMOJI_ARROW          = ':arrow_forward:' # Converted to an emoji by BitBar
  EMOJI_MERGED         = '☯️'  # "yin yang" (Apple), Unicode: U+262F U+FE0F, UTF-8: E2 98 AF EF B8 8F
  EMOJI_NO_MERGE       = '⛔️'  # "no entry" (Apple), Unicode: U+26D4 U+FE0F, UTF-8: E2 9B 94 EF B8 8F

  @verbose = false

  def self.load_config
    config_path = "#{ENV['HOME']}/.github-open-prs.yaml"
    raise "Missing config file: #{config_path}" unless File.exist?(config_path)

    conf = YAML.safe_load(File.read(config_path))

    @api_host_url = conf['api_host_url']
    raise 'Mising configuration field: api_host_url' unless @api_host_url

    search_days_str = conf['search_days']
    raise 'Mising configuration field: search_days' unless search_days_str

    @search_days = search_days_str.to_i

    @api_token = conf['api_token']
    raise 'Missing configuration field: api_token' unless @api_token

    @user_name = conf['user_name']
    raise 'Missing configuration field: user_name' unless @user_name

    @teams = conf['teams']
    raise 'Missing configuration: teams to check requires at least one' unless @teams.size >= 1

    @iso_updated_since = Date.today.prev_day(@search_days).strftime('%Y-%m-%d')

    @pr_lines = SortedSet.new
  end

  def self.execute(argv)
    @verbose = argv.delete('-v')

    load_config

    subexpressions = []
    subexpressions.push("involves:#{@user_name}")
    @teams.each do |team|
      subexpressions.push("team:#{team}")
    end

    begin
      pull_request_search(subexpressions)
      if @pr_lines.empty?
        puts ':octopus: :white_check_mark:'
        puts '---'
        puts 'No PRs :smile:'
      else
        puts ":octopus: #{@pr_lines.size} PRs!"
        puts '---'
        @pr_lines.each do |line|
          puts line
        end
      end
    rescue StandardError => e
      puts ':octopus: '
      puts '---'
      puts ">> Error: #{e} | color=red font=Arial-Bold"
    end

    # Refresh link.
    puts '---'
    puts "Refresh | href=bitbar://refreshPlugin?name=#{File.basename($PROGRAM_NAME, '.rb')}"
  end

  def self.curl_request(url, content_type)
    c = Curl::Easy.new(url)
    c.follow_location = true
    c.headers['Accept'] = content_type
    c.headers['User-Agent'] = 'github-open-prs/v2'
    c.http_auth_types = :basic
    c.username = @user_name
    c.password = @api_token
    c.perform
    c.body_str
  end

  # Search GitHub for PRs with matching criteria.
  def self.pull_request_search(subexpressions)
    subexpressions.each do |expr|
      # rubocop:disable Lint/UriEscapeUnescape
      encoded_query = URI.encode("is:open is:pr sort:updated-desc updated:>=#{@iso_updated_since} #{expr}")
      # rubocop:enable Lint/UriEscapeUnescape

      search_url = "#{@api_host_url}/search/issues?q=#{encoded_query}"
      STDERR.puts "search_url => #{search_url}" if @verbose

      search_response = curl_request(search_url, 'application/vnd.github.v3+json')
      STDERR.puts "    search_response => #{search_response}" if @verbose

      search_doc = JSON.parse(search_response)
      parse_search_response(search_doc)
    end
  end

  def self.parse_search_response(doc)
    doc['items'].each do |item|
      pr_url = item['pull_request']['url']
      STDERR.puts "  pr_url => #{pr_url}" if @verbose

      pr_response = curl_request(pr_url, 'application/vnd.github.v3+json')
      STDERR.puts "    pr_response => #{pr_response}" if @verbose

      pr_doc = JSON.parse(pr_response)
      parse_pr_response(pr_doc)
    end
  end

  def self.parse_pr_response(doc)
    repo_name = doc['head']['repo']['name']
    pr_number = doc['number']
    title = doc['title']
    user_login = doc['user']['login']
    html_url = doc['html_url']
    labels = doc['labels']
    wip = labels.any? { |label| label['name'] == 'WIP' } || title.start_with?('WIP')
    emojis = wip ? EMOJI_WIP : ''
    is_merged = doc['merged']
    is_mergeable = doc['mergeable']
    # is_rebaseable = doc['rebaseable']

    if is_merged
      emojis += EMOJI_MERGED
    elsif !is_mergeable
      emojis += EMOJI_NO_MERGE

      # mergeable_state; lowercase enums from https://developer.github.com/v4/enum/mergestatestatus/
      # mergeable_state = doc['mergeable_state']
    end

    # https://developer.github.com/v3/checks/suites/
    repo_api_url = doc['head']['repo']['url']
    sha = doc['head']['sha']
    check_suites_url = "#{repo_api_url}/commits/#{sha}/check-suites"
    STDERR.puts "  check_suites_url => #{check_suites_url}" if @verbose

    check_suites_response = curl_request(check_suites_url, 'application/vnd.github.antiope-preview+json')
    STDERR.puts "   check_suites_response => #{check_suites_response}" if @verbose

    check_suites_doc = JSON.parse(check_suites_response)
    emojis += parse_check_suites_response(check_suites_doc)

    @pr_lines.add "#{repo_name} #{emojis} \##{pr_number} #{title} (#{user_login}) | href=#{html_url}"
  end

  def self.parse_check_suites_response(doc)
    result = ''
    doc['check_suites'].each do |item|
      next unless item['latest_check_runs_count'].positive?

      # https://developer.github.com/v4/enum/checkstatusstate/
      #   REQUESTED, QUEUED, IN_PROGRES, COMPLETED
      # (v3 is lowercase)
      status = item['status']
      if status.casecmp('completed').zero?
        # https://developer.github.com/v4/enum/checkconclusionstate/
        #   ACTION_REQUIRED, CANCELLED, FAILURE, NEUTRAL, SUCCESS, TIMED_OUT
        conclusion = item['conclusion']
        result =
          case conclusion.downcase
          when 'action_required'  then EMOJI_ACTIONREQUIRED
          when 'cancelled'        then EMOJI_CANCELLED
          when 'failure'          then EMOJI_FAILED
          when 'neutral'          then EMOJI_NEUTRAL
          when 'success'          then EMOJI_SUCCESS
          when 'timed_out'        then EMOJI_TIMEDOUT
          else                         EMOJI_ARROW
          end
      else
        result = EMOJI_INCOMPLETE
      end
    end

    result
  end
end

GithubOpenPRs.execute(ARGV) if $PROGRAM_NAME == __FILE__

# rubocop:enable Metrics/PerceivedComplexity
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/LineLength
# rubocop:enable Metrics/CyclomaticComplexity
# rubocop:enable Metrics/ClassLength
# rubocop:enable Metrics/AbcSize
