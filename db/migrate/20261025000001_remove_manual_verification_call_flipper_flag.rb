# the manual verification flow is no longer flipper-gated — access is simply
# "this identity has an open case", checked in code. the feature kept one
# stored actor per open case, which hit flipper's 100-actor cap and 500'd
# case creation (ActorLimit::LimitExceeded), and the actor list was only
# ever a hand-synced mirror of the cases table anyway.
class RemoveManualVerificationCallFlipperFlag < ActiveRecord::Migration[8.0]
  def up
    Flipper.remove("manual_verification_call_2026_07_03")
  end

  def down
    # nothing to restore — the flow is no longer flipper-gated
  end
end
