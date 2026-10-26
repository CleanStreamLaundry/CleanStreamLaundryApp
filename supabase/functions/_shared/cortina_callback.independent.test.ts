import assert from "node:assert/strict";
import type {
  CortinaDeps,
  VendSession,
  VendStatus,
} from "./cortina.ts";
import { handleNayaxCallback } from "./cortina_callback.ts";

type Row = Record<string, unknown>;

function fixture(status: VendStatus, collision = false) {
  const session: VendSession & Row = {
    id: "00000000-0000-4000-8000-000000000001",
    machine_id: 1,
    user_id: null,
    amount_cents: 400,
    dryer_minutes: null,
    pulse_line_number: 1,
    product_code: null,
    currency: "USD",
    payment_method: "card",
    channel: "app",
    status,
    transaction_id: "fixture-transaction-0001",
    stripe_payment_intent_id: "pi_fixture",
    stripe_checkout_session_id: null,
    stripe_refund_id: null,
    wallet_redemption_id: null,
    nayax_environment: "sandbox",
    nayax_terminal_id: "4434331126150568",
    nayax_uniqr: null,
    stripe_livemode: false,
    nayax_transaction_id: status === "starting" ? null : "1234567",
  };
  const events: Row[] = collision
    ? [{
      session_id: "00000000-0000-4000-8000-000000000002",
      source: "nayax",
      event_type: "sale",
      event_key: "nayax:sale:1234567",
      payload: {},
    }]
    : [];
  let afterEvent: (() => void) | undefined;
  const updates: Row[] = [];
  const admin = {
    from(table: string) {
      const filters: Array<(row: Row) => boolean> = [];
      let change: Row | undefined;
      let insertion: Row | undefined;
      const execute = () => {
        if (insertion) {
          assert.equal(table, "cortina_vend_events");
          if (events.some(event => event.event_key === insertion!.event_key)) {
            return { data: null, error: { code: "23505", message: "duplicate event key" } };
          }
          events.push(structuredClone(insertion));
          afterEvent?.();
          return { data: null, error: null };
        }
        assert.ok(["cortina_vend_sessions", "cortina_vend_events"].includes(table));
        const row = table === "cortina_vend_sessions"
          ? session
          : events.find(event => filters.every(filter => filter(event)));
        if (!row || !filters.every(filter => filter(row))) return { data: null, error: null };
        if (change) {
          updates.push(structuredClone(change));
          Object.assign(row, change);
        }
        // Match the independent snapshot returned by a database read.
        return { data: structuredClone(row), error: null };
      };
      const query = {
        select(_columns: string) { return query; },
        eq(key: string, value: unknown) {
          filters.push(row => row[key] === value);
          return query;
        },
        in(key: string, values: unknown[]) {
          filters.push(row => values.includes(row[key]));
          return query;
        },
        update(value: Row) { change = value; return query; },
        insert(value: Row) { insertion = value; return query; },
        single: async () => execute(),
        maybeSingle: async () => execute(),
        then(resolve: (value: ReturnType<typeof execute>) => unknown) {
          return Promise.resolve(execute()).then(resolve);
        },
      };
      return query;
    },
  };
  const deps = {
    admin,
    stripe: {},
    fetcher: () => { throw new Error("Provider transport prohibited"); },
  } as unknown as CortinaDeps;
  const sale = async () => {
    const keys = ["NAYAX_SANDBOX_CALLBACK_USERNAME", "NAYAX_SANDBOX_CALLBACK_PASSWORD"];
    const previous = keys.map((key) => Deno.env.get(key));
    Deno.env.set(keys[0], "fixture-user");
    Deno.env.set(keys[1], "fixture-password");
    try {
    const response = await handleNayaxCallback(new Request(
      "https://fixture.invalid/functions/v1/nayax-sale-end-sandbox/Cortina/StaticQR/Sale",
      {
        method: "POST",
        headers: { username: "fixture-user", password: "fixture-password" },
        body: JSON.stringify({
          BasicInfo: {
            TransactionId: session.transaction_id,
            NayaxTransactionId: 1234567,
            Amount: 4,
            CurrencyCode: "USD",
          },
          MachineInfo: { TerminalId: session.nayax_terminal_id },
        }),
      },
    ), "sandbox", deps);
    return await response.json();
    } finally {
      keys.forEach((key, i) => {
        if (previous[i] === undefined) Deno.env.delete(key);
        else Deno.env.set(key, previous[i]!);
      });
    }
  };
  return { session, events, updates, sale, afterEvent(fn: () => void) { afterEvent = fn; } };
}

for (const status of ["approved", "started"] as const) {
  Deno.test(`independent Sale: ${status} snapshot cannot approve after concurrent refund`, async () => {
    const f = fixture(status);
    f.afterEvent(() => { f.session.status = "refunded"; });
    const result = await f.sale();
    assert.equal(f.session.status, "refunded");
    assert.equal(result.Status.Verdict, "Declined");
    assert.deepEqual(f.updates, []);
  });
}

Deno.test("independent Sale: another session's event identity cannot authorize this vend", async () => {
  const f = fixture("starting", true);
  const result = await f.sale();
  assert.equal(result.Status.Verdict, "Declined");
  assert.equal(f.session.status, "starting");
  assert.equal(f.session.nayax_transaction_id, null);
  assert.deepEqual(f.updates, []);
  assert.equal(f.events.length, 1);
  assert.notEqual(f.events[0]?.session_id, f.session.id);
});
