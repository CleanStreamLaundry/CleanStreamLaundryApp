import assert from "node:assert/strict";
import {
  handleVoluntaryTopupRefund,
  type ProviderRefund,
  type RefundOperation,
  type TopupRefundDependencies,
} from "./voluntary_topup_refund.ts";

const id = "00000000-0000-4000-8000-000000000123";
function setup(status: string) {
  const op: RefundOperation = {
    id,
    intent: "pi_release",
    amount: 2000,
    livemode: false,
    refund_id: "re_bound",
    idempotency_key: `voluntary-topup-v1:${id}`,
    may_create: false,
  };
  const refund: ProviderRefund = {
    id: "re_bound",
    payment_intent: op.intent,
    amount: op.amount,
    currency: "usd",
    status,
    metadata: { voluntary_topup_refund_id: id },
  };
  const calls: string[] = [];
  const deps: TopupRefundDependencies = {
    authenticate: () => Promise.resolve(),
    callerRpc: () => Promise.resolve({ id, status: "pending" }),
    prepare: () => Promise.resolve(op),
    payment: () =>
      Promise.resolve({
        id: op.intent,
        status: "succeeded",
        amount_received: op.amount,
        currency: "usd",
        livemode: false,
      }),
    retrieve: () => {
      calls.push("retrieve");
      return Promise.resolve({ ...refund });
    },
    refunds: () => {
      calls.push("list");
      return Promise.resolve([{ ...refund }]);
    },
    create: () => {
      calls.push("create");
      return Promise.reject(new Error("Unexpected dispatch"));
    },
    reconcile: (_, result) => {
      calls.push("reconcile");
      return Promise.resolve({ id, status: result.status });
    },
  };
  const run = () =>
    handleVoluntaryTopupRefund(
      new Request("https://synthetic.invalid/refund", {
        method: "POST",
        body: JSON.stringify({ action: "reconcile", id }),
      }),
      deps,
    );
  return { deps, refund, calls, run };
}

for (const terminal of ["failed", "canceled"]) {
  Deno.test(`bound ${terminal}: sole agreeing terminal history permits release`, async () => {
    const f = setup(terminal);
    const response = await f.run();
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { data: { id, status: terminal } });
    assert.deepEqual(f.calls, ["retrieve", "list", "reconcile"]);
  });

  const histories: Record<string, (r: ProviderRefund) => ProviderRefund[]> = {
    empty: () => [],
    missing_bound: (r) => [{ ...r, id: "re_external" }],
    duplicate_bound: (r) => [r, { ...r }],
    partial_bound: (r) => [{ ...r, amount: 1000 }],
    wrong_intent: (r) => [{ ...r, payment_intent: "pi_other" }],
    wrong_currency: (r) => [{ ...r, currency: "eur" }],
    listed_pending: (r) => [{ ...r, status: "pending" }],
    listed_succeeded: (r) => [{ ...r, status: "succeeded" }],
    listed_unknown: (r) => [{ ...r, status: null }],
    terminal_disagreement: (r) => [{
      ...r,
      status: terminal === "failed" ? "canceled" : "failed",
    }],
    replacement_succeeded: (
      r,
    ) => [r, { ...r, id: "re_other", status: "succeeded" }],
    replacement_pending: (
      r,
    ) => [r, { ...r, id: "re_other", status: "pending" }],
    replacement_requires_action: (
      r,
    ) => [r, { ...r, id: "re_other", status: "requires_action" }],
    replacement_partial: (
      r,
    ) => [r, { ...r, id: "re_other", amount: 1000, status: "succeeded" }],
    other_failed: (r) => [r, { ...r, id: "re_other", status: "failed" }],
    other_canceled: (r) => [r, { ...r, id: "re_other", status: "canceled" }],
  };
  for (const [name, history] of Object.entries(histories)) {
    Deno.test(`bound ${terminal}: ${name} retains reservation`, async () => {
      const f = setup(terminal);
      f.deps.refunds = () => {
        f.calls.push("list");
        return Promise.resolve(history(f.refund));
      };
      const response = await f.run();
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), {
        error: "refund_outcome_unknown",
        reconciliation_required: true,
      });
      assert.deepEqual(f.calls, ["retrieve", "list"]);
    });
  }

  Deno.test(`bound ${terminal}: history read failure retains reservation; later clean evidence reconciles once`, async () => {
    const f = setup(terminal), originalList = f.deps.refunds;
    f.deps.refunds = () => {
      f.calls.push("list_error");
      return Promise.reject(new Error("Synthetic incomplete pagination"));
    };
    assert.equal((await f.run()).status, 503);
    assert.deepEqual(f.calls, ["retrieve", "list_error"]);
    f.deps.refunds = originalList;
    assert.equal((await f.run()).status, 200);
    assert.deepEqual(f.calls, [
      "retrieve",
      "list_error",
      "retrieve",
      "list",
      "reconcile",
    ]);
  });
}
