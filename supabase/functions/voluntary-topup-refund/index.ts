import { createClient } from "https://esm.sh/@supabase/supabase-js@2.97.0";
import { callerPublishableKey } from "../_shared/supabase_keys.ts";
import {
  CORS_HEADERS,
  createAdminClient,
  createStripeClient,
  errorResponse,
  HttpError,
} from "../_shared/cortina.ts";
import {
  handleVoluntaryTopupRefund,
  TopupRefundError,
} from "../_shared/voluntary_topup_refund.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  let admin;
  let caller;
  const bearer = req.headers.get("authorization") ?? "";
  try {
    admin = createAdminClient("voluntary-topup-refund");
    caller = createClient(
      Deno.env.get("SUPABASE_URL")!,
      callerPublishableKey(
        (name) => Deno.env.get(name),
        "CLEANSTREAM_TOPUP_REFUND_PUBLISHABLE_KEY_NAME",
      ),
      {
        global: { headers: { Authorization: bearer } },
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      },
    );
  } catch (error) {
    return errorResponse(error instanceof HttpError ? error : new HttpError(
      503, "Public key configuration unavailable", "key_configuration_unavailable",
    ));
  }
  const stripe = createStripeClient();
  const response = await handleVoluntaryTopupRefund(req, {
    authenticate: async () => {
      if (!/^Bearer\s+\S+$/i.test(bearer)) {
        throw new TopupRefundError(401, "session_invalid");
      }
      const { data, error } = await caller.auth.getUser(
        bearer.replace(/^Bearer\s+/i, ""),
      );
      if (error || !data.user) {
        throw new TopupRefundError(401, "session_invalid");
      }
    },
    callerRpc: async (name, args) => {
      const { data, error } = await caller.rpc(name, args);
      if (error) {
        const code = /^PT(400|401|403|404|409)$/.exec(error.code)?.[1];
        if (code) {
          throw new TopupRefundError(
            Number(code),
            {
              "400": "invalid_request",
              "401": "session_invalid",
              "403": "owner_or_location_forbidden",
              "404": "refund_unavailable",
              "409": "refund_conflict",
            }[code]!,
          );
        }
        throw new Error("Review unavailable");
      }
      return data;
    },
    prepare: async (id) => {
      const { data, error } = await admin.rpc(
        "prepare_voluntary_topup_refund",
        { p_id: id },
      );
      if (error) throw new Error("Dispatch unavailable");
      return data;
    },
    payment: (id) => stripe.paymentIntents.retrieve(id),
    refunds: async (intent) => {
      const result = [];
      let cursor: string | undefined;
      // A missing pagination boundary is not proof of complete refund history.
      while (true) {
        const page = await stripe.refunds.list({
          payment_intent: intent,
          limit: 100,
          ...(cursor ? { starting_after: cursor } : {}),
        });
        if (
          !page || page.object !== "list" || !Array.isArray(page.data) ||
          typeof page.has_more !== "boolean"
        ) throw new Error("Incomplete refund history");
        result.push(...page.data);
        if (result.length > 1000) {
          throw new Error("Refund history requires manual reconciliation");
        }
        if (!page.has_more) return result;
        const next = page.data.at(-1)?.id;
        if (
          typeof next !== "string" || !next.startsWith("re_") || next === cursor
        ) {
          throw new Error("Incomplete refund history");
        }
        cursor = next;
      }
    },
    retrieve: (id) => stripe.refunds.retrieve(id),
    create: (op) =>
      stripe.refunds.create({
        payment_intent: op.intent,
        amount: op.amount,
        reason: "requested_by_customer",
        metadata: {
          voluntary_topup_refund_id: op.id,
          policy_version: "unused-topup-v1",
        },
      }, { idempotencyKey: op.idempotency_key }),
    reconcile: async (op, refund) => {
      const { data, error } = await admin.rpc(
        "reconcile_voluntary_topup_refund",
        {
          p_id: op.id,
          p_refund_id: refund.id,
          p_status: refund.status,
          p_intent: typeof refund.payment_intent === "string"
            ? refund.payment_intent
            : refund.payment_intent?.id,
          p_amount: refund.amount,
          p_currency: refund.currency,
          p_livemode: op.livemode,
        },
      );
      if (error) throw new Error("Reconciliation unavailable");
      return data;
    },
  });
  return new Response(response.body, {
    status: response.status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

if (import.meta.main) Deno.serve(handler);
