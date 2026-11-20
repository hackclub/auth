require "rails_helper"

RSpec.describe Calcom::ProcessBookingEventJob do
  let(:starts_at) { 2.days.from_now.change(usec: 0).iso8601 }
  let(:later_starts_at) { 3.days.from_now.change(usec: 0).iso8601 }

  def run(event, kase, booking_uid:, starts_at: nil, no_show: false)
    described_class.perform_now(event: event, case_id: kase.id, booking_uid: booking_uid, starts_at: starts_at, no_show: no_show)
  end

  describe "BOOKING_CREATED" do
    let(:kase) { create(:verification_case, :docs_submitted) }

    it "books the call, logs once and mails once" do
      expect {
        run("BOOKING_CREATED", kase, booking_uid: "bkng_first", starts_at: starts_at)
      }.to have_enqueued_mail(VerificationCaseMailer, :call_scheduled).once

      kase.reload
      expect(kase).to be_call_scheduled
      expect(kase.booking_uid).to eq("bkng_first")
      expect(kase.call_starts_at).to eq(Time.zone.parse(starts_at))
      expect(kase.events.where(key: "call_booked").count).to eq(1)
    end

    it "treats a redelivered BOOKING_CREATED as a duplicate: no second mail, no second event" do
      run("BOOKING_CREATED", kase, booking_uid: "bkng_first", starts_at: starts_at)

      expect {
        run("BOOKING_CREATED", kase, booking_uid: "bkng_first", starts_at: starts_at)
      }.not_to have_enqueued_mail

      kase.reload
      expect(kase).to be_call_scheduled
      expect(kase.events.where(key: "call_booked").count).to eq(1)
      expect(kase.events.where(key: "call_booking_ignored")).not_to exist
    end

    it "updates the booking and mails again only when BOOKING_RESCHEDULED carries a new time" do
      run("BOOKING_CREATED", kase, booking_uid: "bkng_first", starts_at: starts_at)

      expect {
        run("BOOKING_RESCHEDULED", kase, booking_uid: "bkng_first", starts_at: later_starts_at)
      }.to have_enqueued_mail(VerificationCaseMailer, :call_scheduled).once

      kase.reload
      expect(kase).to be_call_scheduled
      expect(kase.call_starts_at).to eq(Time.zone.parse(later_starts_at))
      expect(kase.events.where(key: "call_booked").count).to eq(2)

      # and a retry of that reschedule is quiet
      expect {
        run("BOOKING_RESCHEDULED", kase, booking_uid: "bkng_first", starts_at: later_starts_at)
      }.not_to have_enqueued_mail
      expect(kase.events.where(key: "call_booked").count).to eq(2)
    end

    it "accepts a reschedule that arrives as a brand-new booking uid" do
      run("BOOKING_CREATED", kase, booking_uid: "bkng_first", starts_at: starts_at)

      expect {
        run("BOOKING_RESCHEDULED", kase, booking_uid: "bkng_second", starts_at: later_starts_at)
      }.to have_enqueued_mail(VerificationCaseMailer, :call_scheduled).once

      expect(kase.reload.booking_uid).to eq("bkng_second")
    end
  end

  describe "bookings landing on a case that is not open for booking" do
    # no approved factory trait for cases — a held case that has been decided
    { withdrawn: nil, call_held: nil, link_sent: nil, approved: :call_held }.each do |state, built_from|
      it "leaves a #{state} case untouched, logs an ignored event and sends nothing" do
        kase = create(:verification_case, built_from || state, status: state)
        before = kase.attributes.slice("status", "booking_uid", "call_starts_at")

        expect {
          expect {
            run("BOOKING_RESCHEDULED", kase, booking_uid: "bkng_late", starts_at: later_starts_at)
          }.not_to raise_error
        }.not_to have_enqueued_mail

        kase.reload
        expect(kase.attributes.slice("status", "booking_uid", "call_starts_at")).to eq(before)
        expect(kase.events.where(key: "call_booked")).not_to exist
        ignored = kase.events.find_by(key: "call_booking_ignored")
        expect(ignored.data).to include("event" => "BOOKING_RESCHEDULED", "status" => state.to_s)
      end
    end
  end

  describe "BOOKING_CANCELLED" do
    let(:kase) { create(:verification_case, :call_scheduled) }

    it "releases the booking without mailing" do
      expect {
        run("BOOKING_CANCELLED", kase, booking_uid: kase.booking_uid)
      }.not_to have_enqueued_mail

      kase.reload
      expect(kase).to be_docs_submitted
      expect(kase.booking_uid).to be_nil
      expect(kase.call_starts_at).to be_nil
      expect(kase.events.where(key: "call_cancelled").count).to eq(1)
    end

    it "is idempotent on redelivery" do
      run("BOOKING_CANCELLED", kase, booking_uid: kase.booking_uid)
      run("BOOKING_CANCELLED", kase, booking_uid: "bkng_gone")

      expect(kase.reload).to be_docs_submitted
      expect(kase.events.where(key: "call_cancelled").count).to eq(1)
      expect(kase.events.where(key: "call_booking_ignored")).to exist
    end

    it "ignores a cancellation for a booking other than the one on the case" do
      current_uid = kase.booking_uid

      run("BOOKING_CANCELLED", kase, booking_uid: "bkng_older")

      kase.reload
      expect(kase).to be_call_scheduled
      expect(kase.booking_uid).to eq(current_uid)
      expect(kase.events.find_by(key: "call_booking_ignored").data).to include("reason" => "stale_booking_uid")
    end

    it "does not touch a held or decided case" do
      held = create(:verification_case, :call_held)
      run("BOOKING_CANCELLED", held, booking_uid: held.booking_uid)

      held.reload
      expect(held).to be_call_held
      expect(held.booking_uid).to be_present
      expect(held.events.where(key: "call_cancelled")).not_to exist
    end
  end

  describe "BOOKING_NO_SHOW_UPDATED" do
    let(:kase) { create(:verification_case, :call_scheduled) }

    it "releases the booking when the host marks a no-show" do
      run("BOOKING_NO_SHOW_UPDATED", kase, booking_uid: kase.booking_uid, no_show: true)

      expect(kase.reload).to be_docs_submitted
      expect(kase.booking_uid).to be_nil
      expect(kase.events.where(key: "call_no_show").count).to eq(1)
    end

    it "does nothing at all when a no-show is un-marked" do
      expect {
        run("BOOKING_NO_SHOW_UPDATED", kase, booking_uid: kase.booking_uid, no_show: false)
      }.not_to change { kase.events.count }

      expect(kase.reload).to be_call_scheduled
    end
  end

  it "does nothing for an unknown case" do
    expect {
      described_class.perform_now(event: "BOOKING_CREATED", case_id: 0, booking_uid: "bkng_x", starts_at: starts_at)
    }.not_to raise_error
  end
end
