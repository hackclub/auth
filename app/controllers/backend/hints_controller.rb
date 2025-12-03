# frozen_string_literal: true

module Backend
  class HintsController < ApplicationController
    skip_after_action :verify_authorized

    def mark_seen
      body = JSON.parse(request.body.read) rescue {}
      slugs = body["slugs"] || []
      slugs.each { |slug| current_user.seen_hint!(slug) }
      head :ok
    end
  end
end
