import assert from "node:assert/strict";
import { handleRefundRequest } from "./logic.ts";

for (const transaction_id of [1, "41", "9223372036854775807"]) {
  Deno.test(`refund notice: valid persisted transaction selector ${transaction_id}`, async () => {
    const calls: string[] = [];
    const result = await handleRefundRequest({
      transaction_id,
      username: "<script>forged</script>",
      amount: -500,
      user_id: "another-user",
      recipient: "forged@example.invalid",
      description: "untrusted",
      userAttempts: 999,
    }, {
      enqueueNotice: (id) => {
        calls.push(id);
        return Promise.resolve({ refund_id: "7", state: "queued" });
      },
    });
    assert.deepEqual(calls, [String(transaction_id)]);
    assert.equal(result.status, 200);
    assert("success" in result.body);
    assert.equal(result.body.success, true);
    assert.equal(result.body.claimRecorded, true);
    assert.equal(result.body.notificationSent, false);
    assert.match(result.body.notificationWarning!, /queued, not yet sent/);
    assert(!JSON.stringify(result).includes("forged"));
    assert(!("resend" in result.body));
  });
}

for (
  const transaction_id of [
    undefined,
    null,
    "",
    " 1",
    "1\n",
    "1 ",
    "01",
    "1e2",
    "1.0",
    "-1",
    0,
    -1,
    1.5,
    Number.MAX_SAFE_INTEGER + 1,
    "9223372036854775808",
    {},
    [],
  ]
) {
  Deno.test(`refund notice: invalid transaction selector ${JSON.stringify(transaction_id)}`, async () => {
    const result = await handleRefundRequest({ transaction_id }, {
      enqueueNotice: () => {
        throw new Error("must not enqueue");
      },
    });
    assert.equal(result.status, 400);
    assert(!("claimRecorded" in result.body));
  });
}

for (
  const state of [
    "queued",
    "sending",
    "uncertain",
    "failed",
    "suppressed",
    "disabled",
    "recipient_unavailable",
    "accepted",
    "delivered",
  ]
) {
  Deno.test(`refund notice: saved claim stays successful for notice state ${state}`, async () => {
    const result = await handleRefundRequest({ transaction_id: "41" }, {
      enqueueNotice: () => Promise.resolve({ refund_id: "7", state }),
    });
    const sent = ["accepted", "delivered"].includes(state);
    assert.equal(result.status, 200);
    assert("success" in result.body);
    assert.equal(result.body.success, true);
    assert.equal(result.body.claimRecorded, true);
    assert.equal(result.body.notificationSent, sent);
    assert.equal(result.body.notificationState, state);
    assert.equal("notificationWarning" in result.body, !sent);
  });
}

Deno.test("refund notice: malformed RPC result never claims success or retries", async () => {
  for (
    const result of [null, [], {}, { refund_id: "7", state: "sent" }, {
      refund_id: "0",
      state: "queued",
    }]
  ) {
    let calls = 0;
    await assert.rejects(() =>
      handleRefundRequest({ transaction_id: "41" }, {
        enqueueNotice: () => {
          calls++;
          return Promise.resolve(result);
        },
      })
    );
    assert.equal(calls, 1);
  }
});

Deno.test("refund notice: enqueue failure is not retried as a business operation", async () => {
  let calls = 0;
  await assert.rejects(() =>
    handleRefundRequest({ transaction_id: "41" }, {
      enqueueNotice: () => {
        calls++;
        return Promise.reject(new Error("offline"));
      },
    })
  );
  assert.equal(calls, 1);
});
