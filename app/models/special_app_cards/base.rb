# frozen_string_literal: true

module SpecialAppCards
  class Base
    class << self
      def all
        @all ||= []
      end

      def inherited(subclass)
        super
        all << subclass
      end

      def for_identity(identity)
        all.filter_map { |klass| klass.new(identity) if klass.new(identity).visible? }
      end
    end

    attr_reader :identity

    def initialize(identity)
      @identity = identity
    end

    def visible?
      raise NotImplementedError, "Subclasses must implement #visible?"
    end

    def friendly_name
      raise NotImplementedError, "Subclasses must implement #friendly_name"
    end

    def tagline
      raise NotImplementedError, "Subclasses must implement #tagline"
    end

    def icon = nil

    def icon_background = nil

    def url
      raise NotImplementedError, "Subclasses must implement #url"
    end

    def launch_text = nil

    def to_h
      {
        friendly_name: friendly_name,
        tagline: tagline,
        icon: icon,
        icon_background: icon_background,
        url: url,
        launch_text: launch_text,
        special: true
      }
    end
  end
end
