import { getPaymentStatusLogic, type PaymentDeps } from "./logic.ts";
import Stripe from "npm:stripe@^14.0.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { selectNamedSupabaseKey } from "../_shared/supabase_keys.ts";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, apikey, x-client-info",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};

function createDeps(): PaymentDeps {
  const url = Deno.env.get("SUPABASE_URL")!;
  const name = Deno.env.get("CLEANSTREAM_CHECK_PAYMENT_RESULT_SECRET_KEY_NAME");
  const key = name === undefined
    ? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    : selectNamedSupabaseKey(name, Deno.env.get("SUPABASE_SECRET_KEYS"), "secret");
  if (!key) throw new Error("Payment status unavailable");
  const restUrl = new URL("rest/v1/", url.endsWith("/") ? url : `${url}/`).href;
  const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
    apiVersion: "2023-10-16",
  });
  return {
    retrieveSession: (id) =>
      stripe.checkout.sessions.retrieve(id, {
        expand: ["payment_intent"],
      }),
    supabaseAdmin: createClient(
      url,
      key,
      {
        auth: { persistSession: false, autoRefreshToken: false },
        ...(name === undefined ? {} : {
          global: {
            fetch: (input: RequestInfo | URL, init?: RequestInit) => {
              const request = new Request(input, init);
              // Keep caller Auth bearer; named database keys belong only in apikey.
              if (request.url.startsWith(restUrl)) request.headers.delete("Authorization");
              return fetch(request);
            },
          },
        }),
      },
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
