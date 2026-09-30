import assert from "node:assert/strict";
import {
  executeTopupRefund,
  handleVoluntaryTopupRefund,
  type ProviderRefund,
  type RefundOperation,
  type TopupRefundDependencies,
} from "./voluntary_topup_refund.ts";

const id = "00000000-0000-4000-8000-000000000123";
function setup() {
  const op: RefundOperation = {
    id,
    intent: "pi_independent",
    amount: 2000,
    livemode: false,
    refund_id: "re_original",
    idempotency_key: `voluntary-topup-v1:${id}`,
    may_create: false,
  };
  const original: ProviderRefund = {
    id: "re_original",
    payment_intent: op.intent,
    amount: op.amount,
    currency: "usd",
    status: "pending",
    metadata: { voluntary_topup_refund_id: id },
  };
  const calls: string[] = [];
  let released = false;
  const deps: TopupRefundDependencies = {
    authenticate: () => {
      calls.push("authenticate");
      return Promise.resolve();
    },
    callerRpc: () => Promise.resolve({ id, status: "pending" }),
    prepare: () => Promise.resolve({ ...op }),
    payment: () =>
      Promise.resolve({
        id: op.intent,
        status: "succeeded",
        amount_received: 2000,
        currency: "usd",
        livemode: false,
      }),
    refunds: () => {
      calls.push("list");
      return Promise.resolve([{ ...original }]);
    },
    retrieve: () => {
      calls.push("retrieve");
      return Promise.resolve({ ...original });
    },
    create: () => {
      calls.push("create");
      return Promise.reject(new Error("Unexpected POST"));
    },
    reconcile: (_, refund) => {
      calls.push(`reconcile:${refund.status}`);
      released = ["failed", "canceled"].includes(refund.status!);
      return Promise.resolve({ id, status: refund.status });
    },
  };
  return { op, original, calls, deps, released: () => released };
}

for (const terminal of ["failed", "canceled"]) {
  Deno.test(`REGRESSION: known ${terminal} refund must not release funds when another full refund succeeded`, async () => {
    const f = setup();
    f.original.status = terminal;
    const external = {
      ...f.original,
      id: "re_external",
      status: "succeeded",
      metadata: {},
    };
    f.deps.refunds = () => {
      f.calls.push("list");
      return Promise.resolve([f.original, external]);
    };
    const response = await handleVoluntaryTopupRefund(
      new Request("https://local.invalid/refund", {
        method: "POST",
        body: JSON.stringify({ action: "reconcile", id }),
      }),
      f.deps,
    );
    assert.equal(
      f.released(),
      false,
      `reservation released despite external success; HTTP ${response.status}; calls=${f.calls}`,
    );
    assert.equal(f.calls.includes("create"), false);
  });
}

Deno.test("unbound failed refund plus external success remains reserved", async () => {
  const f = setup();
  f.op.refund_id = null;
  f.original.status = "failed";
  f.deps.refunds = () =>
    Promise.resolve([f.original, {
      ...f.original,
      id: "re_external",
      status: "succeeded",
      metadata: {},
    }]);
  await assert.rejects(
    () => executeTopupRefund(id, f.deps),
    /Conflicting refunds/,
  );
  assert.equal(f.released(), false);
  assert.equal(f.calls.includes("create"), false);
});

for (const status of ["pending", "requires_action", "succeeded"]) {
  Deno.test(`known ${status} remains bound to original provider identity without another create`, async () => {
    const f = setup();
    f.original.status = status;
    const result = await executeTopupRefund(id, f.deps) as { status: string };
    assert.equal(result.status, status);
    assert.equal(f.released(), false);
    assert.equal(f.calls.includes("create"), false);
  });
}

for (
  const change of [
    { currency: "eur" },
    { amount_received: 1999 },
    { livemode: true },
    { id: "pi_other" },
    { status: "requires_capture" },
  ]
) {
  Deno.test(`current payment mismatch blocks provider dispatch: ${JSON.stringify(change)}`, async () => {
    const f = setup();
    f.deps.payment = () =>
      Promise.resolve({
        id: f.op.intent,
        status: "succeeded",
        amount_received: 2000,
        currency: "usd",
        livemode: false,
        ...change,
      });
    await assert.rejects(
      () => executeTopupRefund(id, f.deps),
      /Payment mismatch/,
    );
    assert.deepEqual(f.calls, []);
    assert.equal(f.released(), false);
  });
}

Deno.test("unknown outcome retry uses the exact same provider key and reconciles once", async () => {
  const f = setup();
  f.op.refund_id = null;
  f.op.may_create = true;
  f.deps.refunds = () => Promise.resolve([]);
  const keys: string[] = [];
  f.deps.create = (op) => {
    keys.push(op.idempotency_key);
    if (keys.length === 1) return Promise.reject(Error("response lost"));
    return Promise.resolve({ ...f.original, status: "succeeded" });
  };
  await assert.rejects(() => executeTopupRefund(id, f.deps), /response lost/);
  assert.equal(f.released(), false);
  await executeTopupRefund(id, f.deps);
  assert.deepEqual(keys, [
    `voluntary-topup-v1:${id}`,
    `voluntary-topup-v1:${id}`,
  ]);
  assert.deepEqual(f.calls, ["reconcile:succeeded"]);
});

Deno.test("expired uncertainty with empty provider evidence cannot create or release", async () => {
  const f = setup();
  f.op.refund_id = null;
  f.op.may_create = false;
  f.deps.refunds = () => Promise.resolve([]);
  await assert.rejects(
    () => executeTopupRefund(id, f.deps),
    /Manual reconciliation required/,
  );
  assert.deepEqual(f.calls, []);
  assert.equal(f.released(), false);
});

Deno.test("provider success then acknowledgement loss can only retry reconciliation", async () => {
  const f = setup();
  f.original.status = "succeeded";
  let reconciliations = 0;
  f.deps.reconcile = () => {
    if (++reconciliations === 1) {
      return Promise.reject(Error("database response lost"));
    }
    return Promise.resolve({ id, status: "succeeded" });
  };
  await assert.rejects(() => executeTopupRefund(id, f.deps));
  await executeTopupRefund(id, f.deps);
  assert.equal(reconciliations, 2);
  assert.equal(f.calls.includes("create"), false);
  assert.equal(f.released(), false);
});
