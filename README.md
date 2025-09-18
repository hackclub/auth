# Identity Vault

This is the Rails codebase powering https://identity.hackclub.com!

## contributing

ask around in [#idv-dev](https://hackclub.slack.com/archives/C09D1E22CF5) or poke [nora](https://hackclub.slack.com/team/U06QK6AG3RD)!

avoid questions that can be answered by reading the source code, but otherwise i'd be happy to help you get up to speed :-D

kindly `bin/lint` your code before you submit it!

### areas of focus

the ops view components (look in `app/components`) are a hot mess...

so is the onboarding controller, she should really be ripped out and replaced.

## dev setup

- make sure you have working installations of ruby ≥ 3.4.4 & nodejs
- clone repo
- create .env.development, populate `DATABASE_URL` w/ a local postgres instance 
- if you want to use docker, you can run `docker compose -f docker-compose-dbonly.yml up` to spin up a database and plug `postgresql://postgres@localhost:5432/identity_vault_development` in as your `DATABASE_URL`
- run `bundle install`
- run `rails db:prepare`
- console in (`bin/rails console`)
  - `Backend::User.create!(slack_id: "U<whatever>", username: "<you>", active: true, super_admin: true)`
- run `bin/dev` (and `bin/vite dev` if you want hot reload on css & js)
- visit `http://localhost:3000/backend/login`, paste that Slack ID in, and "fake it til' you make it"

## security

this oughta go without saying, but if you find a security-relevant issue please either contact me directly or go through the security.hackclub.com flow –
if you just open an issue or a PR there's a chance a bad actor sees it and exploits it before we can patch or merge.
