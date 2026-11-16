# frozen_string_literal: true

module Directory
  # Membership expiry dates. A bare date D means "valid through the end of D, eastern time"
  # (hack club runs on it); an ISO 8601 datetime is taken as given, in eastern time unless
  # it carries an offset.
  module Expiry
    ZONE = ActiveSupport::TimeZone["America/New_York"]

    # Unambiguous ISO 8601 only: Time.zone.parse guesses (nil for "tomorrow", Feb 1 for
    # "1/2/2027", March 2 for "2027-02-30"), and for an access expiry a wrong guess is worse
    # than an error.
    FORMAT = /\A(\d{4})-(\d{2})-(\d{2})((?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-](?:[01]\d|2[0-3])(?::?[0-5]\d)?)?))?\z/i

    module_function

    # nil when raw isn't a valid date or datetime
    def parse(raw)
      match = FORMAT.match(raw.to_s.strip)
      return unless match

      ymd = match.captures.first(3).map(&:to_i)
      return unless Date.valid_date?(*ymd)
      # whole microseconds, so storage can't round it into the next day
      return ZONE.local(*ymd).end_of_day.change(usec: 999_999) unless match[4]

      # no offset means eastern, same as a bare date
      ZONE.iso8601(raw.strip.sub(" ", "T"))
    rescue ArgumentError # out-of-range time, e.g. hour 25
      nil
    end

    # the date a stored expiry stands for, for date inputs and display
    def date_for(time)
      time&.in_time_zone(ZONE)&.to_date
    end

    # the earliest date a date input should offer
    def first_selectable_date
      ZONE.today
    end

    def label(time)
      return unless time

      local = time.in_time_zone(ZONE)
      if [ local.hour, local.min, local.sec ] == [ 23, 59, 59 ]
        local.to_date.iso8601
      else
        local.strftime("%Y-%m-%d %H:%M %Z")
      end
    end
  end
end
