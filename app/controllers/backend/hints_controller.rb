# frozen_string_literal: true

module Backend
  class HintsController < ApplicationController
    skip_after_action :verify_authorized

    def mark_seen
      mark_hints_seen
      head :ok
    end
  end
end
