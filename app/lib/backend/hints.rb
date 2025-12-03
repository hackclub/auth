module Backend
  module Hints
    Hint = Data.define(:slug, :content)

    ALL = [
      Hint[:list_navigation, <<~EOH
        <kbd>j</kbd> / <kbd>↓</kbd> next · <kbd>k</kbd> / <kbd>↑</kbd> prev · <kbd>Enter</kbd> open · <kbd>g</kbd> first · <kbd>G</kbd> last
      EOH
      ],
      Hint[:search_focus, <<~EOH
        <kbd>/</kbd> focus search
      EOH
      ],
      Hint[:verification_review, <<~EOH
        <kbd>a</kbd> approve (YSWS) · <kbd>A</kbd> approve (not YSWS) · <kbd>r</kbd> focus reject form<br>
        <kbd>Backspace</kbd> back to pending
      EOH
      ],
      Hint[:identity_actions, <<~EOH
        <kbd>e</kbd> edit identity · <kbd>Backspace</kbd> back to list
      EOH
      ],
      Hint[:back_navigation, <<~EOH
        <kbd>Backspace</kbd> go back
      EOH
      ],
      Hint[:pagination, <<~EOH
        <kbd>n</kbd> next page · <kbd>p</kbd> prev page
      EOH
      ]
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
