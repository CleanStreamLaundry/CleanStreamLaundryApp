import { CortinaDeps, HttpError } from "../_shared/cortina.ts";
import { callerPublishableKey } from "../_shared/supabase_keys.ts";
import { captureFundingAdmission, FUNDING_PUBLIC_KEY_SELECTOR, FundingAdmissionError } from "../_shared/wallet_funding_admission.ts";

const publicSelector = "CLEANSTREAM_VEND_PUBLISHABLE_KEY_NAME";
const invalidSession = () => new HttpError(401, "session_invalid", "session_invalid");
const unavailable = () => new HttpError(503, "admission_unavailable", "admission_unavailable");

export async function resolveCardCaller(
  authorization: string | null,
  admin: CortinaDeps["admin"],
  env: (name: string) => string | undefined,
  transport: typeof fetch = fetch,
): Promise<{ userId: string | null; requireAdmission: () => Promise<void> }> {
  const guest = { userId: null, requireAdmission: () => Promise.resolve() };
  if (authorization === null) return guest;
  const token = /^Bearer (\S+)$/i.exec(authorization)?.[1];
  if (!token) throw invalidSession();
  let publicKey: string;
  try { publicKey = callerPublishableKey(env, publicSelector); } catch { throw unavailable(); }
  // Public SDK guest authorization is an exact configured key, never a prefix or decoded role.
  if (token === publicKey) return guest;

  const admission = captureFundingAdmission(new Request("https://admission.synthetic.invalid", {
    headers: { Authorization: authorization },
  }), (name) => env(name === FUNDING_PUBLIC_KEY_SELECTOR ? publicSelector : name), transport);
  let verified: Awaited<ReturnType<CortinaDeps["admin"]["auth"]["getUser"]>>;
  try { verified = await admin.auth.getUser(token); } catch { throw unavailable(); }
  if (verified.error) {
    const status = verified.error.status ?? 0;
    if (verified.error.name === "AuthRetryableFetchError" || status === 0 || status === 429 || status >= 500) {
      throw unavailable();
    }
    throw invalidSession();
  }
  const userId = verified.data.user?.id;
  if (!userId) throw invalidSession();
  return { userId, requireAdmission: async () => {
    try { await admission(userId); } catch (error) {
      if (error instanceof FundingAdmissionError) throw new HttpError(error.status, error.message, error.message);
      throw unavailable();
    }
  } };
}
