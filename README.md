# auth

To-Do:

- [ ] Implement routes until it's feature complete with what exists today in prod
  - [ ] `POST /login_codes`
    - [x] Rudimentary implementation
    - [x] Make UX exactly same as what's in production right now for basic flow
    - [x] Create user if doesn't exist
    - [ ] Lowercase emails & strip spaces around them
    - [ ] Make sure errors match what is in production
  - [ ] `POST /auth_tokens` w/ login code
    - [ ] Exchange login code for auth token, rudimentary implementation
  - [ ] `POST /auth_tokens/:id/invalidate`
    - [ ] Rudimentary implementation
  - [ ] `PATCH /user/:id`
    - [ ] Rudimentary implementation of updating fields
- [ ] Once feature-complete with what's in production today, migrate data and deploy
- [ ] Move `hackclub/api` to it w/ API passthrough for future requests to https://api.hackclub.com

Future:

- [ ] Optional SMS based auth

---

Auth service for Hack Club ecosystem. Endpoints are as follows:

Objects:

- User ID Created
  - Email
  - Phone number
  - Preferred auth method (:email / :sms)
  - Auth Tokens

- Login Code
  - ID
  - User
  - Created
  - Creator IP Address
  - Creator User Agent
  - Login Code
  - Sent Method (:email / :sms)
  - Auth Token (for whether it was activated)

- Auth Token
  - ID
  - User
  - Token
  - Created
  - Creator IP
  - Creator User Agent - Maybe do separate API Request object
  - Invalidated
  - Invalidator IP
  - Invalidator User Agent

API requests:

- `POST /login_codes` w/ email of user
  - Automatically creates user if doesn't exist
  - Optionally specify preferred auth method. For SMS must have email set
- `POST /auth_tokens` w/ login code
- `POST /auth_tokens/:id/invalidate`
- `PATCH /user/:id`

---

Set the following environment variables:

```
// Airtable API key + base to interact with
AIRTABLE_API_KEY=
AIRTABLE_BASE=

// Email credentials for sending login codes
SMTP_HOST=
SMTP_PORT=
SMTP_USERNAME=
SMTP_PASSWORD=
```
