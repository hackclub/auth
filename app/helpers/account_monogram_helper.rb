# frozen_string_literal: true

# Identities have no avatar, and fetching one from a third party would leak an
# email hash on every chooser render. A deterministic monogram is enough to make
# rows visually distinct without adding an avatar pipeline or a privacy problem.
module AccountMonogramHelper
  HACK_CLUB_EMAIL_DOMAIN = "hackclub.com"

  # Picked for adequate contrast against white monogram text in both themes.
  MONOGRAM_COLORS = %w[
    #2f6f4f
    #1f5f8b
    #5b3f9d
    #8b2f5f
    #8b4a1f
    #3f5f2f
    #1f6f6f
    #6b2f2f
  ].freeze

  def account_monogram_initials(identity)
    initials = [ identity.first_name, identity.last_name ]
      .compact_blank
      .map { |name| name.to_s.strip.first }
      .join
      .upcase

    initials.presence || identity.primary_email.to_s.first.to_s.upcase.presence || "?"
  end

  def account_monogram_color(identity)
    seed = Digest::SHA256.hexdigest(identity.public_id.to_s).to_i(16)
    MONOGRAM_COLORS[seed % MONOGRAM_COLORS.size]
  end

  def hack_club_account?(identity)
    identity.primary_email.to_s.downcase.end_with?("@#{HACK_CLUB_EMAIL_DOMAIN}")
  end

  # Distinguishing a work identity from a personal one is the whole point of the
  # chooser, so it gets a text label rather than colour alone.
  def account_kind_label(identity)
    hack_club_account?(identity) ? t("accounts.kind.hack_club") : t("accounts.kind.personal")
  end
end
