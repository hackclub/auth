require "spec_helper"

# Stub the component hierarchy so we can load Sidebar without Rails/Phlex
module Components; class Base; end; end
module Phlex; module Rails; module Helpers; module LinkTo; end; module CurrentPage; end; end; end; end

# Stub the macros that Sidebar's class body calls
class Components::Base
  def self.register_value_helper(*); end
  def self.register_output_helper(*); end
  def self.include(*); end
end

require_relative "../../app/components/sidebar"

RSpec.describe Components::Sidebar do
  describe "#active_nav_item?" do
    subject { described_class.new(current_path: current_path).send(:active_nav_item?, nav_path) }

    context "root path" do
      let(:nav_path) { "/" }

      context "when on root" do
        let(:current_path) { "/" }
        it { is_expected.to be true }
      end

      context "when on another page" do
        let(:current_path) { "/addresses" }
        it { is_expected.to be false }
      end
    end

    context "verification nav item" do
      let(:nav_path) { "/verifications/new" }

      context "when on the verification landing page" do
        let(:current_path) { "/verifications/new" }
        it { is_expected.to be true }
      end

      context "when on persona flow" do
        let(:current_path) { "/verifications/persona" }
        it { is_expected.to be true }
      end

      context "when on student ID flow" do
        let(:current_path) { "/verifications/student-id" }
        it { is_expected.to be true }
      end

      context "when on verification status" do
        let(:current_path) { "/verifications/status" }
        it { is_expected.to be true }
      end

      context "when on a document step" do
        let(:current_path) { "/verifications/document" }
        it { is_expected.to be true }
      end

      context "when on a different section" do
        let(:current_path) { "/addresses" }
        it { is_expected.to be false }
      end
    end

    context "addresses nav item" do
      let(:nav_path) { "/addresses" }

      context "when on addresses index" do
        let(:current_path) { "/addresses" }
        it { is_expected.to be true }
      end

      context "when on new address" do
        let(:current_path) { "/addresses/new" }
        it { is_expected.to be true }
      end

      context "when on a different section" do
        let(:current_path) { "/security" }
        it { is_expected.to be false }
      end
    end

    context "security nav item" do
      let(:nav_path) { "/security" }

      context "when on security index" do
        let(:current_path) { "/security" }
        it { is_expected.to be true }
      end

      context "when on totp setup" do
        let(:current_path) { "/security/totp" }
        it { is_expected.to be true }
      end

      context "when on a different section" do
        let(:current_path) { "/verifications/new" }
        it { is_expected.to be false }
      end
    end

    context "nested nav paths" do
      let(:nav_path) { "/developer/apps" }

      context "when on the apps index" do
        let(:current_path) { "/developer/apps" }
        it { is_expected.to be true }
      end

      context "when on a specific app" do
        let(:current_path) { "/developer/apps/42" }
        it { is_expected.to be true }
      end

      context "when on a different section" do
        let(:current_path) { "/docs" }
        it { is_expected.to be false }
      end
    end
  end
end
