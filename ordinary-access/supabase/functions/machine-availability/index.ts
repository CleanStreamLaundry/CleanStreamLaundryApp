import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.97.0";
import { selectNamedSupabaseKey } from "../_shared/supabase_keys.ts";
import { deriveAvailability, summarize, type RecordData } from "./logic.ts";
import { AvailabilityAdmissionError, captureAvailabilityAdmission } from "./admission.ts";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
function createAdmin() {
  const url = Deno.env.get("SUPABASE_URL")!;
  const name = Deno.env.get("CLEANSTREAM_AVAILABILITY_SECRET_KEY_NAME");
  const key = name === undefined
    ? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    : selectNamedSupabaseKey(name, Deno.env.get("SUPABASE_SECRET_KEYS"), "secret");
  if (!key) throw new Error("Availability key configuration unavailable");
  const restUrl = new URL("rest/v1/", url.endsWith("/") ? url : `${url}/`).href;
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    ...(name === undefined ? {} : {
      global: {
        fetch: (input: RequestInfo | URL, init?: RequestInit) => {
          const request = new Request(input, init);
          // Modern DB keys belong only in apikey; Auth keeps the caller bearer.
          if (request.url.startsWith(restUrl)) {
            request.headers.delete("Authorization");
          }
          return fetch(request);
        },
      },
    }),
  });
}
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
class ProviderError extends Error {
  constructor(readonly status: number, readonly detail: string) { super(`provider_http_${status}`); }
}

async function nayax(path: string, requireAdmission: () => Promise<void>): Promise<unknown> {
  const token = Deno.env.get("NAYAX_LYNX_TOKEN");
  if (!token) throw new Error("not_configured");
  const base = Deno.env.get("NAYAX_LYNX_BASE_URL") ?? "https://lynx.nayax.com/operational";
  if (!["https://lynx.nayax.com/operational", "https://qa-lynx.nayax.com/operational"].includes(base)) throw new Error("not_configured");
  await requireAdmission();
  const response = await fetch(`${base}${path}`, { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(5000), redirect: "error" });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    const message = typeof payload?.message === "string" ? payload.message : "Request rejected";
    const correlationId = typeof payload?.correlationId === "string" ? payload.correlationId : null;
    const detail = JSON.stringify({ path, message: message.slice(0, 200), correlationId }).replaceAll(token, "[redacted]").replace(/Bearer\s+\S+/gi, "Bearer [redacted]");
    throw new ProviderError(response.status, detail);
  }
  return await response.json();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const authorization = req.headers.get("Authorization");
    const token = authorization?.match(/^Bearer (\S+)$/i)?.[1];
    if (!token) return json({ error: "Sign in required" }, 401);
    const checkAdmission = captureAvailabilityAdmission(req, (name) => Deno.env.get(name));
    const admin = createAdmin();
    const { data: auth, error: authError } = await admin.auth.getUser(token);
    if (authError || !auth.user) return json({ error: "Sign in required" }, 401);
    const subject = auth.user.id;
    const requireAdmission = () => checkAdmission(subject);
    const body = await req.json().catch(() => null);
    const locationId = Number(body?.locationId);
    if (!Number.isSafeInteger(locationId) || locationId <= 0) return json({ error: "Invalid location" }, 400);
    await requireAdmission();
    // Inventory is already readable by customers; device credentials and mappings remain server-side.
    const { data: machines, error } = await admin.from("Machines").select('id,Name,Machine_type,Status,Location_ID').eq("Location_ID", locationId);
    if (error) throw error;
    if (!machines?.length) {
      await requireAdmission();
      return json({ ...summarize([], [], Date.now()), configured: Boolean(Deno.env.get("NAYAX_LYNX_TOKEN")) });
    }
    const ids = machines.map((m) => m.id);
    const [{ data: configs, error: configError }, { data: previous, error: stateError }] = await Promise.all([
      admin.from("cortina_machine_config").select("machine_id,nayax_terminal_id,is_enabled").in("machine_id", ids).eq("is_enabled", true),
      admin.from("nayax_availability_state").select("*").in("machine_id", ids),
    ]);
    if (configError || stateError) throw configError ?? stateError;
    await requireAdmission();
    const { data: lease, error: leaseError } = await admin.rpc("claim_nayax_availability_sync", { p_location_id: locationId });
    if (leaseError) throw leaseError;
    if (lease) {
      const observedAt = new Date().toISOString();
      const states: RecordData[] = [];
      // Small bounded batches avoid one request per client and unbounded fan-out on large locations.
      for (let offset = 0; offset < machines.length; offset += 4) {
        const batch = await Promise.all(machines.slice(offset, offset + 4).map(async (machine) => {
          const config = configs?.find((c) => c.machine_id === machine.id);
          const serial = config?.nayax_terminal_id;
          const old = previous?.find((s) => s.machine_id === machine.id && s.device_serial === serial);
          const row: RecordData = { machine_id: machine.id, device_serial: serial ?? null, nayax_machine_id: old?.device_serial === serial ? old.nayax_machine_id : null, checked_at: observedAt, status: "unknown", event_at: old?.event_at ?? null, event_code: old?.event_code ?? null, reason: "not_connected", reconcile_after: old?.reconcile_after ?? null };
          if (!serial) return row;
          // An account permission failure will not improve with five-second retries.
          if (old && /^provider_http_(401|403):/.test(old.reason ?? "") && Date.now() - Date.parse(old.checked_at) < 60_000) return old;
          // One Inhibit input cannot safely identify multiple independently mapped machines.
          const { count: mappings, error: mappingError } = await admin.from("cortina_machine_config").select("machine_id", { count: "exact", head: true }).eq("nayax_terminal_id", serial).eq("is_enabled", true);
          if (mappingError || mappings !== 1) return { ...row, reason: "ambiguous_mapping" };
          try {
            if (!row.nayax_machine_id) {
              const machineInfo = await nayax(`/v1/devices/${encodeURIComponent(serial)}/machine`, requireAdmission) as RecordData;
              const id = Number(machineInfo?.MachineID);
              if (!Number.isSafeInteger(id) || id <= 0) throw new Error("invalid_mapping");
              row.nayax_machine_id = id;
            }
            const results = await Promise.allSettled([
              nayax(`/v1/machines/${row.nayax_machine_id}/lastAlerts`, requireAdmission),
              nayax(`/v1/machines/${row.nayax_machine_id}/status`, requireAdmission),
            ]);
            const failures = results.filter((r) => r.status === "rejected");
            if (failures.length) {
              const admissionFailure = failures.find((failure) => failure.reason instanceof AvailabilityAdmissionError);
              if (admissionFailure) throw admissionFailure.reason;
              const first = failures[0].reason;
              if (first instanceof ProviderError) throw new ProviderError(first.status, failures.map((f) => f.reason instanceof ProviderError ? f.reason.detail : "Connection failed").join("; "));
              throw first;
            }
            const [alerts, stats] = results.map((r) => r.status === "fulfilled" ? r.value : undefined);
            if (!Array.isArray(alerts) || !stats || typeof stats !== "object") throw new Error("invalid_response");
            const result = deriveAvailability(alerts, stats as RecordData, Date.now(), old?.device_serial === serial ? old : undefined);
            if (result.reason === "offline" && !row.reconcile_after) row.reconcile_after = observedAt;
            if (!result.reason) row.reconcile_after = null;
            return { ...row, ...result, event_at: result.event_at ?? row.event_at, event_code: result.event_code ?? row.event_code };
          } catch (e) {
            if (e instanceof AvailabilityAdmissionError) throw e;
            // Provider details stay in the service-only cache, never the client response.
            const reason = e instanceof ProviderError ? `${e.message}: ${e.detail}` : e instanceof Error && ["not_configured", "invalid_mapping"].includes(e.message) ? e.message : "connection_error";
            return { ...row, reason };
          }
        }));
        states.push(...batch);
      }
      const { error: saveError } = await admin.rpc("finish_nayax_availability_sync", { p_location_id: locationId, p_lease: lease, p_states: states });
      if (saveError) throw saveError;
    }
    const { data: states, error: readError } = await admin.from("nayax_availability_state").select("*").in("machine_id", ids);
    if (readError) throw readError;
    await requireAdmission();
    return json({ ...summarize(machines, states ?? [], Date.now()), configured: Boolean(Deno.env.get("NAYAX_LYNX_TOKEN")), refreshing: !lease && (states?.length ?? 0) < machines.length });
  } catch (error) {
    if (error instanceof AvailabilityAdmissionError && error.status !== 503) {
      return json({ error: error.status === 401 ? "Sign in required" : "Account access restricted" }, error.status);
    }
    // Never send provider errors, authorization headers, or credentials back to the phone.
    return json({ error: "Unable to check machine availability. Please try again." }, 503);
  }
});
