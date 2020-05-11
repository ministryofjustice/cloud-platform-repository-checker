#!/usr/bin/env ruby

# Script to list repositories in the ministryofjustice organisation

require "bundler/setup"
require "json"
require "net/http"
require "open3"
require "uri"
require "pry-byebug"

GITHUB_API_URL = "https://api.github.com/graphql"
ORGANIZATION = "ministryofjustice"
PAGE_SIZE = 100
REGEXP = /^cloud-platform-*/
MASTER = "master"

class RepositoryReport
  attr_reader :repo_data

  def initialize(repo_data)
    @repo_data = repo_data
  end

  # TODO: additional checks
  #   * has issues enabled
  #   * deleteBranchOnMerge
  #   * mergeCommitAllowed (do we want this on or off?)
  #   * squashMergeAllowed (do we want this on or off?)
  #   * teams with permissions (might need to use v3 API https://github.community/t5/GitHub-API-Development-and/How-to-get-repo-teams-via-GraphQL/m-p/41399#M3722)

  def report
    {
      has_master_branch_protection: has_master_branch_protection?,
      requires_approving_reviews: has_branch_protection_property?("requiresApprovingReviews"),
      requires_code_owner_reviews: has_branch_protection_property?("requiresCodeOwnerReviews"),
      administrators_require_review: has_branch_protection_property?("isAdminEnforced"),
      dismisses_stale_reviews: has_branch_protection_property?("dismissesStaleReviews"),
      requires_strict_status_checks: has_branch_protection_property?("requiresStrictStatusChecks"),
    }
  end

  private

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


def matching_repo_names(organization, regexp)
  list_repos(organization)
    .filter { |repo| repo["name"] =~ regexp }
    .map { |repo| repo["name"] }
end

# TODO:
#   * figure out a way to only fetch cloud-platform-* repos
#   * de-duplicate the code
#   * filter out archived repos
#   * filter out disabled repos
#
def list_repos(organization)
  repos = []
  end_cursor = nil

  data = get_repos(organization, end_cursor)
  repos = repos + data.dig("data", "organization", "repositories", "nodes")
  next_page = data.dig("data", "organization", "repositories", "pageInfo", "hasNextPage")
  end_cursor = data.dig("data", "organization", "repositories", "pageInfo", "endCursor")

  while next_page do
    data = get_repos(organization, end_cursor)
    repos = repos + data.dig("data", "organization", "repositories", "nodes")
    next_page = data.dig("data", "organization", "repositories", "pageInfo", "hasNextPage")
    end_cursor = data.dig("data", "organization", "repositories", "pageInfo", "endCursor")
  end

  repos
end

def get_repos(organization, end_cursor = nil)
  json = run_query(
    body: repositories_query(
      organization: organization,
      end_cursor: end_cursor,
    ),
    token: ENV.fetch("GITHUB_TOKEN")
  )

  JSON.parse(json)
end

def run_query(params)
  body = params.fetch(:body)
  token = params.fetch(:token)

  json = {query: body}.to_json
  headers = {"Authorization" => "bearer #{token}"}

  uri = URI.parse(GITHUB_API_URL)
  resp = Net::HTTP.post(uri, json, headers)

  resp.body
end

def repositories_query(params)
  organization = params.fetch(:organization)
  end_cursor = params.fetch(:end_cursor)

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

def get_repo_settings(owner, repo_name)
  body = repo_settings_query(
    organization: owner,
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
        id
        branchProtectionRules(first: 50) {
          edges {
            node {
              id
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


# pp matching_repo_names(ORGANIZATION, REGEXP)

puts "Bad-------------------------------"
repo_data = get_repo_settings(ORGANIZATION, "testing-repo-settings")
pp repo_data
pp RepositoryReport.new(repo_data).report

puts "Good-------------------------------"
repo_data = get_repo_settings(ORGANIZATION, "cloud-platform-infrastructure")
pp repo_data
pp RepositoryReport.new(repo_data).report
