# Admin Permissions

## Local Contract

The local source batch is not deployed. Focused local runtime verification
passed in the composer-assigned serial slot. No real account receives a role
in this migration.

`profiles.roles` retains `User`, `Admin`, and `Owner`. Private
`staff_portal_access` selects `Manager` or `Maintenance` for an Admin; an absent
row means Manager. Owner always has effective portal role Owner. User metadata
and request-supplied roles never authorize access.

Identity retains `role: 'Owner' | 'Admin'` and adds
`portalRole: 'Owner' | 'Manager' | 'Maintenance'`. Team rows retain raw `role`
and add `portal_role`. Canonical current-session, TOTP/MFA, email, lifecycle,
and post-wait admission remain authoritative. The context recheck now also
compares the effective portal role.

| Capability | Owner | Manager | Maintenance |
| --- | --- | --- | --- |
| Location scope | All locations | Explicit memberships | Explicit memberships |
| Operational overview | Yes | Yes, no financial fields | No |
| Machine inventory/status | Full | Operational fields only | No |
| Machine availability | Yes | Existing versioned toggle | No |
| Maintenance queue/history/photos/notes/planning | Yes | Assigned locations | Assigned locations |
| Team | Manage | Read-only, assigned locations | No |
| Machine and maintenance exports | Yes | Operational fields only | Maintenance only |
| Revenue, transactions, credits/refunds, wallets | Yes | No | No |
| Rates/payment config, create/delete, audit, security recovery | Yes | No | No |
| Staff/Owner roles and location-access changes | Yes | No | No |

Manager `overview` returns exactly `locations`, `machines`, `openMaintenance`,
and `updatedAt`. Financial totals, charts, credit counts, and reporting metadata
are absent, not zeroed. Manager `machines` and machine exports use explicit
operational field allowlists; they omit `Price`, rate references, Cortina
configuration, terminal IDs, payment enablement/review state, and environment.
Hidden fields are excluded before export filtering/search. Team exports remain
Owner-only; Manager team access is read-only in the portal.

Normal customer self-reads and public customer-displayed machine prices are not
removed. Owner-all scope does not create synthetic location memberships.
Additional-Owner grants/removals and last-Owner safeguards are unchanged.

## Staff Changes

Owner-only Edge actions use the captured caller bearer and
`admin_staff_role_management(action, payload)`:

```json
{
  "action": "setStaffRole",
  "userId": "target-uuid",
  "portalRole": "Maintenance",
  "expectedPortalRole": "Manager",
  "requestId": "request-uuid",
  "note": "Approved maintenance access"
}
```

Only current Admin targets can change between Manager and Maintenance. This
action cannot promote customers, grant Owner, change oneself, or change location
membership. The expected role protects stale editors. It shares the existing
role advisory lock and Auth/profile lock order, rechecks admission after waits,
and writes an immutable `staff_role_management` / `role_change` audit receipt.

The result is `{ userId, role: 'Admin', portalRole, requestId, changed }`.
An identical request replays its original receipt without reapplying a role;
reuse with another caller or payload is a conflict. After an unknown outcome,
use `{ action: 'staffRoleStatus', requestId }`. The caller-only response is
`{ state: 'completed', result }` or `{ state: 'not_found' }`. A missing receipt is
not authority for an automatic retry. Refresh identity/team after completion.
Conflicts are `staff_role_state_changed`, `staff_role_request_conflict`, and
`staff_role_target_ineligible` (HTTP 409).

`invite` accepts optional `portalRole`, default Manager. The existing audited
onboarding request freezes the selection through authorize/complete and returns
`portal_role` in each receipt. An existing Admin must already have the selected
role; use `setStaffRole` first to change it. Resend preserves the current role.
The SQL RPC gains final optional `target_portal_role text default 'Manager'`;
the old five-argument signature is replaced, not left as a bypass overload.

## Enforcement

Edge action checks provide early denial; database checks remain authoritative
on every request. Actor-taking and renamed implementation RPCs remain revoked
from public, anon, authenticated, and service_role. The existing financial
`is_admin_or_owner()` predicate now requires canonical Owner admission. Direct
transaction/refund/config/rate and vend-record policies exclude non-Owner
cross-customer finance. Existing self-only wallet/profile restrictions remain.
Credit resolution and the legacy deleted-wallet complaint action are Owner-only.
Customer MFA recovery and wallet-management wrappers retain their Owner gates.

Maintenance RLS and existing private Storage attachment policies retain
admission-aware, location-scoped access for both staff roles. No public bucket,
signed-URL fallback, service credential read, Storage policy deployment, or
callback/reconciliation mutation is introduced. The migration updates the
existing attachment predicate dependency without changing Storage ownership.

The migration asserts the expected legacy location-query snippets before
replacing only those projections with shared Owner-all scope. Unexpected
installed bodies abort the transaction and require review, not a weaker fallback.
Deploy only after explicit approval and coordinated database/Edge/web rollout.
Old web financial routes will receive denials for Admins. New invitations fail
closed against old SQL receipts without a portal role.

## Focused Verification

Verified locally on October 4: DB 18/18 reported tests (17 child checks plus the
parent), exit 0; Edge 186/186 with typechecking, exit 0. No skipped/cancelled DB
tests. All owned processes exited; the PostgreSQL cluster stopped and its
disposable directory was removed. The runtime slot was released after Edge exit.

The initial sandbox attempt could not allocate PostgreSQL shared memory; the
approved local escalation used only a private Unix socket. Fixture-only fixes
matched the existing Owner installation's held deletion ACL and supplied missing
legacy SELECT grants so raw-read assertions exercised RLS rather than failing
at table privileges. No production guards or migration logic changed during QA.
The handoff's account-cleanup cache lacked the pinned std module (zero Edge tests
ran in that attempt); the existing default Deno cache completed the suite with
`--cached-only`, without downloads or dependency changes.

Run serially from the app root, only after the composer grants a runtime slot.
The DB harness creates and cleans up its own
PostgreSQL 17 cluster on a private Unix socket; it never uses a linked database.

```sh
PG_BIN=/opt/homebrew/opt/postgresql@17/bin node --max-old-space-size=1024 --test --test-concurrency=1 scripts/admin-role-privacy.test.mjs
```

Focused Edge suite, using the existing cached Deno runtime/dependencies:

```sh
DENO_DIR=/Users/jamaki604/Library/Caches/deno /Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --v8-flags=--max-old-space-size=768 --cached-only --frozen --lock=deno.lock --node-modules-dir=none --no-prompt --allow-env=CLEAN_STREAM_WEB_ORIGIN supabase/functions/admin-portal
```

The new SQL suite covers direct RPC denials, RLS read-only transactions, Storage,
machine/export private fields, customer self-reads, Owner-all scope, invitation
binding, immutable receipts, concurrent replay, and post-lock authority changes.
Existing `scripts/admin-authorization.test.mjs`, `scripts/admin-onboarding.test.mjs`,
and `scripts/owner-management.test.mjs` remain unchanged baseline harnesses; they
do not install this new migration. Their retained evidence is not a substitute
for the new composed suite. These passes are local synthetic evidence, not a
deployed-state or real-account acceptance claim.
