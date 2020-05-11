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

def matching_repo_names(organization, regexp)
  list_repos(organization)
    .filter { |repo| repo["name"] =~ regexp }
    .map { |repo| repo["name"] }
end

# TODO: figure out a way to only fetch cloud-platform-* repos
# TODO: de-duplicate the code
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
              pushAllowances(first:50) {
                edges {
                  node {
                    id
                  }
                }
              }
              restrictsPushes
              restrictsReviewDismissals
              requiresApprovingReviews
              requiresCodeOwnerReviews
              requiredApprovingReviewCount
              isAdminEnforced
              dismissesStaleReviews
            }
          }
        }
      }
    }
  ]
end

def report(repo_data)
  {
    has_master_branch_protection: has_master_branch_protection?(repo_data)
  }
end

def has_master_branch_protection?(repo_data)
  branch_protection_rules = repo_data.dig("data", "repository", "branchProtectionRules", "edges")
  return false unless branch_protection_rules.any?

  branch_protection_rules
    .filter { |edge| edge.dig("node", "pattern") == MASTER }
    .any?
end

# pp matching_repo_names(ORGANIZATION, REGEXP)

repo_data = get_repo_settings(ORGANIZATION, "cloud-platform-helm-charts")
# pp repo_data

repo_data = get_repo_settings(ORGANIZATION, "testing-repo-settings")

# pp report(repo_data)
