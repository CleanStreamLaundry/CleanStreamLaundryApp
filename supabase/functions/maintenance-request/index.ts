import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callerPublishableKey } from "../_shared/supabase_keys.ts";
import { handleMaintenance, type MaintenanceDeps } from "./logic.ts";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};

function createDeps(token: string): MaintenanceDeps {
  const storageUrl = Deno.env.get("SUPABASE_URL")!;
  const client = createClient(
    storageUrl,
    callerPublishableKey(
      (name) => Deno.env.get(name),
      "CLEANSTREAM_MAINTENANCE_PUBLISHABLE_KEY_NAME",
    ),
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    },
  );
  return {
    storageUrl,
    authenticate: async (token) => {
      const { data, error } = await client.auth.getUser(token);
      if (error) {
        if ([400, 401, 403].includes(error.status ?? 0)) return null;
        throw error;
      }
      return data.user;
    },
    submit: async (request) => {
      const { data, error } = await client.rpc("submit_maintenance_request", {
        p_request: request,
      });
      return { data, error };
    },
  };
}

export async function maintenanceRequest(req: Request, deps?: MaintenanceDeps) {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: { ...headers, "Content-Type": "text/plain" },
    });
  }
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Use POST.", code: "method_not_allowed" }),
      { status: 405, headers: { ...headers, Allow: "POST, OPTIONS" } },
    );
  }
  const result = await handleMaintenance(
    req,
    (token) => deps ?? createDeps(token),
  );
  return new Response(JSON.stringify(result.body), {
    status: result.status,
    headers,
  });
}

Deno.serve((req) => maintenanceRequest(req));
