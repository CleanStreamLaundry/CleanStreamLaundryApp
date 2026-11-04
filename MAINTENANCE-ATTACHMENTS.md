# Maintenance Attachment Access

TEST SLOT RELEASED; **64 PostgreSQL cases passed + parent = 65 runner passes**,
exit 0, no failures/skips/cancellations. Server stopped and owned temporary root
removed. This verifies the local metadata contract, not deployed privacy. The
eight cleanup code/test files remain frozen; no cleanup tests were rerun.

## Owned Paths

Only writable root: `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup`.
Exact maintenance ownership under that root:

- `supabase/migrations/20260930165320_maintenance_attachment_access.sql`
  (created with the installed Supabase CLI).
- `supabase/storage/maintenance_attachment_policies.sql` (separate owner-only
  activation artifact, deliberately outside the normal migration runner).
- `scripts/maintenance-attachment-access.test.mjs` and this note.

No existing maintenance function, migration, client, shared actor, route, DI,
payment or mail file changed. No bucket/object/legacy URL mutation, new table,
Edge service-key reader, signed-URL issuer, dependency, or media framework.
Lane documentation ownership also includes root `HANDOFF.md` and
`CLEANUP-ACTIVATION.md`. All active app/web checkouts are read-only inputs. The
eight accepted cleanup files are frozen; their integration is composer's work.

## Current Source And Wire

Read-only sources: active app `docs/supabase.md`, `docs/operations.md`,
`lib/features/maintenance_request/controller.dart`; active web
`src/supabase/repositories/MaintenanceRepository.ts`,
`src/components/MaintenanceDashboardPage.tsx`, `src/admin/MaintenancePage.tsx`;
existing `maintenance-request/logic.ts` and maintenance authorization migration.

- App still uploads to `maintenance-images`, `requests/<filename>`, without
  upsert, and sends a public URL to maintenance-request. The existing Edge parser
  validates that URL locally and turns it into `{name}`; SQL derives the exact
  `{bucket,id,name,version}` reference. This compatibility path is unchanged.
- Both web readers still use legacy `image_data` URLs. Neither invokes the new
  contract. Existing URLs and rows are neither rewritten nor backfilled.
- New authenticated RPC: `get_maintenance_attachment({p_maint_id: "123"})` returns
  `{"maint_id":"123","attachment":{"bucket":"maintenance-images","id":"<uuid>","name":"requests/<filename>","version":null}}`.
  IDs remain decimal text through the full bigint range. Version may be text.
- PT400 invalid ID; PT401 invalid/revoked session; PT403 restricted actor;
  PT404 missing, unauthorized, legacy-only or stale attachment; PT503 sanitized
  lookup failure. No caller-selected bucket, object, URL, or owner is accepted.
- A future reader uses its captured caller JWT for this RPC and authenticated
  Storage download. No public URL fallback or service-key fallback. The
  descriptor is not an authorization capability: Storage must authorize again.

## Reuse And Boundaries

Private predicates reuse `account_access_allowed()` and
`maintenance_record_access(uuid,bigint)`: eligible customers see their own
reports; Admin/Owner require explicit location membership for others' located
reports; the existing Owner access to unassigned reports is preserved. Duplicate
address text never grants scope. Support before terms acceptance stays allowed.
Pending-deletion actors, expired recovery windows, old restored sessions, missing
MFA and revoked sessions follow the existing evaluator. Active staff support
access does not invent a new rule erasing records of pending-deletion customers.

Reads require exact report/object owner, ID, bucket, name and nullable version;
archived, deleted-marker, missing-owner and ambiguous-current objects deny.
Unattached uploads are not readable as report attachments. New uploads keep
existing safe names and require JWT owner plus canonical eligibility. Restrictive
Storage policies compose with permissive rules, prevent client update/delete or
moving another bucket's object into this bucket, and leave other buckets alone.
No existing code is replaced or removed; no duplicate actor evaluator is added.

## Deployment Gates

Compatibility is staged, not assumed: applying only the additive migration does
not replace any existing function, table, policy, bucket flag or client wire.
Legacy uploads, URL generation, report creation and public reads therefore keep
their existing paths. No migration auto-includes the separate policy script.
The restrictive-policy script intentionally denies previously possible unowned,
unsafe, restricted-account uploads and cross-account/location authenticated
reads. Existing `requests/<filename>` uploads with verified owner metadata remain
the intended supported contract, **not yet proven against hosted Storage HTTP**.
Old public readers remain public until a separately approved privacy transition.
Thus this is not a claim that arbitrary old clients survive policy deployment:
inventory/test them and coordinate rollout before executing that artifact.

1. Composer reviews additive RPC/helper names and migration order after existing
   maintenance, membership and lifecycle changes. The SQL migration only adds
   functions/ACLs; it does not alter Storage policies or bucket settings.
2. Recorded Storage owner is `supabase_storage_admin`; `postgres` cannot assume
   it. Policy SQL deliberately aborts under postgres. A separately supported,
   approved owner-authorized execution path is required, not new memberships,
   owner changes or a privileged workaround. The app migration grants that owner
   private-schema USAGE and EXECUTE on only the two new predicates for policy
   binding. Actual hosted ACL/catalog compatibility remains unverified.
3. **Public bucket reads bypass these policies.** No privacy claim is valid until
   paired app/web readers, old clients and historic links have a reviewed rollout
   and an explicitly authorized bucket-privacy transition. No such transition
   or deployment was performed or scheduled.
4. **SELECT also underlies Storage signing capabilities.** This candidate does
   not issue signed URLs, but SQL RLS alone cannot guarantee prompt revocation of
   previously issued URLs, public URLs or already downloaded bytes. Verify the
   supported hosted signing controls and approve the delivery/revocation contract
   before activation; do not advertise immediate end-to-end revocation. Ordinary
   RLS reads use statement snapshots, not a lock spanning remote byte delivery.
5. Test actual Storage HTTP upload/download/signing/version/cache behavior in an
   authorized isolated environment before release. Metadata fixtures do not
   prove service behavior. Owner-authorized activation, frontend integration,
   legacy-object handling and hosted policy deployment remain uncompleted work.

## Verification

One process, Node24 heap 1024 MiB; existing disposable PG17.11 harness, synthetic
database only, no listener, installation, cache copying or host links. The harness
used the previously authorized narrow bottle relocation and teardown. Executed
once under composer's explicit slot grant with approved local shared-memory
access:

```sh
PG_BIN=/opt/homebrew/Cellar/postgresql@17/17.11/bin /Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=1024 --test --test-concurrency=1 scripts/maintenance-attachment-access.test.mjs
```

Ran from `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup`.
Cases cover ACLs/ownership, original-row/function preservation, actual canonical
customer/staff/location/lifecycle behavior, restore-session freshness, metadata
version drift, malformed references, upload ownership, permissive-policy bypass
attempts and unrelated-bucket compatibility. No Deno/SDK changes to rerun.

PostgreSQL reported **17.11 (Homebrew)**; private Unix socket, empty
`listen_addresses`. Completed 64 child cases and the parent: **65 passes, 0
failures, 0 skipped, 0 cancelled**, exit **0**, duration **3500.597 ms**. No code
changes or retries were needed. The harness confirmed server stop and removal
of `/private/tmp/cleanstream-wallet-locking-policy-pg-vdt4kl`, including relocated
executables, links, database and socket. The runner exited; no lane process remains.
Slot released for composer's public-route checks. No provider calls or browser
activity; current vendor documentation/hosted verification remain gaps.
