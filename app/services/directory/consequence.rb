# frozen_string_literal: true

module Directory
  class Consequence
    # For each membership about to be removed from `collection`, what it costs: the collections
    # the affected people stop reaching and the apps they lose (a requirement they no longer
    # meet, or a groups claim through an exposure — the same apps AfterChangeJob revokes).
    # Returns { membership_id => "will lose …" }. Collections `viewer` can't see are counted,
    # not named, and so are apps lost only through them.
    def self.batch_removal_summaries(memberships:, collection:, viewer:)
      new(memberships:, collection:, viewer:).summaries
    end

    def initialize(memberships:, collection:, viewer:)
      @memberships = memberships
      @collection = collection
      @viewer = viewer
      @reach_cache = {}
    end

    def summaries
      return {} if @memberships.empty?

      load_graph
      outcomes = @memberships.to_h { |m| [ m.id, outcomes_for(m) ] }.reject { |_, o| o.empty? }
      return {} if outcomes.empty?

      load_collections_and_apps(outcomes.values.flatten(1).flat_map { |lost, _| lost.to_a })
      outcomes.to_h { |id, o| [ id, describe(o, group_row: @memberships.find { |m| m.id == id }.member_group_id.present?) ] }.compact
    end

    private

    def load_graph
      @parents = Hash.new { |h, k| h[k] = [] }
      Directory::Membership.active.where.not(member_group_id: nil)
        .pluck(:member_group_id, :collection_id)
        .each { |child, parent| @parents[child] << parent }

      group_ids = @memberships.filter_map(&:member_group_id)
      @people_in_group = Directory::EffectiveMembership
        .where(collection_id: group_ids)
        .where("expires_at IS NULL OR expires_at > NOW()")
        .pluck(:collection_id, :person_id)
        .group_by(&:first).transform_values { |rows| rows.map(&:last) }

      person_ids = (@memberships.filter_map(&:member_person_id) + @people_in_group.values.flatten).uniq
      @direct = Directory::Membership.active.where(member_person_id: person_ids)
        .pluck(:member_person_id, :collection_id)
        .group_by(&:first).transform_values { |rows| rows.map(&:last).to_set }
    end

    # [[lost collection ids, collection ids still reached], …] — one pair per affected person
    def outcomes_for(membership)
      if membership.member_person_id
        direct = @direct[membership.member_person_id] || Set.new
        [ outcome(direct, reach(direct - [ @collection.id ])) ]
      elsif membership.member_group_id
        edge = [ membership.member_group_id, @collection.id ]
        (@people_in_group[membership.member_group_id] || []).map do |person_id|
          direct = @direct[person_id] || Set.new
          outcome(direct, reach(direct, without: edge))
        end
      else
        []
      end.reject { |lost, _| lost.empty? }
    end

    def outcome(direct, after)
      [ reach(direct) - after, after ]
    end

    def reach(start, without: nil)
      @reach_cache[[ start, without ]] ||= begin
        seen = Set.new(start)
        queue = start.to_a
        while (id = queue.shift)
          @parents[id].each do |parent|
            next if [ id, parent ] == without || seen.include?(parent)
            seen << parent
            queue << parent
          end
        end
        seen
      end
    end

    def load_collections_and_apps(lost_ids)
      collections = Directory::Collection.where(id: lost_ids.uniq).index_by(&:id)
      @visible = collections.values
        .select { |c| c.id == @collection.id || Directory::CollectionPolicy.new(@viewer, c).show? }
        .to_h { |c| [ c.id, c.name ] }
      entitlement_ids = collections.values.select(&:entitlement?).map(&:id)

      @exposed_apps = Directory::Exposure.where(entitlement_id: entitlement_ids)
        .pluck(:entitlement_id, :app_id)
        .group_by(&:first).transform_values { |rows| rows.map(&:last) }

      required_app_ids = Directory::AppRequirement.where(entitlement_id: entitlement_ids).distinct.pluck(:app_id)
      @requirements = Directory::AppRequirement.where(app_id: required_app_ids)
        .pluck(:app_id, :entitlement_id)
        .group_by(&:first).transform_values { |rows| rows.map(&:last).to_set }

      app_ids = @exposed_apps.values.flatten + @requirements.keys
      @app_names = Program.where(id: app_ids.uniq).pluck(:id, :name).to_h
    end

    # { app_id => lost entitlement ids that cost it }
    def lost_apps(lost, after)
      apps = Hash.new { |h, k| h[k] = Set.new }
      lost.each do |eid|
        (@exposed_apps[eid] || []).each { |app_id| apps[app_id] << eid }
      end
      @requirements.each do |app_id, required|
        hit = required & lost
        apps[app_id].merge(hit) if hit.any? && !required.intersect?(after)
      end
      apps
    end

    def describe(outcomes, group_row:)
      lost = Set.new
      apps = Hash.new { |h, k| h[k] = Set.new }
      outcomes.each do |person_lost, after|
        lost.merge(person_lost)
        lost_apps(person_lost, after).each { |app_id, via| apps[app_id].merge(via) }
      end

      # a person row's own collection is already in the prompt ("remove X from Y?"); a group
      # row's people lose it too, and that isn't obvious
      named = group_row ? lost.to_a : lost.reject { |id| id == @collection.id }
      names = named.filter_map { |id| @visible[id] }.sort
      hidden = named.count { |id| !@visible.key?(id) }

      app_names = []
      apps.each do |app_id, via|
        if via.any? { |id| @visible.key?(id) }
          app_names << @app_names[app_id]
        else
          hidden += 1
        end
      end
      app_names = app_names.compact.sort

      parts = []
      parts << (names.size <= 3 ? names.to_sentence : "#{names.size} memberships including #{names.first(2).join(' and ')}") if names.any?
      parts << "access to #{app_names.to_sentence}" if app_names.any?
      return nil if parts.empty? && hidden.zero?

      text = if parts.any?
        "will lose #{parts.join(' and ')}#{" (+#{hidden} you can't see)" if hidden.positive?}"
      else
        "will lose access through #{hidden} #{hidden == 1 ? 'thing' : 'things'} you can't see"
      end
      group_row ? "#{outcomes.size} #{outcomes.size == 1 ? 'person' : 'people'} #{text}" : text
    end
  end
end
