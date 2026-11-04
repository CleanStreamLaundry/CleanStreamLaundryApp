# Deletion Admission Follow-up

Independent QA accepted: 92 PASS (27 capacity + 65 deletion), both typechecks pass, session 70839 exited 0, receipt `1140e2`. QA confirmed all four active files byte-equal the frozen sources below. No network/provider/PG actions; ignored npm:supabase lifecycle-script warning only, with no installation or scripts enabled. Author made no runtime, cloud, migration, grant, or active-repository changes. Accepted Owner5 bytes and prior 43 PG/96 Deno evidence remain unchanged. This batch does not enable deletion or permanent cleanup.

## Exact Scope

Composer-hosted update: `delete-account` ACTIVE v30, verify_jwt=true, deployment `585196`; empty unauthenticated POST401 verified `8d1fd3`. Its matching Owner SQL `a66ff411` is installed (`a89d46`), postflight accepted (`fbe628`) and exact history recorded (`01632b`); deletion/bootstrap ACLs remain held. The Cortina post-capacity source is integrated and QA accepted but **not deployed**, pending the public return reader. No role grants, balances or customer records changed. No author reruns or remote actions.

Root: `/Users/jamaki604/CleanStreamProjects/.campaign-work/account-cleanup/deletion-admission-followup`.

| Integration file | SHA256 |
| --- | --- |
| `supabase/functions/cortina-vend/logic.ts` | `9357f7aa2bf89ab29fefd186caf26cd7beae65c06c37fac3c5ba518035c756fe` |
| `supabase/functions/cortina-vend/request_limits.test.ts` | `322f9152d4ea14764d8683a57f10e96eaf94a187e9ac7c36046082e6260c02db` |
| `supabase/functions/delete-account/logic.ts` | `bb7db0313a18d66d1bd41fcdf606d5d65d12fe2efe6da5ae42ea87737b84aa96` |
| `supabase/functions/delete-account/logic.test.ts` | `e4d26ed646e825c98d407cb9eb995879fa55a6fbe274a40354a0ffcbb7b0d043` |

Original active-source hashes are in `baseline.sha256`. QA-only `qa.import-map.json` SHA256: `a632792a79edcf275873efd206394926b9702f30597485ede721c52d5c333b12`. It reuses active helpers at canonical URLs, avoiding duplicate error-class identity; it is not a deployment artifact.

## Change and Preservation

- Cortina line 121 repeats the existing captured-caller admission check after the capacity await, before either Stripe creation branch. Rejection remains outside provider compensation and leaves the pending draft unchanged. Anonymous card, nonpending/funded replay, quote/status, confirmation, wallet, callbacks and refunds are unchanged. An already-dispatched provider operation cannot be undone by admission.
- Delete-account line 101 recognizes only `PT409` with exact message `owner_last_required`, returning sanitized HTTP409. All other conflicts retain the existing HTTP503 status-led uncertain-outcome response. No automatic retry or pending-deletion success is manufactured.
- Reuses existing admission/error helpers and fixtures. No new abstraction, dependency, provider transport, or removals.

## QA Handoff

Completed independent QA: 92 cases passed, Cortina capacity 27 (24 retained + 3 new), deletion logic 65 (61 retained + 4 new). New cases cover delayed capacity restriction on app/web, eligible dual-channel creation, exact last-Owner rejection, and three unknown/error-code mismatch combinations.

Accepted command run from this root, one process; retained for reproducibility, not a rerun request:

```sh
/Users/jamaki604/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno test --cached-only --no-config --lock=/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/deno.lock --frozen --import-map=qa.import-map.json --v8-flags=--max-old-space-size=768 --allow-env supabase/functions/cortina-vend/request_limits.test.ts supabase/functions/delete-account/logic.test.ts
```

Cached dependencies only; no provider/network permission or cache blocker. No PG/Owner/older-suite rerun requested. Existing capacity tests retain fake-HTTP SDK coverage. Hosted deployment and deletion activation remain Composer-owned and outside this source batch.
