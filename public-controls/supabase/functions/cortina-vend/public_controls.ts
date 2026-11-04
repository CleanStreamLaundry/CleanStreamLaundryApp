import { errorResponse, HttpError } from "../_shared/cortina.ts";

export const MAX_CORTINA_BODY_BYTES = 8192;
export const CORTINA_BODY_TIMEOUT_MS = 5000;

// Bound the bytes actually received, including chunked requests with no length.
export async function readCortinaBody(req: Request): Promise<Record<string, unknown>> {
  if (req.signal.aborted) {
    void req.body?.cancel().catch(() => {});
    throw new HttpError(400, "Request body was interrupted", "invalid_json");
  }
  const tooLarge = () => new HttpError(413, "Request body is too large", "body_too_large");
  const length = req.headers.get("content-length");
  if (length && /^\d+$/.test(length) && Number(length) > MAX_CORTINA_BODY_BYTES) {
    void req.body?.cancel().catch(() => {});
    throw tooLarge();
  }
  if (!req.body) throw new HttpError(400, "Request body must be valid JSON", "invalid_json");

  const reader = req.body.getReader();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let abort: (() => void) | undefined;
  const interrupted = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new HttpError(
      408, "Request body was not received in time", "request_timeout",
    )), CORTINA_BODY_TIMEOUT_MS);
    abort = () => reject(new HttpError(400, "Request body was interrupted", "invalid_json"));
    req.signal.addEventListener("abort", abort, { once: true });
    if (req.signal.aborted) abort();
  });
  const bytes = new Uint8Array(MAX_CORTINA_BODY_BYTES);
  let size = 0;
  try {
    while (true) {
      const { done, value } = await Promise.race([reader.read(), interrupted]);
      if (done) break;
      if (value.byteLength > MAX_CORTINA_BODY_BYTES - size) throw tooLarge();
      bytes.set(value, size);
      size += value.byteLength;
    }
    const body: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes.subarray(0, size)));
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new HttpError(400, "Request body must be a JSON object", "invalid_body");
    }
    return body as Record<string, unknown>;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(400, "Request body must be valid JSON", "invalid_json");
  } finally {
    clearTimeout(timer);
    if (abort) req.signal.removeEventListener("abort", abort);
    // Cancellation must not extend the deadline by awaiting a stalled producer.
    void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export function cortinaSessionCredentials(body: Record<string, unknown>): {
  sessionId: string;
  accessToken: string;
} {
  const { sessionId, accessToken } = body;
  if (typeof sessionId !== "string" || !sessionId || typeof accessToken !== "string" || !accessToken) {
    throw new HttpError(400, "Missing session credentials", "missing_session");
  }
  // Tokens are opaque: retain historical tokens and never trim/case-fold a secret.
  // deno-lint-ignore no-control-regex -- Reject ASCII controls in opaque capabilities.
  const hasControlCharacters = /[\x00-\x1f\x7f]/.test(accessToken);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(sessionId) ||
    accessToken.length > 128 || hasControlCharacters) {
    throw new HttpError(400, "Invalid session credentials", "invalid_session_credentials");
  }
  return { sessionId, accessToken };
}

export function cortinaPublicResponse(response: Response): Response {
  response.headers.set("Cache-Control", "no-store");
  response.headers.set("Referrer-Policy", "no-referrer");
  return response;
}

export function cortinaPublicError(error: unknown): Response {
  // DB/provider diagnostics can include request data; never reflect them publicly.
  const safeError = error instanceof HttpError && error.status < 500 ? error
    : new HttpError(error instanceof HttpError ? error.status : 500,
      "Cortina request unavailable", error instanceof HttpError ? error.code ?? "internal_error" : "internal_error");
  return cortinaPublicResponse(errorResponse(safeError));
}
