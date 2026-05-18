# frozen_string_literal: true

namespace :backend do
  desc "Seed backend with synthetic data for UI testing"
  task seed: :environment do
    abort "nope. not in production." if Rails.env.production?

    require "faker"
    Faker::Config.locale = "en-US"

    puts "seeding backend with synthetic data..."

    ActionMailer::Base.perform_deliveries = false
    bacon = Rails.root.join("lib/tasks/ez_fresh_bacon.jpg")

    attach_bacon = ->(document, count: 1) {
      count.times do |i|
        document.files.attach(
          io: File.open(bacon),
          filename: "#{Faker::File.file_name(ext: 'jpg')}",
          content_type: "image/jpeg",
        )
      end
    }

    # ─── Programs ───────────────────────────────────────────────
    programs = [
      Program.create!(name: "Hack Club YSWS", redirect_uri: "https://ysws.hackclub.com/callback", scopes: "basic_info email name verification_status", trust_level: :hq_official),
      Program.create!(name: "Sprig Console", redirect_uri: "https://sprig.hackclub.com/callback", scopes: "basic_info email name slack_id", trust_level: :hq_official),
      Program.create!(name: Faker::App.name, redirect_uri: "https://#{Faker::Internet.domain_name}/callback", scopes: "openid email name slack_id", trust_level: :community_trusted),
      Program.create!(name: Faker::App.name, redirect_uri: "https://#{Faker::Internet.domain_name}/callback", scopes: "openid profile", trust_level: :community_untrusted)
    ]
    puts "  #{programs.size} programs"

    identities = []
    verifications = []

    # Helper to make an identity
    mk = ->(attrs) {
      defaults = {
        country: "US",
        birthday: Faker::Date.birthday(min_age: 13, max_age: 18),
        phone_number: Faker::PhoneNumber.cell_phone_with_country_code,
        slack_id: "USEED#{SecureRandom.hex(4).upcase}"
      }
      merged = defaults.merge(attrs)
      merged[:legal_first_name] ||= merged[:first_name]
      merged[:legal_last_name] ||= merged[:last_name]
      merged[:primary_email] ||= "#{merged[:first_name].downcase}.#{merged[:last_name].downcase}@synth.hackclub.com"
      Identity.create!(**merged)
    }

    # ─── Verified, happy path ───────────────────────────────────
    8.times do
      i = mk.call(
        first_name: Faker::Name.first_name,
        last_name: Faker::Name.last_name,
        ysws_eligible: true,
        country: %w[US CA GB AU SG].sample,
      )
      doc = Identity::Document.new(identity: i, document_type: :government_id)
      doc.save!(validate: false)
      attach_bacon.call(doc)
      v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
      v.update_columns(status: "approved", approved_at: rand(1..60).days.ago)
      OAuthToken.create!(resource_owner: i, application: programs.sample, scopes: "basic_info email name")
      identities << i
      verifications << v
    end
    puts "  8 verified identities"

    # ─── Verified but ysws ineligible (19+) ─────────────────────
    3.times do
      i = mk.call(
        first_name: Faker::Name.first_name,
        last_name: Faker::Name.last_name,
        birthday: Faker::Date.birthday(min_age: 19, max_age: 25),
        ysws_eligible: false,
      )
      doc = Identity::Document.new(identity: i, document_type: :government_id)
      doc.save!(validate: false)
      attach_bacon.call(doc)
      v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
      v.update_columns(status: "approved", approved_at: rand(1..30).days.ago)
      identities << i
      verifications << v
    end
    puts "  3 verified but ysws ineligible"

    # ─── Pending verifications (the review queue) ───────────────
    pending_countries = %w[US US US IN IN MX BR FR DE JP KR NG KE]
    pending_countries.each do |country|
      i = mk.call(
        first_name: Faker::Name.first_name,
        last_name: Faker::Name.last_name,
        country: country,
      )

      if country == "IN" && rand < 0.5
        # Aadhaar verification
        aadhaar = Identity::AadhaarRecord.create!(
          identity: i,
          raw_json_response: {
            data: {
              name: "#{i.first_name} #{i.last_name}",
              dob: i.birthday.strftime("%d-%m-%Y"),
              gender: %w[M F].sample,
              aadhar_number: "XXXX-XXXX-#{rand(1000..9999)}",
              photo: "",
              "Father Name": Faker::Name.name,
              co: "S/O #{Faker::Name.last_name}",
              address: { house: Faker::Address.building_number, street: Faker::Address.street_name, dist: Faker::Address.city, state: "Karnataka", pincode: Faker::Address.zip_code }
            }
          }.to_json,
          name: "#{i.first_name} #{i.last_name}",
          date_of_birth: i.birthday,
        )
        v = Verification::AadhaarVerification.create!(identity: i, aadhaar_record: aadhaar)
        v.update_columns(status: "pending", pending_at: rand(1..72).hours.ago)
      else
        doc = Identity::Document.new(identity: i, document_type: :government_id)
        doc.save!(validate: false)
        attach_bacon.call(doc)
        v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
        v.update_columns(pending_at: rand(1..72).hours.ago)
      end

      identities << i
      verifications << v
    end
    puts "  #{pending_countries.size} pending verifications"

    # ─── Rejected (retryable) ───────────────────────────────────
    retryable_reasons = %w[poor_quality not_readable wrong_type expired]
    4.times do
      i = mk.call(first_name: Faker::Name.first_name, last_name: Faker::Name.last_name)
      doc = Identity::Document.new(identity: i, document_type: :government_id)
      doc.save!(validate: false)
      attach_bacon.call(doc)
      reason = retryable_reasons.sample
      v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
      v.update_columns(
        status: "rejected", rejection_reason: reason,
        rejection_reason_details: Faker::Lorem.sentence,
        fatal: false, rejected_at: rand(1..14).days.ago,
      )
      identities << i
      verifications << v
    end
    puts "  4 rejected (retryable)"

    # ─── Rejected (fatal) ───────────────────────────────────────
    fatal_reasons = %w[info_mismatch altered duplicate]
    3.times do |n|
      i = mk.call(
        first_name: Faker::Name.first_name,
        last_name: Faker::Name.last_name,
        country: %w[US IN FR].sample,
      )
      doc = Identity::Document.new(identity: i, document_type: :government_id)
      doc.save!(validate: false)
      attach_bacon.call(doc)
      v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
      v.update_columns(
        status: "rejected", rejection_reason: fatal_reasons[n],
        fatal: true, rejected_at: rand(1..14).days.ago,
      )
      identities << i
      verifications << v
    end
    puts "  3 rejected (fatal)"

    # ─── Pending with resemblances (duplicates) ────────────────
    2.times do |n|
      target = identities[n] # match against the first verified identities
      i = mk.call(
        first_name: target.first_name,
        last_name: "#{target.last_name}-#{Faker::Name.suffix}",
        primary_email: "#{target.first_name.downcase}+dup#{n}@synth.hackclub.com",
      )
      doc = Identity::Document.new(identity: i, document_type: :government_id)
      doc.save!(validate: false)
      attach_bacon.call(doc)
      v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
      v.update_columns(pending_at: rand(1..24).hours.ago)

      Identity::Resemblance::NameResemblance.create!(identity: i, past_identity: target)
      Identity::Resemblance::EmailSubaddressResemblance.create!(identity: i, past_identity: target)

      identities << i
      verifications << v
    end
    puts "  2 pending with resemblances"

    # ─── Under 13 — pending with warning ────────────────────────
    i = mk.call(
      first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name,
      birthday: rand(7..12).years.ago.to_date,
    )
    doc = Identity::Document.new(identity: i, document_type: :government_id)
    doc.save!(validate: false)
    attach_bacon.call(doc)
    v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
    v.update_columns(pending_at: 3.hours.ago)
    identities << i
    puts "  1 under-13 pending"

    # ─── Permabanned ────────────────────────────────────────────
    i = mk.call(
      first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name,
      permabanned: true,
    )
    doc = Identity::Document.new(identity: i, document_type: :government_id)
    doc.save!(validate: false)
    attach_bacon.call(doc)
    v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
    v.update_columns(status: "rejected", rejection_reason: "duplicate", fatal: true, rejected_at: 30.days.ago)
    identities << i
    puts "  1 permabanned"

    # ─── Vouched identity ───────────────────────────────────────
    i = mk.call(first_name: Faker::Name.first_name, last_name: Faker::Name.last_name, ysws_eligible: true)
    v = Verification::VouchVerification.new(identity: i, status: "approved")
    v.evidence.attach(io: File.open(bacon), filename: "vouch_evidence.jpg", content_type: "image/jpeg")
    v.save!
    identities << i
    puts "  1 vouched"

    # ─── Transcript (2 files) ───────────────────────────────────
    i = mk.call(first_name: Faker::Name.first_name, last_name: Faker::Name.last_name)
    doc = Identity::Document.new(identity: i, document_type: :transcript)
    doc.save!(validate: false)
    attach_bacon.call(doc, count: 2)
    v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
    v.update_columns(pending_at: 6.hours.ago)
    identities << i
    puts "  1 transcript pending"

    # ─── Ignored verification ───────────────────────────────────
    i = mk.call(first_name: Faker::Name.first_name, last_name: Faker::Name.last_name)
    doc = Identity::Document.new(identity: i, document_type: :government_id)
    doc.save!(validate: false)
    attach_bacon.call(doc)
    v = Verification::DocumentVerification.create!(identity: i, identity_document: doc)
    v.update_columns(status: "approved", approved_at: 10.days.ago, ignored_at: 5.days.ago, ignored_reason: "submitted during testing — not a real identity")
    identities << i
    puts "  1 ignored"

    # ─── Multiple attempts (rejected then re-submitted) ─────────
    i = mk.call(first_name: Faker::Name.first_name, last_name: Faker::Name.last_name)
    doc1 = Identity::Document.new(identity: i, document_type: :government_id)
    doc1.save!(validate: false)
    attach_bacon.call(doc1)
    v1 = Verification::DocumentVerification.create!(identity: i, identity_document: doc1)
    v1.update_columns(status: "rejected", rejection_reason: "poor_quality", rejection_reason_details: "too dark, try again with better lighting", fatal: false, rejected_at: 7.days.ago)
    doc2 = Identity::Document.new(identity: i, document_type: :government_id)
    doc2.save!(validate: false)
    attach_bacon.call(doc2)
    v2 = Verification::DocumentVerification.create!(identity: i, identity_document: doc2)
    v2.update_columns(pending_at: 2.hours.ago)
    identities << i
    puts "  1 retry (rejected + re-submitted)"

    # ─── No verification (brand new signup) ─────────────────────
    3.times do
      i = mk.call(first_name: Faker::Name.first_name, last_name: Faker::Name.last_name, country: %w[US CA GB].sample)
      identities << i
    end
    puts "  3 brand new (no verification)"

    # ─── hq_override / can_hq_officialize ───────────────────────
    i = mk.call(first_name: Faker::Name.first_name, last_name: Faker::Name.last_name, hq_override: true, ysws_eligible: true, can_hq_officialize: true)
    identities << i
    puts "  1 hq override"

    # ─── Addresses on some identities ───────────────────────────
    addr_count = 0
    identities.sample(6).each do |identity|
      addr = Address.create!(
        identity: identity,
        first_name: identity.first_name,
        last_name: identity.last_name,
        line_1: Faker::Address.street_address,
        line_2: [ nil, Faker::Address.secondary_address ].sample,
        city: Faker::Address.city,
        state: Faker::Address.state_abbr,
        postal_code: Faker::Address.zip_code,
        country: "US",
        phone_number: Faker::PhoneNumber.cell_phone_with_country_code,
      )
      identity.update!(primary_address: addr)
      addr_count += 1
    end
    puts "  #{addr_count} addresses"

    # ─── Developer apps (community) ────────────────────────────
    dev_identity = identities.find { |i| i.ysws_eligible }
    if dev_identity
      2.times do
        Program.create!(
          name: "#{Faker::Hacker.adjective.titleize} #{Faker::Hacker.noun.titleize}",
          redirect_uri: "https://#{Faker::Internet.domain_name}/callback",
          scopes: "openid email name",
          trust_level: :community_untrusted,
          owner_identity: dev_identity,
          active: true,
        )
      end
      puts "  2 community developer apps"
    end

    # ─── HQ Official apps ──────────────────────────────────────
    %w[Arcade Nest Juice Athena Warehouse].each do |name|
      next if Program.exists?(name: name) # skip if already exists
      Program.create!(
        name: name,
        redirect_uri: "https://#{name.downcase}.hackclub.com/callback",
        scopes: "basic_info email name verification_status slack_id",
        trust_level: :hq_official,
        active: true,
      )
    end
    puts "  #{%w[Arcade Nest Juice Athena Warehouse].size} hq official apps"

    # ─── Backend Users ──────────────────────────────────────────
    bu = []

    # Super admin
    bu << Backend::User.create!(identity: identities[0], active: true, super_admin: true, manual_document_verifier: true, can_break_glass: true, all_fields_access: true)

    # MDV
    bu << Backend::User.create!(identity: identities[1], active: true, manual_document_verifier: true, can_break_glass: true)

    # Program manager
    pm = Backend::User.create!(identity: identities[2], active: true, program_manager: true)
    Backend::OrganizerPosition.create!(backend_user: pm, program: programs[0])
    bu << pm

    # Human endorser
    bu << Backend::User.create!(identity: identities[3], active: true, human_endorser: true)

    # Inactive
    bu << Backend::User.create!(identity: identities[4], active: false, manual_document_verifier: true)

    # Orphaned (no identity link)
    bu << Backend::User.create!(username: "legacy_#{Faker::Internet.username(specifier: 5)}", active: true)

    puts "  #{bu.size} backend users"

    # ─── Break Glass Records ────────────────────────────────────
    bg = 0
    Identity::Document.joins(:verification).where(verifications: { status: "approved" }).limit(4).each do |doc|
      BreakGlassRecord.create!(backend_user: bu[0], break_glassable: doc, reason: Faker::Lorem.sentence, accessed_at: rand(1..10).days.ago)
      bg += 1
    end
    puts "  #{bg} break glass records"

    # ─── Activity entries ───────────────────────────────────────
    act = 0
    identities.sample(10).each do |identity|
      identity.create_activity(:update, owner: bu.sample, parameters: { changes: Faker::Lorem.word })
      act += 1
    end
    Verification.limit(8).each do |v|
      key = v.approved? ? :approved : v.rejected? ? :rejected : :create
      v.create_activity(key, owner: bu.sample, recipient: v.identity)
      act += 1
    end
    puts "  #{act} activity log entries"

    puts "\ndone! #{identities.size} identities, log in as: #{identities[0].primary_email} (super admin)"
  end

  desc "Remove all synthetic seed data"
  task unseed: :environment do
    abort "nope. not in production." if Rails.env.production?

    puts "removing synthetic seed data..."

    ids = Identity.where("primary_email LIKE '%@synth.hackclub.com'").pluck(:id)
    bu_ids = Backend::User.where(identity_id: ids).pluck(:id)

    PublicActivity::Activity.where(trackable_type: "Verification", trackable_id: Verification.where(identity_id: ids).pluck(:id)).delete_all
    PublicActivity::Activity.where(trackable_type: "Identity", trackable_id: ids).delete_all
    PublicActivity::Activity.where(owner_type: "Backend::User", owner_id: bu_ids).delete_all
    BreakGlassRecord.where(backend_user_id: bu_ids).delete_all
    Backend::OrganizerPosition.where(backend_user_id: bu_ids).delete_all
    Backend::User.where(identity_id: ids).delete_all
    Backend::User.where("username LIKE 'legacy_%'").delete_all
    OAuthToken.where(resource_owner_id: ids).delete_all
    Identity::Resemblance.where(identity_id: ids).or(Identity::Resemblance.where(past_identity_id: ids)).delete_all
    # Developer apps owned by seed identities
    seed_programs = Program.where(owner_identity_id: ids)
    seed_program_ids = seed_programs.pluck(:id)
    ProgramCollaborator.where(program_id: seed_program_ids).delete_all
    ProgramCollaborator.where(identity_id: ids).delete_all
    OAuthToken.where(application_id: seed_program_ids).delete_all
    seed_programs.delete_all

    # Named seed programs
    %w[YSWS Sprig].each do |name|
      p = Program.find_by("name LIKE ?", "%#{name}%")
      next unless p
      OAuthToken.where(application_id: p.id).delete_all
      Backend::OrganizerPosition.where(program_id: p.id).delete_all
      p.delete
    end

    Verification.where(identity_id: ids).each { |v| v.identity_document&.files&.each(&:purge) rescue nil; v.try(:evidence)&.purge rescue nil }
    Verification.where(identity_id: ids).delete_all
    Identity::AadhaarRecord.where(identity_id: ids).delete_all
    Identity::Document.where(identity_id: ids).delete_all
    Identity.where(id: ids).update_all(primary_address_id: nil)
    Address.where(identity_id: ids).delete_all
    Identity.where(id: ids).delete_all

    puts "done!"
  end
end
