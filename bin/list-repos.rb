#!/usr/bin/env ruby

# Script to list repositories in the ministryofjustice organisation
# and output a JSON report of how well they do/don't comply with
# our organisation-wide standards for how github repositories should
# be configured.

require "bundler/setup"
require "json"
require "net/http"
require "uri"
require "octokit"
require "pry-byebug"

ORGANIZATION = "ministryofjustice"
REGEXP = /^cloud-platform-*/
TEAM = "WebOps"

class GithubGraphQlClient
  GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"

  private

  def run_query(params)
    body = params.fetch(:body)
    token = params.fetch(:token)

    json = {query: body}.to_json
    headers = {"Authorization" => "bearer #{token}"}

    uri = URI.parse(GITHUB_GRAPHQL_URL)
    resp = Net::HTTP.post(uri, json, headers)

    resp.body
  end
end

class RepositoryLister < GithubGraphQlClient
  attr_reader :organization, :regexp

  PAGE_SIZE = 100

  def initialize(organization, regexp)
    @organization = organization
    @regexp = regexp
  end

  # Returns a list of repository names which match `regexp`
  def repository_names
    list_repos
      .filter { |repo| repo["name"] =~ regexp }
      .map { |repo| repo["name"] }
  end

  private

  # TODO:
  #   * figure out a way to only fetch cloud-platform-* repos
  #   * de-duplicate the code
  #   * filter out archived repos
  #   * filter out disabled repos
  #
  def list_repos
    repos = []
    end_cursor = nil

    data = get_repos(end_cursor)
    repos = repos + data.dig("data", "organization", "repositories", "nodes")
    next_page = data.dig("data", "organization", "repositories", "pageInfo", "hasNextPage")
    end_cursor = data.dig("data", "organization", "repositories", "pageInfo", "endCursor")

    while next_page do
      data = get_repos(end_cursor)
      repos = repos + data.dig("data", "organization", "repositories", "nodes")
      next_page = data.dig("data", "organization", "repositories", "pageInfo", "hasNextPage")
      end_cursor = data.dig("data", "organization", "repositories", "pageInfo", "endCursor")
    end

    repos
  end

  def get_repos(end_cursor = nil)
    json = run_query(
      body: repositories_query(end_cursor),
      token: ENV.fetch("GITHUB_TOKEN")
    )

    JSON.parse(json)
  end

  def repositories_query(end_cursor)
    after = end_cursor.nil? ? "" : %[, after: "#{end_cursor}"]
    %[
    {
      organization(login: "#{organization}") {
        repositories(first: #{PAGE_SIZE} #{after}) {
          nodes {
            id
            name
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
    ]
  end
end

class RepositoryReport < GithubGraphQlClient
  attr_reader :organization, :repo_name

  MASTER = "master"
  ADMIN = "admin"
  PASS = "PASS"
  FAIL = "FAIL"

  def initialize(organization, repo_name)
    @organization = organization
    @repo_name = repo_name
  end

  # TODO: additional checks
  #   * has issues enabled
  #   * deleteBranchOnMerge
  #   * mergeCommitAllowed (do we want this on or off?)
  #   * squashMergeAllowed (do we want this on or off?)

  def report
    {
      organization: organization,
      name: repo_name,
      status: status,
      report: all_checks_result
    }
  end

  private

  def repo_data
    @repo_data ||= fetch_repo_data
  end

  def status
    all_checks_result.values.all? ? PASS : FAIL
  end

  def all_checks_result
    @all_checks_result ||= {
      has_master_branch_protection: has_master_branch_protection?,
      requires_approving_reviews: has_branch_protection_property?("requiresApprovingReviews"),
      requires_code_owner_reviews: has_branch_protection_property?("requiresCodeOwnerReviews"),
      administrators_require_review: has_branch_protection_property?("isAdminEnforced"),
      dismisses_stale_reviews: has_branch_protection_property?("dismissesStaleReviews"),
      requires_strict_status_checks: has_branch_protection_property?("requiresStrictStatusChecks"),
      team_is_admin: is_team_admin?,
    }
  end

  def fetch_repo_data
    body = repo_settings_query(
      organization: organization,
      repo_name: repo_name,
    )

    json = run_query(
      body: body,
      token: ENV.fetch("GITHUB_TOKEN")
    )

    JSON.parse(json)
  end

  def repo_settings_query(params)
    owner = params.fetch(:organization)
    repo_name = params.fetch(:repo_name)

    %[
      {
        repository(owner: "#{owner}", name: "#{repo_name}") {
          name
          owner {
            login
          }
          branchProtectionRules(first: 50) {
            edges {
              node {
                pattern
                requiresApprovingReviews
                requiresCodeOwnerReviews
                isAdminEnforced
                dismissesStaleReviews
                requiresStrictStatusChecks
              }
            }
          }
        }
      }
    ]
  end

  def is_team_admin?
    client = Octokit::Client.new(access_token: ENV.fetch("GITHUB_TOKEN"))

    client.repo_teams([organization, repo_name].join("/")).filter do |team|
      team[:name] == TEAM && team[:permission] == ADMIN
    end.any?
  rescue Octokit::NotFound
    # This happens if our token does not have permission to view repo settings
    false
  end

  def branch_protection_rules
    @rules ||= repo_data.dig("data", "repository", "branchProtectionRules", "edges")
  end

  def has_master_branch_protection?
    requiring_branch_protection_rules do |rules|

      rules
        .filter { |edge| edge.dig("node", "pattern") == MASTER }
        .any?
    end
  end

  def has_branch_protection_property?(property)
    requiring_branch_protection_rules do |rules|
      rules
        .map { |edge| edge.dig("node", property) }
        .all?
    end
  end

  def requiring_branch_protection_rules
    rules = branch_protection_rules
    return false unless rules.any?

    yield rules
  end

end

############################################################

repositories = RepositoryLister.new(ORGANIZATION, REGEXP).repository_names.inject([]) do |arr, repo_name|
  arr << RepositoryReport.new(ORGANIZATION, repo_name).report
end

puts({
  repositories: repositories,
  updated_at: Time.now
}.to_json)
