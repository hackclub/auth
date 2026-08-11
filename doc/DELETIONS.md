# deletions

when someone asks us to delete their account, we scrub all their PII and leave behind a tombstone so we can tell if they try to come back.

used to be a rake task you had to run in prod. now there's a web UI at `/backend/deletions`. see [`DeletionService`](../app/services/deletion_service.rb) for the implementation.

## the short version

[`DeletionService.execute_deletion`](../app/services/deletion_service.rb) locks the account, destroys all auth/session data, purges uploaded documents, scrubs every PII field we can find (addresses, aadhaar, names, emails, etc), cleans up PaperTrail versions so the old data can't be recovered from history, and creates a [`Deletion`](../app/models/deletion.rb) tombstone record. all in one transaction.

**destroyed:** login codes, login attempts, sessions, TOTPs, backup codes, webauthn credentials, email change requests, access tokens, OAuth grants, resemblances, document files, vouch evidence, PaperTrail versions, Flipper actor gates

**scrubbed:** identity names/email/birthday/phone/slack/aadhaar (all `[REDACTED]` or nil), address PII, aadhaar record PII, activity log parameters, program collaborator emails

**survives (intentionally):** the identity row itself (tombstoned, `permabanned: true` -- need it for FK integrity), verification records (status/timestamps only, files purged), the `Deletion` tombstone, the `deletion_request` activity log entry

## tombstones

we can't store the deleted person's actual email or name (we just scrubbed it), but we need to catch re-registration. the `Deletion` record stores HMAC-SHA256 hashes of the original email, pairwise name token combinations (bound to DOB), and session IPs. these are irreversible -- you can check "is this the same email?" but you can't recover the original from the hash.

the HMAC key is derived via `ActiveSupport::KeyGenerator` with a purpose-specific salt, not `secret_key_base` raw.

## name combo hashing

we tokenize all name fields (preferred + legal), take every pair of tokens sorted alphabetically, concatenate with DOB, and HMAC. so "John Smith" born 2005-06-15 produces `hmac("john|smith|2005-06-15")`.

this means a deleted "John Michael Smith" will collide with a new "Michael Smith" (same DOB) because they share the `(michael, smith)` pair. false positives are possible with common names but the DOB binding keeps it manageable at our volume.

at IDV time, [`ResemblanceNoticerEngine`](../app/services/resemblance_noticer_engine.rb) checks for overlaps and creates [`TombstoneCollision`](../app/models/identity/tombstone_collision.rb) records. these show up as skulls on the pending list -- ops should check in with nora before approving.

## permissions

[`can_process_deletions`](../app/policies/deletion_policy.rb) is console-only. super_admin doesn't inherit it.

```ruby
Backend::User.find_by(username: "whoever").update!(can_process_deletions: true)
```

## the flow

1. find the identity, click "begin deletion..." (or go to `/backend/deletions/new` directly)
2. enter the identifier and airtable privacy request reference
3. confirm page shows you who you're about to nuke
4. type DELETE, hit the button
5. execution log shows what happened
