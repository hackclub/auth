# Remembers which account a browser last used for a given relying party, so
# returning to a tool doesn't re-prompt. Keyed by client_id for OIDC and by SP
# entity ID for SAML.
#
# This is a convenience only. It never overrides prompt=select_account, an
# id_token_hint, or a login_hint naming a different account.
class BrowserSession::ClientSelection < ApplicationRecord
  self.table_name = "browser_session_client_selections"

  KINDS = %w[oidc saml].freeze

  belongs_to :browser_session
  belongs_to :identity

  validates :client_kind, presence: true, inclusion: { in: KINDS }
  validates :client_ref, presence: true
end
