class RepositoryLister < GithubGraphQlClient
  attr_reader :organization, :regexp

  PAGE_SIZE = 100

  def initialize(params)
    @organization = params.fetch(:organization)
    @regexp = params.fetch(:regexp)
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
