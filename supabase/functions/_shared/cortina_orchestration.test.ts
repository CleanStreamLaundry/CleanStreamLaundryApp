import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { compensateVend, CortinaDeps, DRYER_OPTIONS, sha256, startCortinaVend, VendSession } from "./cortina.ts";
import { handleNayaxCallback } from "./cortina_callback.ts";
import { handleStatus } from "../cortina-vend/logic.ts";

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
    pulse_line_number: 1,
    product_code: null,
    nayax_environment: "sandbox",
    nayax_terminal_id: "4434331126150568",
    nayax_uniqr: null,
    stripe_livemode: false,
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
  let callbackInsertError: string | undefined;
  let beforeSupport: (() => void) | undefined;
  let sponsoredAllowed = true;

  // Execute predicates at update time to exercise the production compare-and-set logic.
  const admin = {
    rpc(name: string, input: Row) {
      if (name === "consume_cortina_request_capacity") {
        assertEquals(input.p_bucket, "status");
        return { abortSignal(signal: AbortSignal) {
          assertEquals(signal.aborted, false);
          return Promise.resolve({ data: { allowed: true, retry_after_seconds: 0 }, error: null });
        } };
      }
      if (name === "authorize_machine_issue_start") return Promise.resolve({ data: sponsoredAllowed, error: null });
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
          if (insertion.source === "nayax" && callbackInsertError) {
            return { data: null, error: { code: callbackInsertError, message: "Synthetic database ownership rejection" } };
          }
          if (events.some((event) => event.event_key === insertion!.event_key)) {
            return { data: null, error: { code: "23505" } };
          }
          events.push(structuredClone(insertion));
          return { data: null, error: null };
        }
        if (change?.status === "approved") beforeApproval?.();
        if (change?.status === "support_required") beforeSupport?.();
        const row = table === "cortina_machine_config" ? config : table === "Machines" ? machine
          : table === "cortina_vend_events" ? events.find((event) => filters.every((filter) => filter(event))) : session;
        if (!row || !filters.every((filter) => filter(row))) return { data: null, error: null };
        if (change) Object.assign(row, change);
        return { data: structuredClone(row), error: null };
      };
      const query = {
        select(_columns: string) { return query; },
        eq(key: string, value: unknown) {
          filters.push((row) => row[key] === value);
          return query;
        },
        neq(key: string, value: unknown) { filters.push((row) => row[key] !== value); return query; },
        in(key: string, values: unknown[]) {
          filters.push((row) => values.includes(row[key]));
          return query;
        },
        is(key: string, value: null) {
          filters.push((row) => (row[key] ?? null) === value);
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
    MachineInfo: { TerminalId: session.nayax_terminal_id },
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
    rejectCallbackInsert(code: string) { callbackInsertError = code; },
    beforeSupport(value: () => void) { beforeSupport = value; },
    sponsoredAllowed(value: boolean) { sponsoredAllowed = value; },
  };
}

function sponsoredFixture() {
  const f = fixture();
  Object.assign(f.session, { funding_source: "machine_issue", complaint_refund_id: 7, payment_method: "wallet",
    stripe_payment_intent_id: null, stripe_livemode: null, wallet_redemption_id: null });
  f.deps.beforeSponsoredStart = () => Promise.resolve();
  return f;
}

Deno.test("sponsored replacement reuses exact Start once with no new debit/refund", async () => {
  const f = sponsoredFixture(); await f.start(); await f.start();
  assertEquals(f.requests.length, 1);
  assertEquals(f.requests[0].body.Products, [{ PulseLineNumber: 1, Price: 4 }]);
  assertEquals(f.refundCalls, []); assertEquals(f.reversals, []);
  assertEquals(f.session.status, "awaiting_sale");
});

Deno.test("sponsored definitive failure never compensates the original payment or retries", async () => {
  const f = sponsoredFixture();
  f.onStart(() => Promise.resolve(Response.json({ Status: { Verdict: "Declined", Code: 1 } })));
  await f.start(); await f.start();
  assertEquals(f.requests.length, 1); assertEquals(f.refundCalls, []); assertEquals(f.reversals, []);
  assertEquals(f.session.status, "support_required");
});

Deno.test("sponsored unknown Start remains support-required with one provider attempt", async () => {
  const f = sponsoredFixture(); f.onStart(() => Promise.reject(new Error("timeout")));
  await f.start(); await f.start();
  assertEquals(f.requests.length, 1); assertEquals(f.session.status, "support_required");
  assertEquals(f.refundCalls, []); assertEquals(f.reversals, []);
});

Deno.test("sponsored Start rechecks captured Owner and reservation after the audit await", async () => {
  const f = sponsoredFixture(); f.deps.beforeSponsoredStart = () => { f.sponsoredAllowed(false); return Promise.resolve(); };
  await f.start();
  assertEquals(f.requests.length, 0); assertEquals(f.session.status, "support_required");
  assertEquals(f.reversals, []);
});

Deno.test("sponsored callback denies an original compensation conflict, without new money", async () => {
  const f = sponsoredFixture(); await f.start(); f.sponsoredAllowed(false);
  const result = await f.callback();
  assertEquals(result.Status.Verdict, "Declined");
  assertEquals(f.refundCalls, []); assertEquals(f.reversals, []);
});

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
  f.session.nayax_terminal_id = null;
  f.session.nayax_uniqr = f.config.nayax_uniqr;
  await f.start();
  assertEquals(f.requests[0].body.TerminalId, undefined);
  assertEquals(f.requests[0].body.UniQR, f.config.nayax_uniqr);
});

Deno.test("price-array Start uses the snapshotted Code, never PulseLineNumber", async () => {
  for (const code of [0, 3]) {
    const f = fixture();
    f.session.product_code = code;
    f.session.pulse_line_number = null;
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
    f.session.pulse_line_number = null;
    f.config.pulse_line_number = null;
    await f.start();
    assertEquals(f.requests[0].body.Products, [{ Code: code, Price: option.amountCents / 100 }]);
  }
});

Deno.test("a missing frozen selector requires reconciliation without Start or guessed refund", async () => {
  const f = fixture();
  f.config.pulse_line_number = null;
  f.session.pulse_line_number = null;
  await f.start();
  assertEquals(f.requests.length, 0);
  assertEquals(f.refunds.size, 0);
  assertEquals(f.session.status, "support_required");
});

Deno.test("a documented definitive Start rejection refunds once and preserves Nayax code", async () => {
  const f = fixture();
  f.onStart(async () => Response.json({ Status: { Verdict: "Declined", Code: 7 } }));
  await f.start();
  await f.start();
  assertEquals(f.requests.length, 1);
  assertEquals(f.refunds.size, 1);
  assertEquals(f.session.status, "refunded");
  assertEquals(f.session.failure_code, "7");
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

Deno.test("Sale rejects mismatched amount, currency, terminal, and environment", async () => {
  for (const mismatch of ["amount", "currency", "terminal", "environment"]) {
    const f = fixture();
    f.session.status = "awaiting_sale";
    const body = f.body();
    if (mismatch === "amount") body.BasicInfo.Amount = 6;
    if (mismatch === "currency") body.BasicInfo.CurrencyCode = "EUR";
    if (mismatch === "terminal") body.MachineInfo.TerminalId = "4434331126150748";
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
    f.session.status = "voided";
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

Deno.test("Start and callbacks retain frozen routing after config changes", async () => {
  const f = fixture();
  f.config.environment = "production";
  f.config.nayax_terminal_id = "9999999999999999";
  f.config.pulse_line_number = 6;
  await Promise.all([f.start(), f.start(), f.start()]);
  assertEquals(f.requests.length, 1);
  assertEquals(f.requests[0].url, "https://nayax.invalid/start");
  assertEquals(f.requests[0].body.TerminalId, "4434331126150568");
  assertEquals(f.requests[0].body.Products, [{ PulseLineNumber: 1, Price: 4 }]);
  assertEquals((await f.callback()).Status.Verdict, "Approved");
});

Deno.test("documented Sale accepts an empty terminal and unrelated hardware serial", async () => {
  const f = fixture(); f.session.status = "awaiting_sale";
  const body = f.body();
  body.MachineInfo.TerminalId = "";
  body.DeviceInfo.HwSerial = "0123456123456123";
  assertEquals((await f.callback(body)).Status.Verdict, "Approved");
  assertEquals(f.session.nayax_transaction_id, "1234567");
});

Deno.test("SaleEnd without a device can complete while Start is still returning", async () => {
  const f = fixture();
  f.onStart(async () => {
    assertEquals((await f.callback({ BasicInfo: f.body().BasicInfo } as any, "SaleEndNotification")).Status.Verdict, "Approved");
    throw new Error("late response failure");
  });
  await f.start();
  assertEquals(f.session.status, "started");
  assertEquals(f.refundCalls, []);
});

Deno.test("Void before acknowledged Sale compensates once with no guessed provider ID", async () => {
  const f = fixture(); await f.start();
  const body: any = f.body(); delete body.BasicInfo.NayaxTransactionId;
  assertEquals((await f.callback(body, "StaticQR/Void")).Status.Verdict, "Approved");
  assertEquals((await f.callback(body, "StaticQR/Void")).Status.Verdict, "Approved");
  assertEquals(f.session.status, "refunded");
  assertEquals(f.refundCalls, ["create"]);
});

for (const route of ["StaticQR/Sale", "StaticQR/Void", "SaleEndNotification"]) {
  for (const mismatch of ["missing_currency", "subcent_amount", "transaction", "environment", "terminal", "legacy"]) {
    Deno.test(`${route} rejects ${mismatch} without money or machine effects`, async () => {
      const f = fixture(); f.session.status = "awaiting_sale";
      const body: any = f.body();
      if (mismatch === "missing_currency") delete body.BasicInfo.CurrencyCode;
      if (mismatch === "subcent_amount") body.BasicInfo.Amount = 4.001;
      if (mismatch === "transaction") body.BasicInfo.TransactionId = "unrelated";
      if (mismatch === "terminal") body.MachineInfo.TerminalId = "wrong";
      if (mismatch === "legacy") f.session.nayax_environment = null;
      const result = await f.callback(body, route, mismatch === "environment" ? "production" : "sandbox");
      assertEquals(result.Status.Verdict, "Declined");
      assertEquals(f.session.status, "awaiting_sale");
      assertEquals(f.events, []); assertEquals(f.refundCalls, []); assertEquals(f.requests, []);
    });
  }
  Deno.test(`${route} rejects a conflicting bound Nayax transaction`, async () => {
    const f = fixture(); f.session.status = "approved"; f.session.nayax_transaction_id = "7654321";
    assertEquals((await f.callback(f.body(), route)).Status.Verdict, "Declined");
    assertEquals(f.refundCalls, []); assertEquals(f.events, []);
  });
}

Deno.test("legacy compensation never guesses routing from today's config", async () => {
  const f = fixture(); f.session.nayax_environment = null;
  f.session.status = "voided";
  let failed = false;
  try { await compensateVend(f.session as VendSession, f.deps, "Legacy void"); } catch { failed = true; }
  assertEquals(failed, true); assertEquals(f.session.status, "support_required");
  assertEquals(f.refundCalls, []); assertEquals(f.requests, []);
});

Deno.test("Void cannot refund an unpaid or not-yet-started session", async () => {
  for (const status of ["payment_pending", "paid"]) {
    const f = fixture(); f.session.status = status;
    assertEquals((await f.callback(f.body(), "StaticQR/Void")).Status.Verdict, "Declined");
    assertEquals(f.refundCalls, []); assertEquals(f.session.status, status);
  }
});

for (const [route, eventType, key] of [
  ["StaticQR/Sale", "sale", "nayax:sale:1234567"],
  ["StaticQR/Void", "void", "nayax:void:1234567"],
  ["SaleEndNotification", "sale_end", "nayax:sale-end:1234567"],
]) {
  Deno.test(`${route} rejects another event owner, type, or transaction without effects`, async () => {
    for (const conflict of ["owner", "source", "type", "transaction", "amount"]) {
      const f = fixture(); f.session.status = "awaiting_sale";
      const payload = f.body();
      if (conflict === "transaction") payload.BasicInfo.TransactionId = "another-transaction";
      if (conflict === "amount") payload.BasicInfo.Amount = 3;
      f.events.push({ event_key: key, session_id: conflict === "owner" ? "another-session" : f.session.id,
        source: conflict === "source" ? "stripe" : "nayax",
        event_type: conflict === "type" ? "another-type" : eventType, payload });
      assertEquals((await f.callback(f.body(), route)).Status.Verdict, "Declined");
      assertEquals(f.session.status, "awaiting_sale");
      assertEquals(f.session.nayax_transaction_id, undefined);
      assertEquals(f.refundCalls, []); assertEquals(f.requests, []); assertEquals(f.events.length, 1);
    }
  });
  Deno.test(`${route} preserves top-level Nayax transaction identity across retries`, async () => {
    const f = fixture(); f.session.status = "awaiting_sale";
    const body: any = f.body();
    body.NayaxTransactionId = body.BasicInfo.NayaxTransactionId;
    delete body.BasicInfo.NayaxTransactionId;
    assertEquals((await f.callback(body, route)).Status.Verdict, "Approved");
    assertEquals((await f.callback(body, route)).Status.Verdict, "Approved");
    assertEquals(f.events.length, 1);
    assertEquals(f.events[0].payload.BasicInfo.NayaxTransactionId, 1234567);
    assertEquals(f.refundCalls, route === "StaticQR/Void" ? ["create"] : []);
    assertEquals(f.requests, []);
  });
  for (const code of ["23505", "23514"]) {
    Deno.test(`${route} declines database ownership rejection ${code} without effects`, async () => {
      const f = fixture(); f.session.status = "awaiting_sale";
      f.rejectCallbackInsert(code);
      assertEquals((await f.callback(f.body(), route)).Status.Verdict, "Declined");
      assertEquals(f.session.status, "awaiting_sale");
      assertEquals(f.session.nayax_transaction_id, undefined);
      assertEquals(f.events, []); assertEquals(f.refundCalls, []);
      assertEquals(f.reversals, []); assertEquals(f.requests, []);
    });
  }
  Deno.test(`${route} scopes new audit identity to the frozen environment`, async () => {
    for (const environment of ["sandbox", "production"] as const) {
      const f = fixture(); f.session.status = "awaiting_sale";
      f.session.nayax_environment = environment;
      f.session.stripe_livemode = environment === "production";
      assertEquals((await f.callback(f.body(), route, environment)).Status.Verdict, "Approved");
      assertEquals(f.events[0].event_key, key.replace("nayax:", `nayax:${environment}:`));
    }
  });
}

Deno.test("Void rejects an invalid supplied top-level provider identity without compensation", async () => {
  const f = fixture(); f.session.status = "awaiting_sale";
  const body: any = f.body(); delete body.BasicInfo.NayaxTransactionId;
  body.NayaxTransactionId = "not-an-id";
  assertEquals((await f.callback(body, "StaticQR/Void")).Status.Verdict, "Declined");
  assertEquals(f.events, []); assertEquals(f.refundCalls, []); assertEquals(f.session.status, "awaiting_sale");
});

const uncertainStarts: Array<[string, () => Promise<Response>]> = [
  ["aborted response", async () => { throw new DOMException("timeout", "AbortError"); }],
  ["connection lost", async () => { throw new Error("connection lost"); }],
  ["HTTP 500 with decline body", async () => Response.json({ Status: { Verdict: "Declined", Code: 7 } }, { status: 500 })],
  ["HTTP 504", async () => new Response("gateway timeout", { status: 504 })],
  ["invalid JSON", async () => new Response("not JSON")],
  ["empty status", async () => Response.json({})],
  ["unknown verdict", async () => Response.json({ Status: { Verdict: "Pending", Code: 7 } })],
  ...[6, 992, 999, 13, undefined, "7"].map((code): [string, () => Promise<Response>] => [
    `uncertain decline code ${String(code)}`, async () => Response.json({ Status: { Verdict: "Declined", Code: code } }),
  ]),
];

for (const method of ["card", "wallet"]) {
  for (const [name, response] of uncertainStarts) {
    Deno.test(`outcome contract: ${method} ${name} neither compensates nor retries Start`, async () => {
      const f = fixture(); f.session.payment_method = method;
      f.onStart(response);
      await f.start(); await f.start();
      assertEquals(f.session.status, "support_required");
      assertEquals(f.session.failure_code, "start_outcome_unknown");
      assertEquals(f.requests.length, 1); assertEquals(f.refundCalls, []); assertEquals(f.reversals, []);
      assertEquals(f.refunds.size, 0);
    });
  }
  Deno.test(`outcome contract: ${method} documented rejections compensate exactly once`, async () => {
    for (const code of [1, 5, 7, 8, 997, 998]) {
      const f = fixture(); f.session.payment_method = method;
      f.onStart(async () => Response.json({ Status: { Verdict: "Declined", Code: code } }));
      await f.start(); await f.start();
      assertEquals(f.session.status, "refunded"); assertEquals(f.session.failure_code, String(code));
      assertEquals(f.requests.length, 1);
      assertEquals(f.refundCalls, method === "card" ? ["create"] : []);
      assertEquals(f.reversals, method === "wallet" ? [f.session.id] : []);
    }
  });
  for (const status of ["paid", "starting", "awaiting_sale", "approved"]) {
    Deno.test(`outcome contract: ${method} 45-second ${status} client wait is support, not a failed vend`, async () => {
      const f = fixture(); f.session.payment_method = method; f.session.status = status;
      f.session.start_requested_at = "2020-01-01T00:00:00.000Z";
      f.session.client_access_token_hash = await sha256("synthetic-access-token");
      const priorTimeout = Deno.env.get("CORTINA_VEND_TIMEOUT_SECONDS");
      try {
        Deno.env.set("CORTINA_VEND_TIMEOUT_SECONDS", "45");
        const response = await handleStatus(new Request("https://fixture.invalid/status", {
          method: "POST", body: JSON.stringify({ sessionId: f.session.id, accessToken: "synthetic-access-token" }),
        }), f.deps);
        assertEquals((await response.json()).status, "support_required");
        assertEquals(f.session.failure_code, "vend_outcome_unknown");
        await f.start();
        assertEquals(f.requests, []); assertEquals(f.refundCalls, []); assertEquals(f.reversals, []);
      } finally {
        if (priorTimeout === undefined) Deno.env.delete("CORTINA_VEND_TIMEOUT_SECONDS");
        else Deno.env.set("CORTINA_VEND_TIMEOUT_SECONDS", priorTimeout);
      }
    });
  }
  Deno.test(`outcome contract: ${method} historical failed label alone cannot authorize compensation`, async () => {
    const f = fixture(); f.session.payment_method = method; f.session.status = "failed";
    await compensateVend(f.session as VendSession, f.deps, "Historical failure");
    assertEquals(f.session.status, "support_required");
    assertEquals(f.refundCalls, []); assertEquals(f.reversals, []);
  });
}

Deno.test("outcome contract: a validated late Void can compensate an unknown Start once", async () => {
  const f = fixture(); f.onStart(async () => { throw new Error("connection lost"); });
  await f.start();
  assertEquals(f.session.status, "support_required"); assertEquals(f.refundCalls, []);
  assertEquals((await f.callback(f.body(), "StaticQR/Void")).Status.Verdict, "Approved");
  assertEquals((await f.callback(f.body(), "StaticQR/Void")).Status.Verdict, "Approved");
  assertEquals(f.refundCalls, ["create"]); assertEquals(f.session.status, "refunded");
  assertEquals(f.requests.length, 1);
});

Deno.test("outcome contract: unknown state is not reopened by late Sale or SaleEnd", async () => {
  const f = fixture(); f.onStart(async () => { throw new Error("connection lost"); });
  await f.start();
  assertEquals((await f.callback()).Status.Verdict, "Declined");
  assertEquals((await f.callback(f.body(), "SaleEndNotification")).Status.Verdict, "Declined");
  assertEquals(f.session.status, "support_required");
  assertEquals(f.requests.length, 1); assertEquals(f.refundCalls, []);
});

Deno.test("outcome contract: accepted Sale outranks a late definitive Start rejection", async () => {
  const f = fixture();
  f.onStart(async () => {
    assertEquals((await f.callback()).Status.Verdict, "Approved");
    return Response.json({ Status: { Verdict: "Declined", Code: 7 } });
  });
  await f.start();
  assertEquals(f.session.status, "approved"); assertEquals(f.refundCalls, []);
});

Deno.test("outcome contract: concurrent completion is not overwritten by timeout support", async () => {
  const f = fixture(); f.session.status = "timed_out";
  const timeoutSnapshot = structuredClone(f.session) as VendSession;
  f.beforeSupport(() => { f.session.status = "started"; });
  await compensateVend(timeoutSnapshot, f.deps, "Client timeout");
  assertEquals(f.session.status, "started"); assertEquals(f.refundCalls, []);
});

Deno.test("outcome contract: missing credentials prevent dispatch and compensate once", async () => {
  const f = fixture(); Deno.env.delete("NAYAX_SANDBOX_SECRET_TOKEN");
  try {
    await f.start(); await f.start();
    assertEquals(f.requests, []); assertEquals(f.refundCalls, ["create"]);
    assertEquals(f.session.status, "refunded"); assertEquals(f.session.failure_code, "start_not_sent");
  } finally { Deno.env.set("NAYAX_SANDBOX_SECRET_TOKEN", "test-secret"); }
});

Deno.test("outcome contract: an earlier request audit blocks another Start without guessing its outcome", async () => {
  const f = fixture();
  f.events.push({ session_id: f.session.id, source: "clean_stream", event_type: "nayax_start_request",
    event_key: `start-request:${f.session.id}`, payload: {} });
  await f.start(); await f.start();
  assertEquals(f.session.status, "support_required");
  assertEquals(f.requests, []); assertEquals(f.refundCalls, []); assertEquals(f.events.length, 1);
});

Deno.test("outcome contract: an earlier Start remains uncertain even when today's machine is unavailable", async () => {
  const f = fixture(); f.machine.is_out_of_service = true;
  f.events.push({ session_id: f.session.id, source: "clean_stream", event_type: "nayax_start_request",
    event_key: `start-request:${f.session.id}`, payload: {} });
  await f.start();
  assertEquals(f.session.status, "support_required");
  assertEquals(f.requests, []); assertEquals(f.refundCalls, []); assertEquals(f.events.length, 1);
});

Deno.test("outcome contract: timeout can observe an already-bound refund without creating another", async () => {
  const f = fixture(); f.session.status = "timed_out"; f.session.stripe_refund_id = "re_test";
  f.refunds.set(`cortina-refund-${f.session.id}`, {
    id: "re_test", payment_intent: "pi_test", amount: 400, currency: "usd", status: "pending",
  });
  await compensateVend(f.session as VendSession, f.deps, "Client timeout");
  assertEquals(f.session.status, "support_required"); assertEquals(f.session.stripe_refund_id, "re_test");
  assertEquals(f.refundCalls, ["retrieve"]); assertEquals(f.requests, []);
});

Deno.test("outcome contract: callback audit binding outranks rejection before the callback status write", async () => {
  const f = fixture();
  f.onStart(async () => {
    // The real ownership trigger commits this ID with the callback audit, before
    // the callback handler's next conditional status update.
    f.session.nayax_transaction_id = "1234567";
    return Response.json({ Status: { Verdict: "Declined", Code: 7 } });
  });
  await f.start(); await f.start();
  assertEquals(f.session.status, "starting"); assertEquals(f.session.nayax_transaction_id, "1234567");
  assertEquals(f.refundCalls, []); assertEquals(f.requests.length, 1);
});

function pulseEndBody(f: ReturnType<typeof fixture>): any {
  return {
    BasicInfo: { TransactionId: f.session.transaction_id, NayaxTransactionId: 1234567 },
    PaymentInfo: { AuthAmount: 0, SettAmount: 4, RRN: "fixture-rrn" },
  };
}

Deno.test("observed Pulse SaleEnd binds settlement to prior validated Sale and replays once", async () => {
  const f = fixture(); await f.start(); await f.callback();
  const body = pulseEndBody(f);
  assertEquals((await f.callback(body, "SaleEndNotification")).Status.Verdict, "Approved");
  const completed = f.session.completed_at;
  assertEquals((await f.callback(body, "SaleEndNotification")).Status.Verdict, "Approved");
  assertEquals(f.session.status, "started");
  assertEquals(f.session.completed_at, completed);
  const ends = f.events.filter(e => e.event_type === "sale_end");
  assertEquals(ends.length, 1);
  assertEquals(ends[0].payload.BasicInfo.Amount, 4);
  assertEquals(ends[0].payload.BasicInfo.CurrencyCode, "USD");
  assertEquals(ends[0].payload.MoneyValidation, {
    source: "settlement_and_validated_sale", saleEventKey: "nayax:sandbox:sale:1234567",
    receivedBasicAmount: null, receivedCurrencyCode: null, settlementAmount: 4,
  });
  assertEquals(body.BasicInfo.Amount, undefined);
  assertEquals(f.requests.length, 1); assertEquals(f.refundCalls, []);
});

for (const mismatch of ["no_sale", "sale_owner", "sale_source", "sale_kind", "sale_amount", "sale_currency",
  "sale_transaction", "sale_provider", "sale_terminal", "unbound_provider", "wrong_provider", "wrong_transaction",
  "wrong_terminal", "wrong_environment", "legacy_sale", "legacy_session", "settlement_missing", "settlement_zero",
  "settlement_wrong", "settlement_subcent", "settlement_boolean", "settlement_array", "settlement_blank",
  "present_amount", "present_currency", "refunded", "voided", "support_required", "awaiting_sale"] as const) {
  Deno.test(`Pulse SaleEnd rejects ${mismatch} without completion, retry or refund`, async () => {
    const f = fixture(); await f.start(); await f.callback();
    const sale = f.events.find(e => e.event_type === "sale")!;
    const body = pulseEndBody(f);
    if (mismatch === "no_sale") f.events.splice(f.events.indexOf(sale), 1);
    if (mismatch === "sale_owner") sale.session_id = "other";
    if (mismatch === "sale_source") sale.source = "other";
    if (mismatch === "sale_kind") sale.event_type = "void";
    if (mismatch === "sale_amount") sale.payload.BasicInfo.Amount = 8;
    if (mismatch === "sale_currency") sale.payload.BasicInfo.CurrencyCode = "EUR";
    if (mismatch === "sale_transaction") sale.payload.BasicInfo.TransactionId = "other";
    if (mismatch === "sale_provider") sale.payload.BasicInfo.NayaxTransactionId = 7654321;
    if (mismatch === "sale_terminal") sale.payload.MachineInfo.TerminalId = "other";
    if (mismatch === "unbound_provider") f.session.nayax_transaction_id = null;
    if (mismatch === "wrong_provider") body.BasicInfo.NayaxTransactionId = 7654321;
    if (mismatch === "wrong_transaction") body.BasicInfo.TransactionId = "other";
    if (mismatch === "wrong_terminal") body.MachineInfo = { TerminalId: "other" };
    if (mismatch === "legacy_sale") sale.event_key = "nayax:sale:1234567";
    if (mismatch === "legacy_session") f.session.nayax_environment = null;
    if (mismatch === "settlement_missing") delete body.PaymentInfo.SettAmount;
    if (mismatch === "settlement_zero") body.PaymentInfo.SettAmount = 0;
    if (mismatch === "settlement_wrong") body.PaymentInfo.SettAmount = 8;
    if (mismatch === "settlement_subcent") body.PaymentInfo.SettAmount = 4.001;
    if (mismatch === "settlement_boolean") body.PaymentInfo.SettAmount = true;
    if (mismatch === "settlement_array") body.PaymentInfo.SettAmount = [4];
    if (mismatch === "settlement_blank") body.PaymentInfo.SettAmount = "";
    if (mismatch === "present_amount") body.BasicInfo.Amount = 0;
    if (mismatch === "present_currency") body.BasicInfo.CurrencyCode = "EUR";
    if (["refunded", "voided", "support_required", "awaiting_sale"].includes(mismatch)) f.session.status = mismatch;
    const before = structuredClone(f.session);
    assertEquals((await f.callback(body, "SaleEndNotification", mismatch === "wrong_environment" ? "production" : "sandbox")).Status.Verdict, "Declined");
    assertEquals(f.session, before);
    assertEquals(f.events.filter(e => e.event_type === "sale_end"), []);
    assertEquals(f.requests.length, 1); assertEquals(f.refundCalls, []);
  });
}

Deno.test("SaleEnd with full BasicInfo still rejects a conflicting settlement amount", async () => {
  const f = fixture(); await f.start(); await f.callback();
  const body: any = f.body(); body.PaymentInfo = { SettAmount: 3 };
  assertEquals((await f.callback(body, "SaleEndNotification")).Status.Code, 7);
  assertEquals(f.session.status, "approved");
});

Deno.test("Pulse SaleEnd preserves database ownership and state rejection", async () => {
  const f = fixture(); await f.start(); await f.callback();
  f.rejectCallbackInsert("23514");
  assertEquals((await f.callback(pulseEndBody(f), "SaleEndNotification")).Status.Verdict, "Declined");
  assertEquals(f.session.status, "approved");
  assertEquals(f.events.filter(e => e.event_type === "sale_end"), []);
  assertEquals(f.refundCalls, []);
});
