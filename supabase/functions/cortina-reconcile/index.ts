import Stripe from "npm:stripe@14.25.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.97.0";
import { sha256 } from "../_shared/cortina.ts";
import { selectNamedSupabaseKey } from "../_shared/supabase_keys.ts";
import { reconcileOneCortinaSession, type ReconciliationDeps } from "../_shared/cortina_reconciliation.ts";

type Env = (name: string) => string | undefined;
const json = (body: unknown, status = 200) => Response.json(body, {
  status, headers: { "Cache-Control": "no-store" },
});

export function reconciliationDependencies(env: Env): ReconciliationDeps {
  const keyName = env("CLEANSTREAM_CORTINA_RECONCILIATION_SECRET_KEY_NAME");
  const key = keyName === undefined ? env("SUPABASE_SERVICE_ROLE_KEY")
    : selectNamedSupabaseKey(keyName, env("SUPABASE_SECRET_KEYS"), "secret");
  if (!key) throw new Error("Database key configuration unavailable");
  const admin = createClient(env("SUPABASE_URL")!, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: (input, init) => {
      const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
      // Modern secret keys belong in apikey, not a JWT bearer header.
      if (keyName !== undefined) headers.delete("Authorization");
      return fetch(input, { ...init, headers, signal: AbortSignal.timeout(8000) });
    } },
  });
  let client: Stripe | undefined;
  const stripe = () => client ??= new Stripe(env("STRIPE_SECRET_KEY")!, {
    apiVersion: "2023-10-16", httpClient: Stripe.createFetchHttpClient(),
    timeout: 8000, maxNetworkRetries: 0,
  });
  return {
    claim: async (environment) => {
      const { data, error } = await admin.rpc("claim_cortina_reconciliation", { p_environment: environment });
      if (error) throw new Error("Claim unavailable");
      return data;
    },
    finish: async (session, observation) => {
      const { data, error } = await admin.rpc("finish_cortina_reconciliation", {
        p_session: session.id, p_claim: session.reconcile_claim,
        p_outcome: observation.outcome, p_reason: observation.reason, p_evidence: observation.evidence,
      });
      if (error || typeof data !== "boolean") throw new Error("Finish outcome unknown");
      return data;
    },
    payment: (id) => stripe().paymentIntents.retrieve(id),
    checkout: (id) => stripe().checkout.sessions.retrieve(id),
    refund: (id) => stripe().refunds.retrieve(id),
  };
}

export function reconciliationHandler(
  env: Env,
  dependencies: () => ReconciliationDeps = () => reconciliationDependencies(env),
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const secret = env("CORTINA_RECONCILIATION_WORKER_SECRET") ?? "";
    if (secret.trim().length < 32 || await sha256(request.headers.get("authorization") ?? "") !==
      await sha256(`Bearer ${secret}`)) return json({ error: "unauthorized" }, 401);
    if (env("CORTINA_RECONCILIATION_ENABLED") !== "true") return json({ error: "reconciliation_disabled" }, 503);
    const environment = env("CORTINA_RECONCILIATION_ENVIRONMENT");
    if (environment !== "sandbox" && environment !== "production") return json({ error: "environment_not_configured" }, 503);
    try {
      // Fixed one-row budget. Body/query parameters cannot select sessions,
      // override environment, enlarge the batch, or authorize a provider write.
      return json(await reconcileOneCortinaSession(environment, dependencies()));
    } catch {
      return json({ error: "reconciliation_outcome_unknown" }, 503);
    }
  };
}

if (import.meta.main) Deno.serve(reconciliationHandler((name) => Deno.env.get(name)));
