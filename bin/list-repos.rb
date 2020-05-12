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

libdir = File.join(".", File.dirname(__FILE__), "..", "lib")
require File.join(libdir, "github_graph_ql_client")
require File.join(libdir, "repository_lister")
require File.join(libdir, "repository_report")

############################################################

ORGANIZATION = "ministryofjustice"
REGEXP = /^cloud-platform-*/
TEAM = "WebOps"

repositories = RepositoryLister.new(ORGANIZATION, REGEXP)
  .repository_names
  .inject([]) do |arr, repo_name|
    arr << RepositoryReport.new(ORGANIZATION, repo_name).report
end

puts({
  repositories: repositories,
  updated_at: Time.now
}.to_json)
