# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeletionPolicy do
  subject { described_class.new(user, Deletion) }

  context "with a user who can process deletions" do
    let(:user) { create(:backend_user, :deletion_processor) }

    it { is_expected.to be_index }
    it { is_expected.to be_show }
    it { is_expected.to be_create }
  end

  context "with a super admin" do
    let(:user) { create(:backend_user, :super_admin) }

    it { is_expected.to be_index }
    it { is_expected.to be_show }
    it { is_expected.to be_create }
  end

  context "with a regular user" do
    let(:user) { create(:backend_user) }

    it { is_expected.not_to be_index }
    it { is_expected.not_to be_show }
    it { is_expected.not_to be_create }
  end
end
