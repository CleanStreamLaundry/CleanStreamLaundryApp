import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  handleRefundResolution,
  RefundHttpError,
  type RefundResolution,
  type RefundResolutionDependencies,
} from "./refund_resolution.ts";
import { renderMail } from "./mail.ts";

const resolution = (overrides: Partial<RefundResolution> = {}): RefundResolution => ({
  success: true,
  alreadyResolved: false,
  refundId: 12,
  transactionId: 44,
  customerId: "customer-1",
  amount: 2.5,
  status: "approved",
  notificationSent: false,
  notificationState: "ready",
  ...overrides,
});

function request(body: unknown): Request {
  return new Request("http://localhost/approveRefund", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer test" },
    body: JSON.stringify(body),
  });
}

function dependencies(overrides: Partial<RefundResolutionDependencies> = {}) {
  const calls = { resolve: 0 };
  const deps: RefundResolutionDependencies = {
    ...overrides,
    authenticate: overrides.authenticate ?? (async () => "admin-1"),
    resolve: async (input) => {
      calls.resolve += 1;
      return overrides.resolve ? await overrides.resolve(input) : resolution({ status: input.decision });
    },
  };
  return { calls, deps };
}

Deno.test("refund resolution reports atomic queue receipt without claiming email was sent", async () => {
  const { calls, deps } = dependencies();
  const response = await handleRefundResolution(
    request({ refundId: 12, note: "Machine failed" }),
    "approved",
    deps,
  );
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.status, "approved");
  assertEquals(body.notificationSent, false);
  assertStringIncludes(body.notificationWarning, "queued");
  assertEquals(calls, { resolve: 1 });
});

Deno.test("an idempotent retry does not send a duplicate notification", async () => {
  const { calls, deps } = dependencies({
    resolve: async () => resolution({ alreadyResolved: true }),
  });
  const response = await handleRefundResolution(
    request({ refundId: 12 }),
    "approved",
    deps,
  );

  assertEquals(response.status, 200);
  assertEquals(calls, { resolve: 1 });
});

Deno.test("notification failure does not hide a completed refund", async () => {
  const { calls, deps } = dependencies({
    resolve: () => Promise.resolve(resolution({ notificationState: "failed" })),
  });
  const response = await handleRefundResolution(
    request({ refundId: 12 }),
    "approved",
    deps,
  );
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.success, true);
  assertEquals(body.notificationSent, false);
  assertStringIncludes(body.notificationWarning, "Customer notice failed");
  assertEquals(calls, { resolve: 1 });
});

Deno.test("invalid refund identifiers are rejected before authentication", async () => {
  const { deps } = dependencies();
  const response = await handleRefundResolution(
    request({ refundId: "R12" }),
    "denied",
    deps,
  );
  assertEquals(response.status, 400);
});

Deno.test("authentication and authorization errors reach the caller", async () => {
  const { deps } = dependencies({
    authenticate: async () => {
      throw new RefundHttpError(403, "Owner or Admin access required");
    },
  });
  const response = await handleRefundResolution(
    request({ refundId: 12 }),
    "denied",
    deps,
  );
  const body = await response.json();

  assertEquals(response.status, 403);
  assertEquals(body.error, "Owner or Admin access required");
});

Deno.test("refund email escapes stored administrator notes in the shared brand renderer", async () => {
  const { payload: { html } } = await renderMail({
    id: "synthetic-job", lease_id: "synthetic-lease", kind: "credit_decision",
    email: "customer@example.invalid", consent_id: null,
    credit_notice: { refund_id: "12", transaction_id: "44", amount_cents: 250,
      status: "approved", note: '<script>alert("x")</script>' },
  }, { key: "re_synthetic", from: "synthetic@cleanstreamlaundry.com", replyTo: "support@cleanstreamlaundry.com",
    postal: "Synthetic", publicUrl: "https://synthetic.invalid/functions/v1/newsletter",
    pageUrl: "https://cleanstreamlaundry.com/newsletter", tokenSecret: "x".repeat(43) });
  assert(!html.includes("<script>"));
  assertStringIncludes(html, "&lt;script&gt;");
});
