# auth

Auth service for Hack Club ecosystem. Endpoints are as follows:

Objects:

- User
  - ID
  - Created
  - Email
  - Phone number
  - Preferred auth method (:email / :sms)
  - Auth Tokens

- Login Code
  - ID
  - User
  - Created
  - Created IP Address
  - Created User Agent
  - Login Code
  - Sent Method (:email / :sms)
  - Auth Token (for whether it was activated)

- Auth Token
  - ID
  - User
  - Created
  - Created IP Address
  - Created User Agent - Maybe do separate API Request object
  - Invalidated
  - Invalidated IP Address
  - Invalidated User Agent
  - Token

API requests:

- `POST /login_codes`
  - Automatically creates user if doesn't exist
  - Optionally specify preferred auth method. For SMS must have email set
- `POST /auth_tokens` w/ login code
- `POST /auth_tokens/:id/invalidate`
- `PATCH /user/:id`
