class AddLoginAttemptToV2LoginCodes < ActiveRecord::Migration[7.2]
  def change
    add_reference :identity_v2_login_codes, :login_attempt, foreign_key: true, index: true
    add_index :identity_v2_login_codes, [ :identity_id, :login_attempt_id, :code, :used_at ], name: 'index_v2_codes_on_identity_attempt_code_used'
  end
end
