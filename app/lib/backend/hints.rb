module Backend
  module Hints
    Hint = Data.define(:slug, :shortcuts)

    ALL = [
      Hint[:list_navigation, [
        { keys: ["j", "↓"], action: "next" },
        { keys: ["k", "↑"], action: "prev" },
        { keys: ["↵"], action: "open" },
        { keys: ["g"], action: "first" },
        { keys: ["G"], action: "last" },
      ]],
      Hint[:search_focus, [
        { keys: ["/"], action: "focus search" },
      ]],
      Hint[:verification_review, [
        { keys: ["a"], action: "approve (YSWS)" },
        { keys: ["A"], action: "approve (not YSWS)" },
        { keys: ["r"], action: "focus reject" },
        { keys: ["Bksp"], action: "back to pending" },
      ]],
      Hint[:identity_actions, [
        { keys: ["e"], action: "edit" },
        { keys: ["Bksp"], action: "back" },
      ]],
      Hint[:back_navigation, [
        { keys: ["Bksp"], action: "go back" },
      ]],
      Hint[:pagination, [
        { keys: ["n"], action: "next page" },
        { keys: ["p"], action: "prev page" },
      ]],
    ].freeze.index_by(&:slug)

    def self.find(slug) = ALL[slug]

    module Controller
      extend ActiveSupport::Concern

      included do
        class_attribute :_hints, default: {}, instance_accessor: false
        helper_method :current_hints, :has_unseen_hints?
      end

      class_methods do
        def hint(slug, on: nil)
          actions = Array(on).map(&:to_sym)
          self._hints = _hints.dup unless _hints.frozen?
          actions.each do |action|
            self._hints[action] = (_hints[action] || []) + [ slug.to_sym ]
          end
        end
      end

      def current_hints
        hints_for_action.filter_map { |slug| Backend::Hints.find(slug) }
      end

      def has_unseen_hints?
        return false unless current_user
        hints_for_action.any? { |slug| !current_user.seen_hint?(slug) }
      end

      def mark_hints_seen
        return unless current_user
        hints_for_action.each { |slug| current_user.seen_hint!(slug) }
      end

      private

      def hints_for_action
        self.class._hints[action_name.to_sym] || []
      end
    end

    module Shortcuts
      extend ActiveSupport::Concern

      included do
        helper_method :keyboard_shortcuts
      end

      def keyboard_shortcuts
        @_keyboard_shortcuts ||= {}
      end

      def set_keyboard_shortcut(key, path)
        keyboard_shortcuts[key] = path
      end
    end
  end
end
