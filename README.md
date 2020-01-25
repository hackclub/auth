# auth

API:

- Users
  - [ ] `GET /users/:id` (`:id` can be "me" in all requests for current user)
  - [ ] `PATCH /users/:id` to change fields
  - [ ] `GET /users/:id/access_tokens` for list of active access tokens
- Login codes
  - [x] `POST /login_codes` w/ email of user
    - Automatically creates user if doesn't exist
- Auth tokens
  - [ ] `POST /auth_tokens` w/ user id & login code
  - [ ] `POST /auth_tokens/:id/invalidate` (must be authed)

Ideas:

- [x] Separate objects for "Emails" in DB
- [ ] "API Request" object in DB

Notes:

- Need to test for SQL-injection equivalent in Airtable filters
- Must fix race condition reproducible with: `while true; do http POST localhost:8080/login_codes email="putanewuserhere@zachlatta.com" &; done`
  - Multiple users with same email gets created

Future:

- [ ] Optional SMS based auth

---

Auth service for Hack Club ecosystem. Endpoints are as follows:

Objects:

- User
  - ID
  - Created
  - Email
  - Auth Tokens

- Login Code
  - ID
  - User
  - Created
  - Creator IP Address
  - Creator User Agent
  - Login Code
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

- Email
  - ID
  - User
  - Login Code
  - To Email
  - From Email
  - Subject
  - Plain Text Body
  - HTML Body

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
