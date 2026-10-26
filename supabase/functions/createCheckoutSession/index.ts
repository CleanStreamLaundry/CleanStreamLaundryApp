import Stripe from "npm:stripe@^14.0.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleCheckout } from "./logic.ts";
import { captureFundingAdmission, FundingAdmissionError, FUNDING_PUBLIC_KEY_SELECTOR } from "../_shared/wallet_funding_admission.ts";
import { callerPublishableKey, selectNamedSupabaseKey } from "../_shared/supabase_keys.ts";
import { NewPaymentsUnavailableError } from "../_shared/new_payment_control.ts";
import { ActionConsentError, captureWalletLoadConsent } from "../_shared/loyalty_action_consent.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
};

export async function checkoutHandler(req: Request): Promise<Response> {
  const env = (name: string) => Deno.env.get(name);
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const keyName = env("CLEANSTREAM_CHECKOUT_SECRET_KEY_NAME");
    const key = keyName === undefined ? env("SUPABASE_SERVICE_ROLE_KEY")
      : selectNamedSupabaseKey(keyName, env("SUPABASE_SECRET_KEYS"), "secret");
    if (!key) return new Response(JSON.stringify({ error: "Server configuration unavailable" }), {
      status: 503, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");

    const stripe = new Stripe(env("STRIPE_SECRET_KEY")!, {
      apiVersion: "2023-10-16",
      httpClient: Stripe.createFetchHttpClient(),
    });

    const supabase = createClient(
      env("SUPABASE_URL")!,
      callerPublishableKey(env, FUNDING_PUBLIC_KEY_SELECTOR),
      { auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: token ? { Authorization: `Bearer ${token}` } : {} } }
    );

    const supabaseAdmin = createClient(
      env("SUPABASE_URL")!, key,
      { auth: { persistSession: false, autoRefreshToken: false },
        global: { fetch: (input, init) => {
          const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
          if (keyName !== undefined && headers.get("Authorization") === `Bearer ${key}`) {
            headers.delete("Authorization");
          }
          return fetch(input, { ...init, headers });
        } } }
    );

    const response = await handleCheckout(req, {
      stripe,
      supabase,
      supabaseAdmin,
      fundingAdmission: captureFundingAdmission(req, env),
      walletLoadConsent: captureWalletLoadConsent(req, env),
    });

    return new Response(response.body, {
      status: response.status,
      headers: { ...CORS_HEADERS, ...Object.fromEntries(response.headers) },
    });
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err));
    const status = err instanceof ActionConsentError ? err.status : err instanceof NewPaymentsUnavailableError ? 503 : err instanceof FundingAdmissionError ? err.status : error.message === "Unauthorized" ? 401 : 400;
    return new Response(JSON.stringify({ error: error.message }), {
      status,
      headers: CORS_HEADERS,
    });
  }
}

if (import.meta.main) Deno.serve(checkoutHandler);
