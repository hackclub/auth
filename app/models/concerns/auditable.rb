# frozen_string_literal: true

module Auditable
  extend ActiveSupport::Concern

  included do
    class_attribute :auditable_fields, default: {}
  end

  class_methods do
    # Declare fields to track. Types: :scalar (default), :array, :boolean
    # label: human-readable name for the field
    # transform: optional lambda to format values for display
    def audit_field(name, type: :scalar, label: nil, transform: nil)
      self.auditable_fields = auditable_fields.merge(
        name => { type: type, label: label || name.to_s.humanize, transform: transform }
      )
    end
  end

  # Snapshot current values for declared fields
  def audit_snapshot
    auditable_fields.each_with_object({}) do |(name, _config), hash|
      val = send(name)
      hash[name] = val.is_a?(Array) ? val.dup : val
    end
  end

  # Compute structured diff between snapshot and current state
  def audit_diff(snapshot)
    changes = {}
    auditable_fields.each do |name, config|
      old_val = snapshot[name]
      new_val = send(name)

      case config[:type]
      when :array
        old_arr = Array(old_val)
        new_arr = Array(new_val)
        added = new_arr - old_arr
        removed = old_arr - new_arr
        next if added.empty? && removed.empty?
        changes[name] = { added: added, removed: removed }
      when :boolean
        next if old_val == new_val
        changes[name] = { from: old_val, to: new_val }
      else # :scalar
        next if old_val == new_val
        transform = config[:transform]
        changes[name] = {
          from: transform ? transform.call(old_val) : old_val,
          to: transform ? transform.call(new_val) : new_val
        }
      end
    end
    changes
  end
end
