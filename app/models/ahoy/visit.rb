# frozen_string_literal: true

module Ahoy
  class Visit < AnalyticsRecord
    self.table_name = "ahoy_visits"

    has_many :events, class_name: "Ahoy::Event", dependent: :nullify

    # Privacy: No user association - visits are anonymous
  end
end
