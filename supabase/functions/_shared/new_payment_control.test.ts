import assert from "node:assert/strict";
import { NewPaymentsUnavailableError, requireNewPayments } from "./new_payment_control.ts";

Deno.test("new payment control reads exactly the fixed RPC with an 8000ms unexpired signal", async () => {
  const timeout = AbortSignal.timeout;
  const durations: number[] = [];
  try {
    AbortSignal.timeout = (ms) => { durations.push(ms); return timeout.call(AbortSignal, ms); };
    await requireNewPayments({ rpc: (...args) => {
      assert.deepEqual(args, ["new_payments_enabled"]);
      return { abortSignal: (signal) => {
        assert(signal instanceof AbortSignal);
        assert.equal(signal.aborted, false);
        return Promise.resolve({ data: true, error: null });
      } };
    } });
    assert.deepEqual(durations, [8000]);
  } finally { AbortSignal.timeout = timeout; }
});

for (const data of [false, null, undefined, 0, 1, "true", [], [true], {}, { enabled: true }]) {
  Deno.test("new payment control accepts only literal true, rejects " + JSON.stringify(data), async () => {
    await assert.rejects(requireNewPayments({ rpc: () => ({
      abortSignal: () => Promise.resolve({ data, error: null }),
    }) }), { name: "Error", message: "new_payments_unavailable" });
  });
}
Deno.test("new payment control missing client never defaults enabled", async () => {
  await assert.rejects(requireNewPayments(undefined), NewPaymentsUnavailableError);
});
Deno.test("new payment control does not accept true accompanied by an SDK error", async () => {
  await assert.rejects(requireNewPayments({ rpc: () => ({
    abortSignal: () => Promise.resolve({ data: true, error: { message: "private database diagnostic" } }),
  }) }), { message: "new_payments_unavailable" });
});
for (const error of [new Error("private transport detail"), new DOMException("private timeout", "TimeoutError")]) {
  Deno.test("new payment control sanitizes rejected transport " + error.name, async () => {
    await assert.rejects(requireNewPayments({ rpc: () => ({
      abortSignal: () => Promise.reject(error),
    }) }), { message: "new_payments_unavailable" });
  });
}
