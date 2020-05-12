class RepositoryReport < GithubGraphQlClient
  attr_reader :organization, :repo_name, :team

  MASTER = "master"
  ADMIN = "admin"
  PASS = "PASS"
  FAIL = "FAIL"

  def initialize(params)
    @organization = params.fetch(:organization)
    @repo_name = params.fetch(:repo_name)
    @team = params.fetch(:team)
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
      team[:name] == team && team[:permission] == ADMIN
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
