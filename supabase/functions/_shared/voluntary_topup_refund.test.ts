import {
  executeTopupRefund,
  handleVoluntaryTopupRefund,
  type ProviderRefund,
  type RefundOperation,
  type TopupRefundDependencies,
  TopupRefundError,
} from "./voluntary_topup_refund.ts";
import {
  handleStripeWebhook,
  type StripeEvent,
} from "../stripeWebhook/logic.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
async function rejects(fn: () => Promise<unknown>) {
  let failed = false;
  try {
    await fn();
  } catch {
    failed = true;
  }
  equal(failed, true);
}
const id = "00000000-0000-4000-8000-0000000000ab";
function setup() {
  const op: RefundOperation = {
    id,
    intent: "pi_test",
    amount: 2000,
    livemode: false,
    refund_id: null,
    idempotency_key: `voluntary-topup-v1:${id}`,
    may_create: true,
  };
  const refund: ProviderRefund = {
    id: "re_test",
    payment_intent: "pi_test",
    amount: 2000,
    currency: "usd",
    status: "succeeded",
    metadata: { voluntary_topup_refund_id: id },
  };
  const calls: string[] = [];
  const deps: TopupRefundDependencies = {
    authenticate: () => {
      calls.push("auth");
      return Promise.resolve();
    },
    callerRpc: (name) => {
      calls.push(name);
      return Promise.resolve({ id, status: "approved" });
    },
    prepare: () => {
      calls.push("prepare");
      return Promise.resolve(op);
    },
    payment: () =>
      Promise.resolve({
        id: "pi_test",
        status: "succeeded",
        amount_received: 2000,
        currency: "usd",
        livemode: false,
      }),
    refunds: () => {
      calls.push("list");
      return Promise.resolve([]);
    },
    retrieve: () => {
      calls.push("retrieve");
      return Promise.resolve(refund);
    },
    create: () => {
      calls.push("create");
      return Promise.resolve(refund);
    },
    reconcile: (_, r) => {
      calls.push("reconcile");
      return Promise.resolve({ id, status: r.status });
    },
  };
  return { op, refund, calls, deps };
}
const request = (body: unknown) =>
  new Request("https://local.invalid/refunds", {
    method: "POST",
    body: JSON.stringify(body),
  });

Deno.test("full refund only after caller authorization and provider confirmation", async () => {
  const { deps, calls } = setup();
  const response = await handleVoluntaryTopupRefund(
    request({ action: "approve", id }),
    deps,
  );
  equal(response.status, 200);
  equal(await response.json(), { data: { id, status: "succeeded" } });
  equal(calls, [
    "auth",
    "review_voluntary_topup_refund",
    "prepare",
    "list",
    "create",
    "reconcile",
  ]);
});
Deno.test("UUID case is normalized before review and dispatch", async () => {
  const { deps } = setup();
  const response = await handleVoluntaryTopupRefund(
    request({ action: "approve", id: id.toUpperCase() }),
    deps,
  );
  equal(response.status, 200);
  equal(await response.json(), { data: { id, status: "succeeded" } });
});
for (const status of ["pending", "requires_action"]) {
  Deno.test(`provider ${status} is not success`, async () => {
    const { deps, refund } = setup();
    refund.status = status;
    deps.reconcile = () => Promise.resolve({ id, status: "pending" });
    equal(
      (await handleVoluntaryTopupRefund(
        request({ action: "approve", id }),
        deps,
      )).status,
      202,
    );
  });
}
for (const status of ["failed", "canceled"]) {
  Deno.test(`known provider ${status} reconciles`, async () => {
    const { deps, refund, calls } = setup();
    refund.status = status;
    equal(await executeTopupRefund(id, deps), { id, status });
    equal(calls.at(-1), "reconcile");
  });
}
Deno.test("network uncertainty returns unknown without attempting release", async () => {
  const { deps, calls } = setup();
  deps.create = () => {
    calls.push("create");
    return Promise.reject(new Error("timeout secret"));
  };
  const response = await handleVoluntaryTopupRefund(
    request({ action: "approve", id }),
    deps,
  );
  equal(response.status, 503);
  equal(await response.json(), {
    error: "refund_outcome_unknown",
    reconciliation_required: true,
  });
  equal(calls.includes("reconcile"), false);
});
Deno.test("provider success then DB failure is recovered by list and retrieve, no second create", async () => {
  const { deps, refund, calls } = setup();
  deps.reconcile = () => {
    return Promise.reject(new Error("db down"));
  };
  await rejects(() => executeTopupRefund(id, deps));
  deps.refunds = () => Promise.resolve([refund]);
  deps.reconcile = () => Promise.resolve({ id, status: "succeeded" });
  equal(await executeTopupRefund(id, deps), { id, status: "succeeded" });
  equal(calls.filter((c) => c === "create").length, 1);
});
Deno.test("unknown after 23h refuses a new POST when listing has no evidence", async () => {
  const { deps, op, calls } = setup();
  op.may_create = false;
  await rejects(() => executeTopupRefund(id, deps));
  equal(calls.includes("create"), false);
});
Deno.test("old unknown with matching refund still reconciles", async () => {
  const { deps, op, refund, calls } = setup();
  op.may_create = false;
  deps.refunds = () => Promise.resolve([refund]);
  await executeTopupRefund(id, deps);
  equal(calls.includes("create"), false);
  equal(calls.includes("reconcile"), true);
});
Deno.test("known refund is retrieved, never blindly recreated", async () => {
  const { deps, op, calls } = setup();
  op.refund_id = "re_test";
  await executeTopupRefund(id, deps);
  equal(calls, ["prepare", "retrieve", "reconcile"]);
});
for (
  const change of [
    { amount: 1000 },
    { currency: "eur" },
    { payment_intent: "pi_other" },
    { status: "bogus" },
    { id: "wrong" },
  ]
) {
  Deno.test(`provider mismatch ${JSON.stringify(change)} fails closed`, async () => {
    const { deps, refund, calls } = setup();
    Object.assign(refund, change);
    await rejects(() => executeTopupRefund(id, deps));
    equal(calls.includes("reconcile"), false);
  });
}
for (
  const change of [{ amount_received: 1999 }, { currency: "eur" }, {
    livemode: true,
  }, { status: "processing" }]
) {
  Deno.test(`payment mismatch ${JSON.stringify(change)} never refunds`, async () => {
    const { deps, calls } = setup();
    const original = deps.payment;
    deps.payment = async (id) => ({ ...await original(id), ...change });
    await rejects(() => executeTopupRefund(id, deps));
    equal(calls.includes("create"), false);
  });
}
Deno.test("full external refund reconciles without another payout", async () => {
  const { deps, refund, calls } = setup();
  refund.metadata = {};
  deps.refunds = () => Promise.resolve([refund]);
  await executeTopupRefund(id, deps);
  equal(calls.includes("create"), false);
});
Deno.test("external partial refund requires manual reconciliation, no partial voluntary payout", async () => {
  const { deps, refund, calls } = setup();
  refund.metadata = {};
  refund.amount = 1000;
  deps.refunds = () => Promise.resolve([refund]);
  await rejects(() => executeTopupRefund(id, deps));
  equal(calls.includes("create"), false);
  equal(calls.includes("reconcile"), false);
});
Deno.test("multiple active or matching refunds are ambiguous", async () => {
  const { deps, refund } = setup();
  deps.refunds = () => Promise.resolve([refund, { ...refund, id: "re_other" }]);
  await rejects(() => executeTopupRefund(id, deps));
});
Deno.test("list payload is not terminal truth; retrieve current state", async () => {
  const { deps, refund } = setup();
  deps.refunds = () => Promise.resolve([{ ...refund, status: "pending" }]);
  equal(await executeTopupRefund(id, deps), { id, status: "succeeded" });
});
Deno.test("denial is DB-only and never invokes Stripe", async () => {
  const { deps, calls } = setup();
  deps.callerRpc = () => Promise.resolve({ id, status: "denied" });
  const response = await handleVoluntaryTopupRefund(
    request({ action: "deny", id }),
    deps,
  );
  equal(await response.json(), { data: { id, status: "denied" } });
  equal(calls, ["auth"]);
});
Deno.test("Owner list forwards canonical caller RPC with cursor", async () => {
  const { deps, calls } = setup();
  deps.callerRpc = (name, args) => {
    equal(name, "owner_list_voluntary_topup_refunds");
    equal(args, { p_before: null, p_before_id: null });
    return Promise.resolve([]);
  };
  const response = await handleVoluntaryTopupRefund(
    request({ action: "list" }),
    deps,
  );
  equal(await response.json(), { data: [] });
  equal(calls, ["auth"]);
});
for (const code of [401, 403, 409]) {
  Deno.test(`authority ${code} denies before service dispatch`, async () => {
    const { deps, calls } = setup();
    deps.callerRpc = () => {
      return Promise.reject(new TopupRefundError(code, "forbidden"));
    };
    equal(
      (await handleVoluntaryTopupRefund(
        request({ action: "approve", id }),
        deps,
      )).status,
      code,
    );
    equal(calls, ["auth"]);
  });
}
for (
  const body of [
    { action: "approve", id, amount: 100 },
    { action: "approve", id, user_id: "other" },
    { action: "approve", id, location_id: 2 },
    { action: "approve", id: "bad" },
    { action: "deny", id, note: 3 },
    null,
    [],
    { action: "list", id },
  ]
) {
  Deno.test(`reject forged contract ${JSON.stringify(body)}`, async () => {
    const { deps, calls } = setup();
    equal((await handleVoluntaryTopupRefund(request(body), deps)).status, 400);
    equal(calls, ["auth"]);
  });
}
Deno.test("unauthenticated or wrong method never reaches SQL/provider", async () => {
  const { deps, calls } = setup();
  deps.authenticate = () => {
    return Promise.reject(new TopupRefundError(401, "session_invalid"));
  };
  equal(
    (await handleVoluntaryTopupRefund(request({ action: "approve", id }), deps))
      .status,
    401,
  );
  equal(
    (await handleVoluntaryTopupRefund(
      new Request("https://local.invalid"),
      deps,
    )).status,
    405,
  );
  equal(calls, []);
});

function event(): StripeEvent {
  return {
    id: "evt_test",
    created: 1780000000,
    livemode: false,
    type: "payment_intent.succeeded",
    data: {
      object: {
        id: "pi_test",
        status: "succeeded",
        currency: "usd",
        amount_received: 2000,
        latest_charge: "ch_test",
        metadata: { purpose: "wallet_load", user_id: id },
      },
    },
  };
}
Deno.test("verified success event records provenance after existing settlement", async () => {
  const calls: string[] = [];
  const e = event();
  await handleStripeWebhook({ rawBody: "signed", signature: "sig" }, {
    verifyAndConstructEvent: () => Promise.resolve(e),
    recordWalletLoad: () => {
      calls.push("load");
      return Promise.resolve();
    },
    recordTopupRefundProvenance: (p) => {
      calls.push("provenance");
      equal(p, {
        intent: "pi_test",
        user: id,
        amount: 2000,
        succeededAt: new Date(e.created! * 1000).toISOString(),
        event: "evt_test",
        livemode: false,
      });
      return Promise.resolve();
    },
  });
  equal(calls, ["load", "provenance"]);
});
for (
  const mutate of [(e: StripeEvent) => {
    delete e.created;
  }, (e: StripeEvent) => {
    delete e.livemode;
  }, (e: StripeEvent) => {
    e.data.object.currency = "eur";
  }, (e: StripeEvent) => {
    e.data.object.status = "processing";
  }, (e: StripeEvent) => {
    e.type = "checkout.session.completed";
    e.data.object.amount_total = 2000;
  }]
) {
  Deno.test("incomplete/non-success evidence preserves settlement without guessing provenance", async () => {
    const e = event();
    mutate(e);
    let captured = false, settled = false;
    await handleStripeWebhook({ rawBody: "signed", signature: "sig" }, {
      verifyAndConstructEvent: () => Promise.resolve(e),
      recordWalletLoad: () => {
        settled = true;
        return Promise.resolve();
      },
      recordTopupRefundProvenance: () => {
        captured = true;
        return Promise.resolve();
      },
    });
    equal(settled, true);
    equal(captured, false);
  });
}
Deno.test("unsigned event cannot create provenance", async () => {
  let captured = false;
  equal(
    (await handleStripeWebhook({ rawBody: "bad", signature: "sig" }, {
      verifyAndConstructEvent: () => {
        return Promise.reject(new Error("bad signature"));
      },
      recordTopupRefundProvenance: () => {
        captured = true;
        return Promise.resolve();
      },
    })).status,
    400,
  );
  equal(captured, false);
});
