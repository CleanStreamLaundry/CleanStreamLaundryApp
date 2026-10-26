import { callerPublishableKey } from "./supabase_keys.ts";

export type FundingAdmission = (subject: string) => Promise<void>;
export const FUNDING_PUBLIC_KEY_SELECTOR =
  "CLEANSTREAM_FUNDING_PUBLISHABLE_KEY_NAME";

export class FundingAdmissionError extends Error {
  constructor(public readonly status: 401 | 403 | 503) {
    super(
      status === 401
        ? "session_invalid"
        : status === 403
        ? "account_restricted"
        : "admission_unavailable",
    );
  }
}

// Both human funding adapters use this same request-bound, public-key RPC.
// Never substitute the service client's identity or decode claims locally.
export function captureFundingAdmission(
  request: Request,
  env: (name: string) => string | undefined,
  transport: typeof fetch = fetch,
): FundingAdmission {
  const authorization = request.headers.get("Authorization");
  return async (subject) => {
    if (!authorization || !/^Bearer \S+$/i.test(authorization)) {
      throw new FundingAdmissionError(401);
    }
    try {
      const url = env("SUPABASE_URL");
      if (!url) throw new FundingAdmissionError(503);
      const response = await transport(
        `${url.replace(/\/$/, "")}/rest/v1/rpc/get_admission_status`,
        {
          method: "POST",
          headers: {
            apikey: callerPublishableKey(env, FUNDING_PUBLIC_KEY_SELECTOR),
            Authorization: authorization,
            "Content-Type": "application/json",
          },
          body: "{}",
          redirect: "error",
          signal: AbortSignal.timeout(8000),
        },
      );
      if (!response.ok) {
        await response.body?.cancel();
        throw new FundingAdmissionError(
          response.status === 401 ? 401 : response.status === 403 ? 403 : 503,
        );
      }
      const data: unknown = await response.json();
      if (!data || typeof data !== "object" || Array.isArray(data)) {
        throw new FundingAdmissionError(503);
      }
      const admission = data as Record<string, unknown>;
      if (
        typeof admission.subject_id !== "string" ||
        typeof admission.account_access !== "string" ||
        typeof admission.next_step !== "string"
      ) throw new FundingAdmissionError(503);
      if (!subject || admission.subject_id !== subject) {
        throw new FundingAdmissionError(401);
      }
      if (
        admission.account_access !== "eligible" ||
        admission.next_step !== "home"
      ) {
        throw new FundingAdmissionError(403);
      }
    } catch (error) {
      if (error instanceof FundingAdmissionError) throw error;
      throw new FundingAdmissionError(503);
    }
  };
}

export async function requireFundingAdmission(
  check: FundingAdmission | undefined,
  subject: string,
) {
  if (!check) throw new FundingAdmissionError(503);
  await check(subject);
}
