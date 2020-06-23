describe RepositoryReport do
  let(:params) { {
    organization: "ministryofjustice",
    repo_name: "cloud-platform-infrastructure",
    team: "WebOps",
    github_token: "dummytoken"
  } }

  let(:checks) {
    [
      :has_main_branch_protection,
      :requires_approving_reviews,
      :requires_code_owner_reviews,
      :administrators_require_review,
      :dismisses_stale_reviews,
      :requires_strict_status_checks,
      :team_is_admin,
    ]
  }

  subject(:report) { described_class.new(params) }

  before do
    allow(report).to receive(:fetch_repo_data).and_return(repo_data)
    allow(report).to receive(:is_team_admin?).and_return(true)
  end

  context "when repository is correctly configured" do
    let(:repo_data) { JSON.parse(File.read("spec/fixtures/good-repo.json")) }

    it "passes" do
      result = report.report
      expect(result[:status]).to eq("PASS")
    end

    it "passes checks" do
      checks.each do |check|
        result = report.report[:report]
        expect(result[check]).to be(true)
      end
    end
  end

  context "when repository has no branch protection" do
    let(:repo_data) { JSON.parse(File.read("spec/fixtures/bad-repo-no-branch-protection.json")) }

    before do
      allow(report).to receive(:is_team_admin?).and_return(false)
    end

    it "fails" do
      result = report.report
      expect(result[:status]).to eq("FAIL")
    end

    it "fails checks" do
      checks.each do |check|
        result = report.report[:report]
        expect(result[check]).to be(false)
      end
    end
  end

  context "when default branch is master" do
    let(:repo_data) { JSON.parse(File.read("spec/fixtures/bad-repo-master.json")) }

    it "fails" do
      result = report.report
      expect(result[:status]).to eq("FAIL")
    end
  end
end
