import { callerPublishableKey } from "../_shared/supabase_keys.ts";

export class AvailabilityAdmissionError extends Error {
  constructor(readonly status: 401 | 403 | 503) {
    super(status === 401 ? "session_invalid" : status === 403 ? "account_restricted" : "admission_unavailable");
  }
}

// This read requires account eligibility, not funding's stronger Home/terms gate.
export function captureAvailabilityAdmission(
  request: Request,
  env: (name: string) => string | undefined,
  transport: typeof fetch = fetch,
) {
  const authorization = request.headers.get("Authorization");
  return async (subject: string): Promise<void> => {
    if (!authorization || !/^Bearer \S+$/i.test(authorization)) {
      throw new AvailabilityAdmissionError(401);
    }
    try {
      const url = env("SUPABASE_URL");
      if (!url) throw new AvailabilityAdmissionError(503);
      const response = await transport(`${url.replace(/\/$/, "")}/rest/v1/rpc/get_admission_status`, {
        method: "POST",
        headers: {
          apikey: callerPublishableKey(env, "CLEANSTREAM_AVAILABILITY_PUBLISHABLE_KEY_NAME"),
          Authorization: authorization,
          "Content-Type": "application/json",
        },
        body: "{}",
        redirect: "error",
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new AvailabilityAdmissionError(response.status === 401 ? 401 : response.status === 403 ? 403 : 503);
      }
      const admission: unknown = await response.json();
      if (!admission || typeof admission !== "object" || Array.isArray(admission)) {
        throw new AvailabilityAdmissionError(503);
      }
      const value = admission as Record<string, unknown>;
      if (typeof value.subject_id !== "string" || typeof value.account_access !== "string") {
        throw new AvailabilityAdmissionError(503);
      }
      if (!subject || value.subject_id !== subject) throw new AvailabilityAdmissionError(401);
      if (value.account_access !== "eligible") throw new AvailabilityAdmissionError(403);
    } catch (error) {
      if (error instanceof AvailabilityAdmissionError) throw error;
      throw new AvailabilityAdmissionError(503);
    }
  };
}
