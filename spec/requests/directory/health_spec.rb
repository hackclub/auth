# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory health page", type: :request do
  let(:admin) do
    create(:identity).tap do |i|
      create(:backend_user, identity: i, directory_services_admin: true)
      i.reload
    end
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def record_run(error: nil, finished_at: 1.hour.ago)
    GoodJob::Job.create!(id: SecureRandom.uuid, active_job_id: SecureRandom.uuid, job_class: "Directory::ValidateJob",
      queue_name: "default", serialized_params: {}, finished_at:, error:)
  end

  it "says never run when the job hasn't run" do
    get directory_health_path
    expect(response.body).to include(I18n.t("directory.health.show.never_run"))
  end

  it "shows the last scheduled run from good_jobs, including a drift failure" do
    record_run(finished_at: 2.days.ago)
    record_run(error: "Directory::ValidateJob::DriftDetected: directory drift detected — closure: 1 missing, 0 extra")

    get directory_health_path

    expect(response.body).to include(I18n.t("directory.health.show.invalid"))
    expect(response.body).to include("closure: 1 missing, 0 extra")
  end

  it "runs a check on demand and shows the result" do
    get directory_health_validate_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("directory.health.checked_just_now"))
    expect(response.body).to include(I18n.t("directory.flash.health_valid"))
  end
end
