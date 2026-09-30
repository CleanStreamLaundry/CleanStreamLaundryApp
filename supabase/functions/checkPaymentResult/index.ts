import { getPaymentStatusLogic, type PaymentDeps } from "./logic.ts";
import Stripe from "npm:stripe@^14.0.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, apikey, x-client-info",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};

function createDeps(): PaymentDeps {
  const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
    apiVersion: "2023-10-16",
  });
  return {
    retrieveSession: (id) =>
      stripe.checkout.sessions.retrieve(id, {
        expand: ["payment_intent"],
      }),
    supabaseAdmin: createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    ),
  };
}

export async function getPaymentStatus(req: Request, deps?: PaymentDeps) {
  if (req.method === "OPTIONS") return new Response(null, { headers });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method Not Allowed" }), {
      status: 405,
      headers,
    });
  }

  try {
    const response = await getPaymentStatusLogic(req, deps ?? createDeps());
    return new Response(response.body, { status: response.status, headers });
  } catch {
    return new Response(
      JSON.stringify({ error: "Payment status unavailable" }),
      {
        status: 503,
        headers,
      },
    );
  }
}

Deno.serve((req) => getPaymentStatus(req));
