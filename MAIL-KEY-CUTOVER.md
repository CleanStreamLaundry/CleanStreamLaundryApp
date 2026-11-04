# Email Named Secret Candidate

LOCAL ONLY. TEST SLOT RELEASED; candidate frozen for review. Deno 2.9.6:
41 passed, 0 failed (33 new + 8 existing independent); scoped fmt/lint clean
across 3 files. All processes exited. No environment values,
keys, deployments, gateway settings, providers or active checkouts changed.

## Scope

- `_shared/mail_keys.ts`: one pure exact-name dictionary selector used by the
  existing shared RPC adapter, avoiding per-handler parsing in the three mail
  handlers. Rejects absent/malformed dictionaries, missing own entries, empty or
  whitespace/control selectors, non-string values and non-secret key shapes.
- `_shared/mail.ts`: import plus databaseRpc key/header selection only. Existing
  fetch transport, URL binding, timeout, body, status mapping and no-retry policy
  remain. Templates, raw-body/BOM fix, delivery logic and accepted tests untouched.
- `_shared/mail_keys.test.ts`: 33 passing cases with synthetic credentials and
  injected HTTP. No new package, SDK, SQL or financial edits.

## Exact Configuration

`CLEANSTREAM_MAIL_SECRET_KEY_NAME` is an optional server-side **key name**, not a
key value. Example proposed name: `cleanstream-mail-prod` (not created here).
When present, privileged RPCs select that exact own property from the runtime's
JSON dictionary `SUPABASE_SECRET_KEYS`. The selected value must have nonempty
`sb_secret_` opaque-token shape. Code sends it only in `apikey`, with no synthetic
Authorization bearer. No `default` lookup, legacy fallback or cached selection.

Missing/malformed selection returns sanitized `mail_unavailable` (503) before
HTTP. A revoked key still in the dictionary may return HTTP 401/403; that remains
a failure with no retry or alternate credentials. An empty selector is invalid,
not the opt-out switch. Re-evaluate on every RPC so removed entries fail closed.

Applies to `mail-delivery` claims/prepare/finish, `mail-webhook` event recording,
and `newsletter` capability RPCs through their existing shared adapter. This does
not change their inbound worker secret, webhook signature, capability checks,
gateway configuration or sending gates. Keys remain project-privileged, not
least-privilege just because named.

Authenticated newsletter RPCs retain `SUPABASE_ANON_KEY` on `apikey` and the
exact caller Authorization bearer; they do not read the secret selector/dictionary.
Named publishable migration is outside this bounded task.

## Staging And Rollback

With the selector **absent**, the adapter preserves `SUPABASE_SERVICE_ROLE_KEY`
and its legacy bearer exactly. Presence enables named mode; even missing/revoked
entries cannot silently restore legacy behavior. Do not overwrite reserved
runtime dictionaries or put any secret into public app configuration.

After separate approval and provisioning verification, enable the selector for
the mail component while keeping legacy credentials available for an approved
overlap. Hosted header/dictionary behavior still needs staged verification;
synthetic tests cannot prove deployment configuration or key ownership.
Rollback is an explicit operator action: remove the selector entirely (not set
it empty), or restore the accepted previous adapter artifact, only while legacy
credentials remain authorized/active. Never roll back to a known compromised
key, clear outbox fingerprints/event keys, or replay business actions/sends.

Official contracts checked 2026-09-30: [runtime dictionaries](https://supabase.com/docs/guides/functions/secrets),
[key formats and privileges](https://supabase.com/docs/guides/api/api-keys),
[header separation](https://supabase.com/docs/guides/functions/auth-headers).

## Completed Checks

Ran serially after composer grant, in `/Users/jamaki604/CleanStreamProjects/.campaign-work/email`:

```sh
DENO_NO_UPDATE_CHECK=1 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --node-modules-dir=none supabase/functions/_shared/mail_keys.test.ts supabase/functions/_shared/mail.independent-qa.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno fmt --check supabase/functions/_shared/mail.ts supabase/functions/_shared/mail_keys.ts supabase/functions/_shared/mail_keys.test.ts
DENO_NO_UPDATE_CHECK=1 DENO_V8_FLAGS=--max-old-space-size=768 /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno lint supabase/functions/_shared/mail.ts supabase/functions/_shared/mail_keys.ts supabase/functions/_shared/mail_keys.test.ts
```

Completed: 33 new + 8 unchanged independent cases. Initial lint rejected the
intentional control-character regex; replaced it with an equivalent character
check and added embedded NUL/DEL assertions within the existing case count.
The relevant 41 cases passed again after that change; formatter then normalized
wrapping, and final fmt/lint both passed. No broad 94-case/BOM/template rerun,
missing imports or installations. Local code readiness is separate from existing
sender/activation blockers; mail stays disabled until separately approved.
