# frozen_string_literal: true

module InternalHooksHelper
  def internal_content(slot)
    "Internal::Slots::#{slot.to_s.camelize}".safe_constantize&.then { |klass| render klass.new }
  end
end
