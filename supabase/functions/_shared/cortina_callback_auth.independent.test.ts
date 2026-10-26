import assert from "node:assert/strict";
import type { CortinaDeps } from "./cortina.ts";
import { handleNayaxCallback } from "./cortina_callback.ts";

const key = "NAYAX_CALLBACK_AUTH_TOKEN";
const routes = ["StaticQR/Sale", "StaticQR/Void", "SaleEndNotification"];
const headers = [
  { "x-nayax-auth": "qa-secret" },
  { authorization: "Bearer qa-secret" },
] as const;

async function configured(
  secret: string | undefined,
  run: () => Promise<void>,
) {
  const before = Deno.env.get(key);
  try {
    if (secret === undefined) Deno.env.delete(key);
    else Deno.env.set(key, secret);
    await run();
  } finally {
    if (before === undefined) Deno.env.delete(key);
    else Deno.env.set(key, before);
  }
}

function request(route: string, auth: HeadersInit, body: string) {
  const req = new Request(`https://local.invalid/Cortina/${route}`, {
    method: "POST",
    headers: auth,
    body,
  });
  const json = req.json.bind(req);
  let reads = 0;
  Object.defineProperty(req, "json", {
    value: () => {
      reads++;
      return json();
    },
  });
  return { req, reads: () => reads };
}

for (const environment of ["sandbox", "production"] as const) {
  for (const route of routes) {
    Deno.test(`independent ${environment} ${route}: reject before any body read or dependency access`, async () => {
      let accesses = 0;
      const deps = new Proxy({}, {
        get() {
          accesses++;
          throw Error("dependency must remain untouched");
        },
      }) as CortinaDeps;
      const cases: Array<[string | undefined, HeadersInit]> = [
        [undefined, headers[0]],
        ["", headers[0]],
        [" \t\n", headers[0]],
        [undefined, {}],
        ["qa-secret", {}],
        ["qa-secret", { "x-nayax-auth": "wrong" }],
        ["qa-secret", { authorization: "Bearer wrong" }],
        ["qa-secret", {
          "x-nayax-auth": "wrong",
          authorization: "Bearer qa-secret",
        }],
      ];
      for (const [secret, auth] of cases) {
        await configured(secret, async () => {
          const f = request(route, auth, "invalid JSON");
          const response = await handleNayaxCallback(f.req, environment, deps);
          assert.equal(response.status, 200);
          assert.deepEqual(await response.json(), {
            Status: {
              Verdict: "Declined",
              Code: 5,
              StatusMessage: "Unauthorized callback",
            },
          });
          assert.equal(f.reads(), 0);
          assert.equal(f.req.bodyUsed, false);
          assert.equal(accesses, 0);
        });
      }
    });

    for (const auth of headers) {
      Deno.test(`independent ${environment} ${route}: matching ${Object.keys(auth)[0]} preserves authenticated route`, async () => {
        await configured("qa-secret", async () => {
          // Terminal states exercise authenticated routing without initiating compensation.
          const status = route.endsWith("Void")
            ? "refunded"
            : route.endsWith("Sale")
            ? "approved"
            : "started";
          const session = {
            id: "00000000-0000-4000-8000-000000000001",
            transaction_id: "qa-transaction",
            machine_id: 1,
            amount_cents: 400,
            currency: "USD",
            payment_method: "card",
            nayax_environment: environment,
            nayax_terminal_id: "terminal-1",
            nayax_uniqr: null,
            stripe_livemode: environment === "production",
            product_code: null,
            pulse_line_number: 1,
            status,
          };
          const tables: string[] = [],
            events: Array<Record<string, unknown>> = [];
          const admin = {
            from(table: string) {
              tables.push(table);
              const query = {
                select: () => query,
                eq: () => query,
                maybeSingle: () =>
                  Promise.resolve({
                    data: table === "cortina_vend_sessions"
                      ? session
                      : null,
                    error: null,
                  }),
                single: () => Promise.resolve({ data: session, error: null }),
                insert: (event: Record<string, unknown>) => {
                  events.push(event);
                  return Promise.resolve({ error: null });
                },
              };
              return query;
            },
          };
          const deps = new Proxy({ admin }, {
            get(target, property) {
              if (property !== "admin") {
                throw Error(`unexpected dependency ${String(property)}`);
              }
              return target.admin;
            },
          }) as unknown as CortinaDeps;
          const f = request(
            route,
            auth,
            JSON.stringify({
              BasicInfo: {
                TransactionId: session.transaction_id,
                NayaxTransactionId: 123,
                Amount: 4,
                CurrencyCode: "USD",
              },
              MachineInfo: { TerminalId: "terminal-1" },
            }),
          );
          const response = await handleNayaxCallback(f.req, environment, deps);
          const body = await response.json();
          assert.equal(response.status, 200);
          assert.equal(body.Status.Verdict, "Approved");
          assert.equal(f.reads(), 1);
          assert.equal(f.req.bodyUsed, true);
          assert.deepEqual(tables, [
            "cortina_vend_sessions",
            "cortina_vend_events",
            "cortina_vend_events",
            ...(route.endsWith("Sale") ? ["cortina_vend_sessions"] : []),
          ]);
          assert.equal(events.length, 1);
          assert.equal(
            events[0].event_type,
            route.endsWith("Void")
              ? "void"
              : route.endsWith("Sale")
              ? "sale"
              : "sale_end",
          );
          assert.equal(session.status, status);
          if (route !== "SaleEndNotification") {
            assert.equal(body.PaymentInfo.SrvTranId, session.transaction_id);
            assert.equal(body.PaymentInfo.AuthAmount, 4);
          }
        });
      });
    }
  }
}
