# the manual-verification flag kept one stored actor per open case and hit
# flipper's 100-actor cap on case creation (ActorLimit::LimitExceeded).
# membership is now computed by the :has_open_verification_case group
# (config/initializers/flipper.rb): enable it once here, and drop the stored
# actors — they're redundant, and every enabled? check loads the whole set.
class EnableOpenCaseGroupForManualVerificationCall < ActiveRecord::Migration[8.0]
  FLAG = "manual_verification_call_2026_07_03"

  def up
    Flipper.enable_group(FLAG, :has_open_verification_case)
    execute("DELETE FROM flipper_gates WHERE feature_key = #{connection.quote(FLAG)} AND key = 'actors'")
  end

  def down
    # the deleted actor rows can't be restored — rolling back means
    # re-enabling actors by hand for identities with open cases
    Flipper.disable_group(FLAG, :has_open_verification_case)
  end
end
