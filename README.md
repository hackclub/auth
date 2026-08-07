# Hack Club Auth

This is the Rails codebase powering https://auth.hackclub.com!

## contributing

ask around in [#idv-dev](https://hackclub.slack.com/archives/C09D1E22CF5) or poke [nora](https://hackclub.slack.com/team/U06QK6AG3RD)!

avoid questions that can be answered by reading the source code, but otherwise i'd be happy to help you get up to speed :-D

kindly `bin/lint` your code before you submit it!

## local dev setup

### prerequisites

you'll need:
- ruby 3.4.4+ (i use [mise](https://mise.jdx.dev) to manage this)
- node.js + yarn
- postgres (see below)
- imagemagick & libvips (image processing)
- libxmlsec1 (SAML signing)

on macOS:

```bash
brew install imagemagick libvips libxmlsec1 yarn
```

### database

easiest way is docker. if you don't have it and you're on macOS, [orbstack](https://orbstack.dev) works well enough.

```bash
docker compose -f docker-compose-dbonly.yml up -d
```

this gives you a postgres instance at `postgresql://postgres@localhost:5432/identity_vault_development`.

if you've got your own postgres running somewhere, that works too – just point at it.

### environment

create a `.env.development` file:

```bash
DATABASE_URL=postgresql://postgres@localhost:5432/identity_vault_development
```

that's it for local dev – lockbox will use a deterministic dev key automatically. see [environment variables](#environment-variables) below for the full list.

### install & setup

```bash
bundle install
yarn install
bin/rails db:prepare
bin/rails db:seed
```

the seeds create a dev account with 2FA already set up. it'll print out the TOTP secret – add that to your authenticator app.

### running the thing

```bash
bin/dev
```

if you want hot reload on css & js, also run `bin/vite dev` in another terminal.

### logging in to the backend

1. go to http://localhost:3000/login
2. enter `identity@hackclub.com`
3. grab the verification code from http://localhost:3000/letter_opener
4. enter your TOTP code (from the authenticator app you set up during seeding)
5. head to http://localhost:3000/backend

the backend requires 2FA – that's why the seeds set up a TOTP for you.

## environment variables

### required

| var | description |
|-----|-------------|
| `DATABASE_URL` | postgres connection string |

### required in production

| var | description |
|-----|-------------|
| `SECRET_KEY_BASE` | rails secret key – generate with `openssl rand -hex 64` |
| `LOCKBOX_MASTER_KEY` | encryption key for lockbox fields – generate with `openssl rand -hex 32` |

### active record encryption

used for `encrypts` fields (like aadhaar data). generate these with `bin/rails db:encryption:init` or use random strings.

| var | description |
|-----|-------------|
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | primary encryption key |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | deterministic encryption key |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | key derivation salt |

### slack integration

| var | description |
|-----|-------------|
| `SLACK_BOT_TOKEN` | bot token (xoxb-*) |
| `SLACK_TEAM_ID` | workspace ID (T*) |
| `SLACK_SCIM_TOKEN` | SCIM API token for user provisioning |
| `SLACK_CLIENT_ID` | OAuth client ID |
| `SLACK_CLIENT_SECRET` | OAuth client secret |
| `SLACK_SIGNING_SECRET` | webhook request verification |
| `SLACK_ADULT_WEBHOOK_URL` | webhook for guardian notifications |

### SAML

| var | description |
|-----|-------------|
| `SAML_IDP_CERT_PATH` | path to SAML IdP certificate |
| `SAML_IDP_KEY_PATH` | path to SAML IdP private key |

generate a self-signed cert for local dev:

```bash
openssl req -x509 -newkey rsa:2048 -keyout saml_key.pem -out saml_cert.pem -days 365 -nodes -subj "/CN=localhost"
```

### OIDC

| var | description |
|-----|-------------|
| `OIDC_SIGNING_KEY` | RSA private key for JWT signing |

generate an RSA key:

```bash
openssl genrsa -out oidc_key.pem 2048
```

then set `OIDC_SIGNING_KEY` to the contents of `oidc_key.pem` (the whole thing including the BEGIN/END lines).

### email (production/staging/uat)

| var | description |
|-----|-------------|
| `SES_SMTP_HOST` | SES SMTP endpoint |
| `SES_SMTP_USERNAME` | SES SMTP username |
| `SES_SMTP_PASSWORD` | SES SMTP password |

### document storage (production)

| var | description |
|-----|-------------|
| `CLOUDFLARE_R2_ENDPOINT` | R2 endpoint URL |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2 access key |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2 secret key |

### other

| var | description |
|-----|-------------|
| `SENTRY_DSN` | error tracking |
| `GOOGLE_PLACES_API_KEY` | address autocomplete |
| `ANALYTICS_DATABASE_URL` | separate analytics DB (optional) |
| `DISABLE_ANALYTICS` | set to "true" to disable Ahoy |
| `SOURCE_COMMIT` | git commit for version display |

## security

this oughta go without saying, but if you find a security-relevant issue please either contact me directly or go through the security.hackclub.com flow –
if you just open an issue or a PR there's a chance a bad actor sees it and exploits it before we can patch or merge.
