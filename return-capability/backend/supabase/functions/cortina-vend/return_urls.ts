import { HttpError } from "../_shared/cortina.ts";

export function cortinaReturnUrls(
  payUrl: string,
  reference: { sessionId: string; accessToken: string },
  selector: { machineToken?: unknown; terminalId?: unknown; uniQr?: unknown },
): { success_url: string; cancel_url: string } {
  let base: URL;
  try {
    base = new URL(payUrl);
    if (!["https:", "http:"].includes(base.protocol) || base.username || base.password) throw new Error();
  } catch {
    throw new HttpError(503, "Payment return configuration unavailable", "return_configuration_unavailable");
  }
  base.hash = "";
  for (const key of ["session", "access", "cortina_return", "machine", "terminal", "uniqr"]) base.searchParams.delete(key);
  const success = new URL(base);
  // The marker keeps a missing/stripped fragment support-only, never a fresh checkout.
  success.searchParams.set("cortina_return", "1");
  success.hash = new URLSearchParams({ session: reference.sessionId, access: reference.accessToken }).toString();

  const cancel = new URL(base);
  if (selector.machineToken) cancel.searchParams.set("machine", String(selector.machineToken));
  else if (selector.terminalId) cancel.searchParams.set("terminal", String(selector.terminalId));
  else cancel.searchParams.set("uniqr", String(selector.uniQr ?? ""));
  return { success_url: success.toString(), cancel_url: cancel.toString() };
}
