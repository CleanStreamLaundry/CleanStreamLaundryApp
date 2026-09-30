import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { compensateVend, CortinaDeps, DRYER_OPTIONS, startCortinaVend, VendSession } from "./cortina.ts";
import { handleNayaxCallback } from "./cortina_callback.ts";

type Row = Record<string, any>;

function fixture() {
  Deno.env.set("NAYAX_SANDBOX_START_URL", "https://nayax.invalid/start");
  Deno.env.set("NAYAX_SANDBOX_SECRET_TOKEN", "test-secret");
  Deno.env.set("NAYAX_CALLBACK_AUTH_TOKEN", "test-callback-secret");
  const session: Row = {
    id: "00000000-0000-4000-8000-000000000001",
    transaction_id: "0123456789abcdef0123456789abcdef",
    machine_id: 1,
    user_id: null,
    amount_cents: 400,
    pulse_line_number: null,
    currency: "USD",
    payment_method: "card",
    stripe_payment_intent_id: "pi_test",
    status: "paid",
  };
  const config: Row = {
    machine_id: 1,
    nayax_terminal_id: "4434331126150568",
    pulse_line_number: 1,
    environment: "sandbox",
    is_enabled: true,
  };
  const machine: Row = { id: 1, is_out_of_service: false };
  const events: Row[] = [];
  const requests: Row[] = [];
  const refunds = new Map<string, Row>();
  const refundCalls: string[] = [];
  const reversals: string[] = [];
  let beforeApproval: (() => void) | undefined;
  let onStart: (() => Promise<Response>) | undefined;

  // Execute predicates at update time to exercise the production compare-and-set logic.
  const admin = {
    rpc(name: string, input: { target_session_id: string }) {
      if (name !== "reverse_cortina_wallet_redemption") throw new Error("Unexpected RPC");
      reversals.push(input.target_session_id); session.status = "refunded";
      return Promise.resolve({ error: null });
    },
    from(table: string) {
      let change: Row | undefined;
      let insertion: Row | undefined;
      const filters: Array<(row: Row) => boolean> = [];
      const execute = () => {
        if (insertion) {
          if (events.some((event) => event.event_key === insertion!.event_key)) {
            return { data: null, error: { code: "23505" } };
          }
          events.push(structuredClone(insertion));
          return { data: null, error: null };
        }
        if (change?.status === "approved") beforeApproval?.();
        const row = table === "cortina_machine_config" ? config : table === "Machines" ? machine : session;
        if (!filters.every((filter) => filter(row))) return { data: null, error: null };
        if (change) Object.assign(row, change);
        return { data: structuredClone(row), error: null };
      };
      const query = {
        select(_columns: string) { return query; },
        eq(key: string, value: unknown) {
          filters.push((row) => row[key] === value);
          return query;
        },
        in(key: string, values: unknown[]) {
          filters.push((row) => values.includes(row[key]));
          return query;
        },
        update(value: Row) { change = value; return query; },
        insert(value: Row) { insertion = value; return query; },
        maybeSingle: async () => execute(),
        single: async () => execute(),
        then(resolve: (value: ReturnType<typeof execute>) => unknown) {
          return Promise.resolve(execute()).then(resolve);
        },
      };
      return query;
    },
  };
  const deps = {
    admin,
    stripe: {
      refunds: {
        create: async (body: Row, options: { idempotencyKey: string }) => {
          refundCalls.push("create");
          if (!refunds.has(options.idempotencyKey)) {
            refunds.set(options.idempotencyKey, {
              id: "re_test", status: "succeeded", currency: "usd",
              amount: session.amount_cents, ...body,
            });
          }
          return refunds.get(options.idempotencyKey)!;
        },
        retrieve: async (id: string) => {
          refundCalls.push("retrieve");
          const refund = [...refunds.values()].find((row) => row.id === id);
          if (!refund) throw new Error("Refund unavailable");
          return refund;
        },
      },
    },
    fetcher: async (url: string, init: RequestInit) => {
      requests.push({ url, method: init.method, headers: init.headers, body: JSON.parse(String(init.body)) });
      return onStart ? await onStart() : Response.json({ Status: { Verdict: "Approved" } });
    },
  } as unknown as CortinaDeps;

  const body = () => ({
    BasicInfo: {
      TransactionId: session.transaction_id,
      NayaxTransactionId: 1234567,
      Amount: 4,
      CurrencyCode: "USD",
    },
    DeviceInfo: { HwSerial: config.nayax_terminal_id },
  });
  const callback = async (value = body(), route = "StaticQR/Sale", environment: "sandbox" | "production" = "sandbox") => {
    const response = await handleNayaxCallback(new Request(
      `https://example.supabase.co/functions/v1/nayax-sale-end-sandbox/Cortina/${route}`,
      {
        method: "POST",
        headers: { "x-nayax-auth": "test-callback-secret" },
        body: JSON.stringify(value),
      },
    ), environment, deps);
    return await response.json();
  };
  return {
    session, config, machine, events, requests, refunds, refundCalls, reversals, deps, body, callback,
    start: () => startCortinaVend(session.id, deps),
    onStart(value: () => Promise<Response>) { onStart = value; },
    beforeApproval(value: () => void) { beforeApproval = value; },
  };
}

Deno.test("Start sends the canonical documented request exactly once", async () => {
  const f = fixture();
  await f.start();
  await f.start();
  assertEquals(f.requests.length, 1);
  assertEquals(f.requests[0], {
    url: "https://nayax.invalid/start",
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: {
      AppUserId: `guest-${f.session.id.slice(0, 30)}`,
      TransactionId: f.session.transaction_id,
      SecretToken: "test-secret",
      TerminalId: "4434331126150568",
      Products: [{ PulseLineNumber: 1, Price: 4 }],
    },
  });
  assertEquals(f.session.status, "awaiting_sale");
  const audit = f.events.find((event) => event.event_type === "nayax_start_request")!;
  assertEquals(audit.payload.request.SecretToken, undefined);
  assertEquals(audit.payload.request.Products, [{ PulseLineNumber: 1, Price: 4 }]);
});

Deno.test("unpaid and closed sessions cannot send Start", async () => {
  for (const status of ["payment_pending", "failed", "refunded", "voided", "started"]) {
    const f = fixture();
    f.session.status = status;
    await f.start();
    assertEquals(f.requests.length, 0);
  }
});

Deno.test("all six dryers send one snapshotted pulse line and decimal price", async () => {
  for (const option of DRYER_OPTIONS) {
    const f = fixture();
    f.session.amount_cents = option.amountCents;
    f.session.pulse_line_number = option.pulseLineNumber;
    await f.start();
    assertEquals(f.requests[0].body.Products, [{
      PulseLineNumber: option.pulseLineNumber,
      Price: option.amountCents / 100,
    }]);
  }
});

Deno.test("UniQR is sent instead of an absent terminal ID", async () => {
  const f = fixture();
  f.config.nayax_terminal_id = null;
  f.config.nayax_uniqr = "https://qr.nayax.com/v1/test";
  await f.start();
  assertEquals(f.requests[0].body.TerminalId, undefined);
  assertEquals(f.requests[0].body.UniQR, f.config.nayax_uniqr);
});

Deno.test("price-array Start uses the snapshotted Code, never PulseLineNumber", async () => {
  for (const code of [0, 3]) {
    const f = fixture();
    f.session.product_code = code;
    f.config.product_codes = { "400": 5 };
    f.config.pulse_line_number = null;
    await f.start();
    await f.start();
    assertEquals(f.requests.length, 1);
    assertEquals(f.requests[0].body.Products, [{ Code: code, Price: 4 }]);
  }
});

Deno.test("all six dryer price-array options preserve their individual codes", async () => {
  for (const [code, option] of DRYER_OPTIONS.entries()) {
    const f = fixture();
    f.session.amount_cents = option.amountCents;
    f.session.product_code = code;
    f.config.pulse_line_number = null;
    await f.start();
    assertEquals(f.requests[0].body.Products, [{ Code: code, Price: option.amountCents / 100 }]);
  }
});

Deno.test("a missing session selector refunds without sending Start", async () => {
  const f = fixture();
  f.config.pulse_line_number = null;
  await f.start();
  assertEquals(f.requests.length, 0);
  assertEquals(f.refunds.size, 1);
});

Deno.test("a declined Start refunds once and preserves Nayax code", async () => {
  const f = fixture();
  f.onStart(async () => Response.json({ Status: { Verdict: "Declined", Code: 13 } }));
  await f.start();
  await f.start();
  assertEquals(f.requests.length, 1);
  assertEquals(f.refunds.size, 1);
  assertEquals(f.session.status, "refunded");
  assertEquals(f.session.failure_code, "13");
});

Deno.test("a paid Sale arriving before Start returns is approved", async () => {
  const f = fixture();
  f.onStart(async () => {
    assertEquals((await f.callback()).Status.Verdict, "Approved");
    return Response.json({ Status: { Verdict: "Approved" } });
  });
  await f.start();
  assertEquals(f.session.status, "approved");
  assertEquals(f.refunds.size, 0);
});

Deno.test("fast Sale and SaleEnd are not overwritten by the Start response", async () => {
  const f = fixture();
  f.onStart(async () => {
    await f.callback();
    await f.callback(f.body(), "SaleEndNotification");
    return Response.json({ Status: { Verdict: "Approved" } });
  });
  await f.start();
  assertEquals(f.session.status, "started");
});

Deno.test("a late Start error cannot refund a callback-confirmed vend", async () => {
  const f = fixture();
  f.onStart(async () => {
    await f.callback();
    await f.callback(f.body(), "SaleEndNotification");
    throw new Error("response connection lost");
  });
  await f.start();
  assertEquals(f.session.status, "started");
  assertEquals(f.refunds.size, 0);
});

Deno.test("duplicate Sale is approved without changing a completed vend", async () => {
  const f = fixture();
  f.session.status = "awaiting_sale";
  await f.callback();
  await f.callback(f.body(), "SaleEndNotification");
  assertEquals((await f.callback()).Status.Verdict, "Approved");
  assertEquals(f.session.status, "started");
  assertEquals(f.events.filter((event) => event.event_type === "sale").length, 1);
});

Deno.test("Sale rejects mismatched amount, currency, serial, and environment", async () => {
  for (const mismatch of ["amount", "currency", "serial", "environment"]) {
    const f = fixture();
    f.session.status = "awaiting_sale";
    const body = f.body();
    if (mismatch === "amount") body.BasicInfo.Amount = 6;
    if (mismatch === "currency") body.BasicInfo.CurrencyCode = "EUR";
    if (mismatch === "serial") body.DeviceInfo.HwSerial = "4434331126150748";
    const result = await f.callback(body, "StaticQR/Sale", mismatch === "environment" ? "production" : "sandbox");
    assertEquals(result.Status.Verdict, "Declined");
    assertEquals(f.session.status, "awaiting_sale");
  }
});

Deno.test("Sale cannot approve a session closed during validation", async () => {
  const f = fixture();
  f.session.status = "awaiting_sale";
  f.beforeApproval(() => { f.session.status = "refunded"; });
  assertEquals((await f.callback()).Status.Verdict, "Declined");
  assertEquals(f.session.status, "refunded");
});

Deno.test("Sale never approves an unpaid or already reversed session", async () => {
  for (const status of ["payment_pending", "paid", "refunded", "voided", "failed", "timed_out"]) {
    const f = fixture();
    f.session.status = status;
    assertEquals((await f.callback()).Status.Verdict, "Declined");
  }
});

Deno.test("a paid checkout settling during an outage is refunded without starting the machine", async () => {
  const f = fixture();
  f.machine.is_out_of_service = true;
  await f.start();
  await f.start();
  assertEquals(f.requests.length, 0);
  assertEquals(f.refunds.size, 1);
  assertEquals(f.session.status, "refunded");
});

Deno.test("wallet payment settling during an outage reverses once without sending Start", async () => {
  const f = fixture(); f.machine.is_out_of_service = true; f.session.payment_method = "wallet";
  await f.start(); await f.start();
  assertEquals(f.requests.length, 0); assertEquals(f.refunds.size, 0);
  assertEquals(f.reversals, [f.session.id]); assertEquals(f.session.status, "refunded");
});
Deno.test("a machine that cannot be read fails closed before Start", async () => {
  const f = fixture(); f.machine.id = 99;
  await f.start();
  assertEquals(f.requests.length, 0); assertEquals(f.refunds.size, 1);
});

for (const status of ["pending", "failed", "canceled", "requires_action", "unknown", undefined]) {
  Deno.test(`failed vend does not report an unconfirmed ${status} refund as completed`, async () => {
    const f = fixture();
    f.machine.is_out_of_service = true;
    f.refunds.set(`cortina-refund-${f.session.id}`, {
      id: "re_test", payment_intent: "pi_test", amount: 400, currency: "usd", status,
    });
    await f.start();
    assertEquals(f.session.status, "support_required");
    assertEquals(f.session.stripe_refund_id, "re_test");
    assertEquals(f.session.completed_at, null);
    assertEquals(f.requests.length, 0);
    assertEquals(f.refundCalls, ["create"]);
  });
}

for (const mismatch of [
  { payment_intent: "pi_other" }, { amount: 399 }, { currency: "eur" },
  { id: "" }, { currency: undefined }, { amount: undefined },
]) {
  Deno.test(`failed vend rejects successful refund mismatch ${JSON.stringify(mismatch)}`, async () => {
    const f = fixture();
    f.refunds.set(`cortina-refund-${f.session.id}`, {
      id: "re_test", payment_intent: "pi_test", amount: 400, currency: "usd",
      status: "succeeded", ...mismatch,
    });
    await compensateVend(f.session as VendSession, f.deps, "Machine unavailable");
    assertEquals(f.session.status, "support_required");
    assertEquals(f.session.completed_at, null);
  });
}

Deno.test("bound pending refund is retrieved to confirm success without another create", async () => {
  const f = fixture();
  f.session.status = "support_required";
  f.session.stripe_refund_id = "re_test";
  const refund = { id: "re_test", payment_intent: { id: "pi_test" }, amount: 400,
    currency: "usd", status: "pending" };
  f.refunds.set(`cortina-refund-${f.session.id}`, refund);
  await compensateVend(f.session as VendSession, f.deps, "Machine unavailable");
  assertEquals(f.session.status, "support_required");
  refund.status = "succeeded";
  await compensateVend(f.session as VendSession, f.deps, "Machine unavailable");
  assertEquals(f.session.status, "refunded");
  assertEquals(typeof f.session.completed_at, "string");
  assertEquals(f.refundCalls, ["retrieve", "retrieve"]);
  await compensateVend(f.session as VendSession, f.deps, "Machine unavailable");
  assertEquals(f.refundCalls, ["retrieve", "retrieve"]);
});

Deno.test("unavailable bound refund remains support-required without a replacement create", async () => {
  const f = fixture();
  f.session.status = "support_required";
  f.session.stripe_refund_id = "re_unavailable";
  let failed = false;
  try {
    await compensateVend(f.session as VendSession, f.deps, "Machine unavailable");
  } catch {
    failed = true;
  }
  assertEquals(failed, true);
  assertEquals(f.session.status, "support_required");
  assertEquals(f.session.stripe_refund_id, "re_unavailable");
  assertEquals(f.refundCalls, ["retrieve"]);
  assertEquals(f.refunds.size, 0);
});
