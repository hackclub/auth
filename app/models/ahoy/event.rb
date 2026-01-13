# frozen_string_literal: true

module Ahoy
  class Event < AnalyticsRecord
    self.table_name = "ahoy_events"

    include Ahoy::QueryMethods

    belongs_to :visit, class_name: "Ahoy::Visit", optional: true

    # Privacy: No user association - events are anonymous

    # Scopes for funnel analysis
    scope :signup, -> { where("name LIKE 'signup.%'") }
    scope :login, -> { where("name LIKE 'login.%'") }
    scope :dialogue, -> { where("name LIKE 'dialogue.%'") }
    scope :by_name, ->(name) { where(name: name) }
    scope :by_scenario, ->(scenario) { where("properties->>'scenario' = ?", scenario) }
    scope :in_range, ->(start_date, end_date) { where(time: start_date..end_date) }
  end
end
