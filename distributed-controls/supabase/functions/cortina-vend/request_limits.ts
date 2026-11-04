import { HttpError } from "../_shared/cortina.ts";
import { cortinaPublicError } from "./public_controls.ts";

type CapacityBucket = "quote" | "card" | "status";
interface CapacityClient {
  rpc(name: "consume_cortina_request_capacity", args: { p_bucket: CapacityBucket }): {
    abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }>;
  };
}

export const CORTINA_CAPACITY_TIMEOUT_MS = 2000;

// Fixed route budgets shared by all instances; never derive a bucket from caller headers.
export async function cortinaRequestCapacity(
  admin: CapacityClient,
  bucket: CapacityBucket,
): Promise<Response | null> {
  let decision: { allowed: boolean; retry_after_seconds: number };
  try {
    const { data, error } = await admin.rpc("consume_cortina_request_capacity", { p_bucket: bucket })
      .abortSignal(AbortSignal.timeout(CORTINA_CAPACITY_TIMEOUT_MS));
    if (error || !data || typeof data !== "object" || Array.isArray(data)) throw new Error();
    const result = data as Record<string, unknown>;
    const retry = result.retry_after_seconds;
    if (typeof result.allowed !== "boolean" || typeof retry !== "number" || !Number.isSafeInteger(retry) ||
      (result.allowed ? retry !== 0 : retry < 1 || retry > 6)) throw new Error();
    decision = { allowed: result.allowed, retry_after_seconds: retry };
  } catch {
    // Includes missing schema, lock timeout, aborted transport and malformed RPC output.
    throw new HttpError(503, "Cortina capacity unavailable", "capacity_unavailable");
  }
  if (decision.allowed) return null;
  const response = cortinaPublicError(new HttpError(429, "Cortina request capacity exceeded", "capacity_exceeded"));
  response.headers.set("Retry-After", String(decision.retry_after_seconds));
  response.headers.set("Access-Control-Expose-Headers", "Retry-After");
  return response;
}
