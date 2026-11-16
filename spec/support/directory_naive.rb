# frozen_string_literal: true

# A deliberately dumb re-implementation of the directory's derived state, for property specs.
# Reads the raw tables, walks the graph in Ruby, and says what closure, effective memberships
# and effective grants should be. Expiry: nil means "never"; an edge counts while expires_at
# is nil or after the database's NOW() (the clock GraphQueries uses). Along a path the earliest
# expiry wins; across paths the latest one does.
class DirectoryNaive
  Edge = Struct.new(:id, :parent, :child_group, :person, :expires_at, keyword_init: true)

  attr_reader :now, :edges

  def self.load(except_membership_ids: [])
    new(except_membership_ids:)
  end

  def initialize(except_membership_ids: [])
    @now = ActiveRecord::Base.connection.select_value("SELECT NOW()")
    @protected = Directory::Collection.where(protected: true).pluck(:id).to_set
    @collection_ids = Directory::Collection.pluck(:id)
    @edges = Directory::Membership.where.not(id: except_membership_ids)
      .pluck(:id, :collection_id, :member_group_id, :member_person_id, :expires_at)
      .map { |id, parent, group, person, exp| Edge.new(id:, parent:, child_group: group, person:, expires_at: exp) }
    @grants = Directory::Grant.pluck(:grantee_group_id, :target_collection_id, :permission, :recursive)
  end

  def active?(edge) = edge.expires_at.nil? || edge.expires_at > now

  # nil is "never expires"
  def self.earliest(a, b) = a.nil? ? b : (b.nil? ? a : [ a, b ].min)
  def self.latest(a, b) = (a.nil? || b.nil?) ? nil : [ a, b ].max

  def children
    @children ||= edges.select { |e| e.child_group && active?(e) }.group_by(&:parent)
  end

  # { [ancestor, descendant] => [min depth, best expiry, any_path_seen] }
  def closure
    @closure ||= begin
      out = {}
      @collection_ids.each do |root|
        walk(root, 0, nil, [ root ]) do |node, depth, exp|
          key = [ root, node ]
          if (cur = out[key])
            out[key] = [ [ cur[0], depth ].min, self.class.latest(cur[1], exp) ]
          else
            out[key] = [ depth, exp ]
          end
        end
      end
      out
    end
  end

  # { [collection, person] => expiry }
  def effective_memberships
    @effective_memberships ||= begin
      out = {}
      edges.select { |e| e.person && active?(e) }.each do |m|
        closure.each do |(ancestor, descendant), (_depth, path_exp)|
          next unless descendant == m.parent

          exp = self.class.earliest(m.expires_at, path_exp)
          key = [ ancestor, m.person ]
          out[key] = out.key?(key) ? self.class.latest(out[key], exp) : exp
        end
      end
      out
    end
  end

  # { [person, target, permission] => expiry }
  def effective_grants
    @effective_grants ||= begin
      out = {}
      em_by_collection = effective_memberships.group_by { |(collection, _), _| collection }
      @grants.each do |grantee, target, permission, recursive|
        targets = []
        if recursive
          walk(target, 0, nil, [ target ], skip_protected: true) { |node, _depth, exp| targets << [ node, exp ] }
        else
          targets << [ target, nil ]
        end

        (em_by_collection[grantee] || []).each do |(_, person), em_exp|
          targets.each do |node, path_exp|
            exp = self.class.earliest(path_exp, em_exp)
            key = [ person, node, permission ]
            out[key] = out.key?(key) ? self.class.latest(out[key], exp) : exp
          end
        end
      end
      out
    end
  end

  def entitlements_of(person_id)
    effective_memberships.keys.select { |_, p| p == person_id }.map(&:first).to_set
  end

  private

  # yields every (node, depth, path expiry) reachable from start through active group edges,
  # start included at depth 0, paths up to MAX_DEPTH edges
  def walk(node, depth, exp, path, skip_protected: false, &block)
    yield node, depth, exp
    return if depth >= Directory::MAX_DEPTH

    (children[node] || []).each do |edge|
      child = edge.child_group
      next if path.include?(child)
      next if skip_protected && @protected.include?(child)

      walk(child, depth + 1, self.class.earliest(exp, edge.expires_at), path + [ child ], skip_protected:, &block)
    end
  end
end
