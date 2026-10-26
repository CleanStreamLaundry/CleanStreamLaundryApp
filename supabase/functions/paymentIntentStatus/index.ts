 import Stripe from "npm:stripe";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { selectNamedSupabaseKey } from "../_shared/supabase_keys.ts";
import { handlePaymentIntentStatus } from "./logic.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, apikey, x-client-info",
};

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2023-10-16",
});

class KeyConfigurationError extends Error {}

function createAdmin() {
  const url = Deno.env.get("SUPABASE_URL")!;
  const name = Deno.env.get("CLEANSTREAM_PAYMENT_INTENT_STATUS_SECRET_KEY_NAME");
  const key = name === undefined
    ? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    : selectNamedSupabaseKey(name, Deno.env.get("SUPABASE_SECRET_KEYS"), "secret");
  if (!key) throw new KeyConfigurationError("Payment status unavailable");
  const restUrl = new URL("rest/v1/", url.endsWith("/") ? url : `${url}/`).href;
  return createClient(url, key, name === undefined ? undefined : {
    global: {
      fetch: (input: RequestInfo | URL, init?: RequestInit) => {
        const request = new Request(input, init);
        // Keep caller Auth bearer; named database keys belong only in apikey.
        if (request.url.startsWith(restUrl)) request.headers.delete("Authorization");
        return fetch(request);
      },
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: CORS_HEADERS,
    });
  }

  try {
    const response = await handlePaymentIntentStatus(req, {
      stripe,
      supabaseAdmin: createAdmin(),
    });

    return new Response(response.body, {
      status: response.status,
      headers: { ...CORS_HEADERS, ...Object.fromEntries(response.headers) },
    });
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err));
    return new Response(
      JSON.stringify({ error: error.message ?? "Unknown error" }),
      {
        status: err instanceof KeyConfigurationError ? 503 : 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      }
    );
  }
});
