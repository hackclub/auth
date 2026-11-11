# frozen_string_literal: true

require "rails_helper"

# Random directories, checked against DirectoryNaive (spec/support/directory_naive.rb), a
# brute-force model of what the derived tables, policies, requirement checks, claims and
# revocations should say. Seeded: PROPERTY_SEED=<n> reruns one family of cases, and every
# failure message names the seed that produced it.
module DirectoryAccessProperties
  BASE_SEED = Integer(ENV.fetch("PROPERTY_SEED", "20261110"))
  STATIC_CASES = Integer(ENV.fetch("PROPERTY_STATIC_CASES", "15"))
  MUTATION_CASES = Integer(ENV.fetch("PROPERTY_MUTATION_CASES", "40"))
  PERMISSIONS = %w[view manage_members expose].freeze
  MUTATION_KINDS = %i[remove_person_membership remove_group_edge expire_membership delete_collection delete_person
    remove_requirement renew_membership add_membership].freeze
end

RSpec.describe "directory access properties", type: :model do
  include ActiveJob::TestHelper

  def micros(time) = time && (time.to_r * 1_000_000).round

  def norm(hash) = hash.transform_values { |exp| micros(exp) }

  # builds a random directory through the real models inside one Directory.mutate!
  def build_directory(rng)
    admin = create(:identity)
    db_now = ActiveRecord::Base.connection.select_value("SELECT NOW()")
    future = -> { db_now + rng.rand(1..72).hours }

    people = Array.new(rng.rand(3..8)) { create(:directory_person, created_by: admin) }
    kinds = Array.new(rng.rand(3..8)) { rng.rand < 0.6 ? "group" : "entitlement" }
    kinds[0] = "group"
    kinds[-1] = "entitlement"
    collections = kinds.each_with_index.map do |kind, i|
      create(kind == "group" ? :directory_group : :directory_entitlement, name: "coll-#{i}-#{rng.rand(1_000_000)}")
    end
    groups = collections.select(&:group?)
    entitlements = collections.select(&:entitlement?)
    collections.each { |c| c.update_columns(protected: true) if rng.rand < 0.3 }

    to_lapse = []
    seen = Set.new
    Directory.mutate!(cause: "property-build") do
      # sometimes a long chain first, so deep nesting and MAX_DEPTH get exercised
      if rng.rand < 0.35
        chain = groups.shuffle(random: rng) + entitlements.sample(1, random: rng)
        chain.each_cons(2) do |child, parent|
          next unless child.group? && seen.add?([ parent.id, :group, child.id ])

          Directory::Membership.new(collection: parent, member_group: child, created_by_identity_id: admin.id,
            expires_at: rng.rand < 0.5 ? nil : future.call).save
        end
      end

      # nesting: a group into any other collection
      rng.rand(0..(collections.size * 2)).times do
        parent = collections.sample(random: rng)
        child = groups.sample(random: rng)
        next if parent == child || !seen.add?([ parent.id, :group, child.id ])

        expiry = rng.rand
        m = Directory::Membership.new(collection: parent, member_group: child, created_by_identity_id: admin.id,
          expires_at: expiry < 0.55 ? nil : future.call)
        next unless m.save

        to_lapse << m if expiry > 0.9
      end

      people.each do |person|
        collections.sample(rng.rand(0..3), random: rng).each do |c|
          next unless seen.add?([ c.id, :person, person.id ])

          expiry = rng.rand
          m = Directory::Membership.new(collection: c, member_person: person, created_by_identity_id: admin.id,
            expires_at: expiry < 0.6 ? nil : future.call)
          next unless m.save

          to_lapse << m if expiry > 0.85
        end
      end

      rng.rand(2..8).times do
        # mostly onto groups, so recursion has somewhere to go
        target = rng.rand < 0.75 ? groups.sample(random: rng) : collections.sample(random: rng)
        Directory::Grant.new(grantee_group: groups.sample(random: rng), target_collection: target,
          permission: DirectoryAccessProperties::PERMISSIONS.sample(random: rng), recursive: target.group? && rng.rand < 0.7).save
      end

      # lapsed before this rebuild: the raw row says so, the derived tables never saw it
      to_lapse.each { |m| m.update_columns(expires_at: db_now - rng.rand(1..48).hours) }
    end

    apps = Array.new(rng.rand(1..3)) do |i|
      create(:program, :with_groups, name: "papp-#{rng.rand(1_000_000)}-#{i}")
    end
    # half the time the first app is the awkward one: claim-only (no requirements) and
    # downgraded, so whether a revocation is right hinges on who holds a groups token
    awkward = rng.rand < 0.5 ? apps.first : nil
    apps.each do |app|
      unless app == awkward
        entitlements.sample(rng.rand(0..2), random: rng).each { |e| Directory::AppRequirement.create!(app:, entitlement: e) }
      end
      entitlements.sample(rng.rand(app == awkward ? 1..2 : 0..2), random: rng).each do |e|
        Directory::Exposure.create!(app:, entitlement: e, claim_name: "c#{e.id}")
      end
      # downgraded after wiring: only tokens already issued with groups still carry the claim
      app.update_columns(scopes: "basic_info email name") if app == awkward || rng.rand < 0.3
    end

    tokens = []
    people.each do |person|
      apps.each do |app|
        next unless rng.rand < 0.85

        scopes = rng.rand < 0.5 ? "basic_info groups" : "basic_info"
        tokens << create(:oauth_token, resource_owner: person.identity, application: app, scopes:)
      end
    end

    { admin:, people:, collections:, groups:, entitlements:, apps: apps.map(&:reload), tokens: }
  end

  def check(failures, seed, label, expected, actual)
    return if expected == actual

    missing = expected.to_a - actual.to_a
    extra = actual.to_a - expected.to_a
    failures << "seed #{seed} #{label}: missing #{missing.first(5).inspect} extra #{extra.first(5).inspect}"
  end

  def check_derived_tables(failures, seed, naive)
    closure = Directory::Closure.pluck(:ancestor_id, :descendant_id, :depth).to_h { |a, d, depth| [ [ a, d ], depth ] }
    check(failures, seed, "closure", naive.closure.transform_values(&:first), closure)

    em = Directory::EffectiveMembership.unscoped.pluck(:collection_id, :person_id, :expires_at).to_h { |c, p, e| [ [ c, p ], micros(e) ] }
    check(failures, seed, "effective_memberships", norm(naive.effective_memberships), em)

    eg = Directory::EffectiveGrant.unscoped.pluck(:person_id, :target_collection_id, :permission, :expires_at)
      .to_h { |p, t, perm, e| [ [ p, t, perm ], micros(e) ] }
    check(failures, seed, "effective_grants", norm(naive.effective_grants), eg)
  end

  def requirements_by_app = Directory::AppRequirement.pluck(:app_id, :entitlement_id).group_by(&:first).transform_values { |r| r.map(&:last).to_set }
  def exposures_by_app = Directory::Exposure.pluck(:app_id, :entitlement_id).group_by(&:first).transform_values { |r| r.map(&:last).to_set }

  def passes?(reqs, held) = reqs.nil? || reqs.empty? || reqs.intersect?(held)

  # [identity_id, app_id] pairs the groups claim reaches, read before anything is revoked
  def claim_reach(apps, tokens, identity_ids)
    requesting = apps.select { |a| a.scopes.to_s.split.include?("groups") }.map(&:id).to_set
    pairs = requesting.to_a.product(identity_ids).to_set(&:reverse)
    tokens.each do |t|
      t.reload
      next if t.revoked_at

      pairs << [ t.resource_owner_id, t.application_id ] if requesting.include?(t.application_id) || t.scopes.to_s.split.include?("groups")
    end
    pairs
  end

  describe "a freshly built directory" do
    DirectoryAccessProperties::STATIC_CASES.times do |i|
      seed = DirectoryAccessProperties::BASE_SEED + i

      it "matches the naive model (seed #{seed})" do
        rng = Random.new(seed)
        world = build_directory(rng)
        naive = DirectoryNaive.load
        failures = []

        # 1. derived tables
        check_derived_tables(failures, seed, naive)

        # 2. validate agrees
        result = Directory::Validate.call
        failures << "seed #{seed} validate: #{result.mismatches.inspect}" unless result.valid?

        # 3. policies
        live_grants = naive.effective_grants.select { |_, exp| exp.nil? || exp > naive.now }.keys.to_set
        world[:people].each do |person|
          plain = Directory::Context.new(identity: person.identity, person:, admin: false)
          preloaded = Directory::Context.new(identity: person.identity, person:, admin: false).preload_grants!
          world[:collections].each do |c|
            DirectoryAccessProperties::PERMISSIONS.each do |perm|
              want = live_grants.include?([ person.id, c.id, perm ])
              [ plain, preloaded ].each do |ctx|
                failures << "seed #{seed} can?(#{perm}) person #{person.id} on #{c.id}: want #{want}" unless ctx.can?(perm, c) == want
              end
            end
            show = DirectoryAccessProperties::PERMISSIONS.any? { |perm| live_grants.include?([ person.id, c.id, perm ]) }
            manage = live_grants.include?([ person.id, c.id, "manage_members" ])
            policy = Directory::CollectionPolicy.new(plain, c)
            failures << "seed #{seed} show? person #{person.id} on #{c.id}: want #{show}" unless policy.show? == show
            failures << "seed #{seed} manage_members? person #{person.id} on #{c.id}: want #{manage}" unless policy.manage_members? == manage
          end
          has_any = live_grants.any? { |p, _, _| p == person.id }
          failures << "seed #{seed} has_any_grants? person #{person.id}: want #{has_any}" unless plain.has_any_grants? == has_any
        end

        # 4. requirement check, 5. claims
        reqs = requirements_by_app
        exposures = Directory::Exposure.pluck(:app_id, :entitlement_id, :claim_name)
        world[:people].each do |person|
          held = naive.entitlements_of(person.id)
          world[:apps].each do |app|
            want = passes?(reqs[app.id], held)
            got = Directory::RequirementCheck.passes?(identity: person.identity, app:)
            failures << "seed #{seed} requirement app #{app.id} person #{person.id}: want #{want}" unless got == want

            want_claims = exposures.select { |a, e, _| a == app.id && held.include?(e) }.map(&:last).sort
            got_claims = Directory::Exposure.claim_names_for(person:, app:).sort
            failures << "seed #{seed} claims app #{app.id} person #{person.id}: want #{want_claims} got #{got_claims}" unless got_claims == want_claims
          end
        end

        expect(failures).to be_empty, failures.first(20).join("\n")
      end
    end
  end

  # one random change, run the way the app runs it, then: who lost tokens?
  describe "revocation after a change" do
    DirectoryAccessProperties::MUTATION_CASES.times do |i|
      seed = DirectoryAccessProperties::BASE_SEED + 10_000 + i

      it "revokes exactly the people who lost access (seed #{seed})" do
        rng = Random.new(seed)
        world = build_directory(rng)
        failures = []

        before_em = Directory::EffectiveMembership.unscoped.pluck(:person_id, :collection_id)
          .group_by(&:first).transform_values { |r| r.map(&:last).to_set }
        reqs_before = requirements_by_app
        exposures = exposures_by_app
        reach = claim_reach(world[:apps], world[:tokens], world[:people].map(&:identity_id))
        identity_of = world[:people].to_h { |p| [ p.id, p.identity_id ] }
        person_of = identity_of.invert

        kind, consequence = nil
        mutated = false
        # removals are where revocation happens, so try them first more often
        order = DirectoryAccessProperties::MUTATION_KINDS.sort_by { |k| rng.rand * (%i[renew_membership add_membership].include?(k) ? 3 : 1) }
        order.each do |candidate|
          kind = candidate
          mutated, consequence = run_mutation(candidate, world, rng)
          break if mutated
        end
        skip "seed #{seed}: no applicable mutation" unless mutated

        naive_after = DirectoryNaive.load
        check_derived_tables(failures, seed, naive_after) unless kind == :remove_requirement
        reqs_after = requirements_by_app

        revoked_pairs = Set.new
        world[:tokens].group_by { |t| [ t.resource_owner_id, t.application_id ] }.each do |pair, tokens|
          states = tokens.map { |t| t.reload.revoked_at.present? }.uniq
          failures << "seed #{seed} #{kind}: pair #{pair} only partly revoked" if states.size > 1
          revoked_pairs << pair if states.include?(true)
        end

        world[:tokens].map { |t| [ t.resource_owner_id, t.application_id ] }.uniq.each do |identity_id, app_id|
          person_id = person_of[identity_id]
          deleted = !Directory::Person.exists?(person_id)
          held_before = before_em.fetch(person_id, Set.new)
          held_after = deleted ? Set.new : naive_after.entitlements_of(person_id)
          passes_before = passes?(reqs_before[app_id], held_before)
          passes_after = passes?(reqs_after[app_id], held_after)
          exposed = exposures.fetch(app_id, Set.new)
          claims_lost = reach.include?([ identity_id, app_id ]) && !(held_before & exposed).subset?(held_after)
          revoked = revoked_pairs.include?([ identity_id, app_id ])

          if kind == :remove_requirement && app_id == @requirement_app_id
            must = reqs_after[app_id].present? && !passes_after
            must_not = passes_after
          elsif kind == :remove_requirement
            # nothing about any other app changed
            must = false
            must_not = true
          else
            must = (passes_before && !passes_after) || claims_lost
            must_not = passes_after && !claims_lost
          end

          failures << "seed #{seed} #{kind}: identity #{identity_id} app #{app_id} kept access it lost (reqs #{reqs_before[app_id].to_a}→#{reqs_after[app_id].to_a}, held #{held_before.to_a}→#{held_after.to_a}, exposed #{exposed.to_a}, reach #{reach.include?([ identity_id, app_id ])})" if must && !revoked
          failures << "seed #{seed} #{kind}: identity #{identity_id} app #{app_id} revoked but still has access" if must_not && revoked
        end

        # 7. the remove dialog named the apps the removal actually costs
        if consequence
          expected_names, text = consequence
          named = text.to_s.scan(/papp-\d+-\d+/).to_set
          check(failures, seed, "#{kind} consequence apps (#{text.inspect})", expected_names, named)
        end

        expect(failures).to be_empty, failures.first(20).join("\n")
      end
    end

    # returns [mutated?, [expected app names, consequence text] or nil]
    def run_mutation(kind, world, rng)
      case kind
      when :remove_person_membership, :remove_group_edge
        column = kind == :remove_person_membership ? :member_person_id : :member_group_id
        m = Directory::Membership.active.where.not(column => nil).to_a.sample(random: rng)
        return [ false, nil ] unless m

        consequence = expected_consequence(m, world)
        perform_enqueued_jobs(only: Directory::AfterChangeJob) { Directory.mutate!(cause: "property") { m.destroy! } }
        [ true, consequence ]
      when :expire_membership
        m = Directory::Membership.active.to_a.sample(random: rng)
        return [ false, nil ] unless m

        m.update_columns(expires_at: ActiveRecord::Base.connection.select_value("SELECT NOW()") - 1.hour)
        perform_enqueued_jobs(only: Directory::AfterChangeJob) { Directory::MembershipExpirySweepJob.perform_now }
        [ true, nil ]
      when :delete_collection
        # an entitlement an app still requires can't be deleted (restrict FK)
        required = Directory::AppRequirement.distinct.pluck(:entitlement_id)
        c = Directory::Collection.where.not(id: required).to_a.sample(random: rng)
        return [ false, nil ] unless c

        perform_enqueued_jobs(only: Directory::AfterChangeJob) do
          revocations = nil
          Directory.mutate!(cause: "property") do
            revocations = Directory::DestroyRevocations.for_entitlement(c)
            c.destroy!
          end
          Directory::AfterChangeJob.perform_later(change_ids: [], revocations:) if revocations.any?
        end
        [ true, nil ]
      when :delete_person
        person = world[:people].sample(random: rng)
        perform_enqueued_jobs(only: Directory::AfterChangeJob) do
          revocations = nil
          Directory.mutate!(cause: "property") do
            revocations = Directory::DestroyRevocations.for_person(person.reload)
            person.destroy!
          end
          Directory::AfterChangeJob.perform_later(change_ids: [], revocations:) if revocations.any?
        end
        [ true, nil ]
      when :renew_membership
        # a lapsed membership extended again, the way memberships#update does it
        m = Directory::Membership.where("expires_at <= NOW()").to_a.sample(random: rng)
        return [ false, nil ] unless m

        perform_enqueued_jobs(only: Directory::AfterChangeJob) do
          Directory.mutate!(cause: "property") { m.update!(expires_at: ActiveRecord::Base.connection.select_value("SELECT NOW()") + 5.hours) }
        end
        [ true, nil ]
      when :add_membership
        person = world[:people].sample(random: rng)
        c = world[:collections].sample(random: rng)
        return [ false, nil ] if Directory::Membership.exists?(collection: c, member_person: person)

        perform_enqueued_jobs(only: Directory::AfterChangeJob) do
          Directory.mutate!(cause: "property") { Directory::Membership.create!(collection: c, member_person: person) }
        end
        [ true, nil ]
      when :remove_requirement
        req = Directory::AppRequirement.all.to_a.sample(random: rng)
        return [ false, nil ] unless req

        app = req.app
        @requirement_app_id = app.id
        req.destroy!
        Directory::RevokeAccess.bulk_revoke_non_passing(app:) if Directory::AppRequirement.exists?(app_id: app.id)
        [ true, nil ]
      end
    end

    # what Consequence says removing m costs (as an admin), and what the naive model says
    def expected_consequence(membership, world)
      viewer = Directory::Context.new(identity: world[:admin], person: nil, admin: true)
      text = Directory::Consequence.batch_removal_summaries(memberships: [ membership ], collection: membership.collection, viewer:)[membership.id]

      before = DirectoryNaive.load
      after = DirectoryNaive.load(except_membership_ids: [ membership.id ])
      reqs = requirements_by_app
      exposures = exposures_by_app
      reach = claim_reach(world[:apps], world[:tokens], world[:people].map(&:identity_id))
      names = world[:apps].to_h { |a| [ a.id, a.name ] }

      affected = before.effective_memberships.keys.map(&:last).uniq
      expected = Set.new
      affected.each do |person_id|
        held_before = before.entitlements_of(person_id)
        held_after = after.entitlements_of(person_id)
        identity_id = world[:people].find { |p| p.id == person_id }&.identity_id
        world[:apps].each do |app|
          lost_requirement = passes?(reqs[app.id], held_before) && !passes?(reqs[app.id], held_after)
          lost_claim = reach.include?([ identity_id, app.id ]) && !(held_before & exposures.fetch(app.id, Set.new)).subset?(held_after)
          expected << names[app.id] if lost_requirement || lost_claim
        end
      end
      [ expected, text ]
    end
  end
end
