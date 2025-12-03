module Backend
  module Hints
    Hint = Data.define(:slug, :content)

    ALL = [
      Hint[:imaginary, <<~EOH
        woah cool
      EOH
      ]
    ].freeze.index_by(&:slug)

    def self.find(slug) = ALL[slug]

    module Controller
      extend ActiveSupport::Concern

      included do
        class_attribute :_hints, default: {}
        helper_method :current_hints, :has_unseen_hints?
      end

      class_methods do
        def hint(slug, on: nil)
          actions = Array(on).map(&:to_sym)
          actions.each do |action|
            self._hints = _hints.merge(action => (_hints[action] || []) + [slug.to_sym])
          end
        end
      end

      def current_hints
        slugs = self.class._hints[action_name.to_sym] || []
        slugs.filter_map { |slug| Backend::Hints.find(slug) }
      end

      def has_unseen_hints?
        return false unless current_user

        slugs = self.class._hints[action_name.to_sym] || []
        slugs.any? { |slug| !current_user.seen_hint?(slug) }
      end

      def mark_hints_seen
        return unless current_user

        slugs = self.class._hints[action_name.to_sym] || []
        slugs.each { |slug| current_user.seen_hint!(slug) }
      end
    end
  end
end