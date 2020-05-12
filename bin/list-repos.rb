#!/usr/bin/env ruby

# Script to list repositories in the ministryofjustice organisation whose names
# match a regular expression, and output a JSON report of how well they
# do/don't comply with our team-wide standards for how github repositories
# should be configured.

require "bundler/setup"
require "json"
require "net/http"
require "uri"
require "octokit"

libdir = File.join(".", File.dirname(__FILE__), "..", "lib")
require File.join(libdir, "github_graph_ql_client")
require File.join(libdir, "repository_lister")
require File.join(libdir, "repository_report")

############################################################

# TODO: get these from env. vars.
params = {
  organization: "ministryofjustice",
  regexp: Regexp.new("^cloud-platform-*"),
  team: "WebOps",
  github_token: ENV.fetch("GITHUB_TOKEN")
}

repositories = RepositoryLister.new(params)
  .repository_names
  .inject([]) do |arr, repo_name|
    report = RepositoryReport.new(params.merge(repo_name: repo_name)).report
    arr << report
end

puts({
  repositories: repositories,
  updated_at: Time.now
}.to_json)
