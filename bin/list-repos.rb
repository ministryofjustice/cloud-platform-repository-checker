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
ORGANIZATION = "ministryofjustice"
REGEXP = /^cloud-platform-*/
TEAM = "WebOps"

repositories = RepositoryLister.new(organization: ORGANIZATION, regexp: REGEXP)
  .repository_names
  .inject([]) do |arr, repo_name|
    report = RepositoryReport.new(
      organization: ORGANIZATION,
      team: TEAM,
      repo_name: repo_name
    ).report
    arr << report
end

puts({
  repositories: repositories,
  updated_at: Time.now
}.to_json)
