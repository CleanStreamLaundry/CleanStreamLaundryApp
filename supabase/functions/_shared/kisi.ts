// Server-side inventory transport and local simulation. Customer access is
// phone-to-reader via the native Kisi SDK; hosted cloud unlock is disabled.
// This server module must never be bundled into Flutter.
export const KISI_SANDBOX_KEY = "cleanstream-local-kisi-only";

type CommonOptions = { fetcher?: typeof fetch; timeoutMs?: number };
export type KisiOptions = CommonOptions & (
  | { environment: "hosted"; apiKey: string }
  | { environment: "local-sandbox"; port?: number }
);
export type KisiErrorKind =
  | "invalid_input" | "unlock_disabled" | "unauthorized" | "denied"
  | "not_found" | "controller_unassigned" | "locked_down" | "offline"
  | "conflict" | "rate_limited" | "provider_error" | "invalid_response"
  | "transport_error" | "outcome_unknown";

export class KisiError extends Error {
  readonly kind: KisiErrorKind;
  readonly status: number | null;
  readonly providerCode: string | null;
  readonly retryAfterSeconds: number | null;

  constructor(kind: KisiErrorKind, status: number | null = null,
    providerCode: string | null = null, retryAfterSeconds: number | null = null) {
    // Do not echo provider bodies, request headers, keys, or transport errors.
    super(`Kisi request: ${kind}`);
    this.name = "KisiError";
    this.kind = kind;
    this.status = status;
    this.providerCode = providerCode;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

export interface KisiPlace { id: number; name: string }
export interface KisiLock extends KisiPlace {
  placeId: number;
  configured: boolean;
  online: boolean | null;
  unlocked: boolean;
  lockedDown: boolean;
}
export interface KisiPage<T> { items: T[]; nextOffset: number | null }
export interface KisiUnlockContext {
  location?: { latitude: number; longitude: number };
  proximityProof?: string;
}

function integer(value: unknown, min: number, max = Number.MAX_SAFE_INTEGER): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < min || value > max) {
    throw new KisiError("invalid_input");
  }
  return value;
}

function record(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new KisiError("invalid_response");
  }
  return value as Record<string, unknown>;
}

function place(value: unknown): KisiPlace {
  const row = record(value);
  if (!Number.isSafeInteger(row.id) || (row.id as number) < 1 || typeof row.name !== "string") {
    throw new KisiError("invalid_response");
  }
  return { id: row.id as number, name: row.name };
}

function lock(value: unknown): KisiLock {
  const row = record(value);
  if (!Number.isSafeInteger(row.place_id) || (row.place_id as number) < 1 ||
    typeof row.configured !== "boolean" || typeof row.unlocked !== "boolean" ||
    typeof row.locked_down !== "boolean" ||
    (typeof row.online !== "boolean" && row.online !== null)) {
    throw new KisiError("invalid_response");
  }
  return { ...place(value), placeId: row.place_id as number,
    configured: row.configured, online: row.online, unlocked: row.unlocked,
    lockedDown: row.locked_down };
}

function providerError(status: number, body: unknown, retryAfter: string | null): KisiError {
  const row = body && typeof body === "object" ? body as Record<string, unknown> : {};
  const code = typeof row.code === "string" && /^[a-f0-9]{6}$/.test(row.code) ? row.code : null;
  let kind: KisiErrorKind = "provider_error";
  // HTTP admission failures take precedence over any conflicting body code.
  if (status === 401) kind = "unauthorized";
  else if (status === 403) kind = "denied";
  else if (status === 404) kind = "not_found";
  else if (status === 429) kind = "rate_limited";
  else if (status === 409 || status === 503) {
    if (code === "ff420a" || (status === 409 && row.error === "The door has no assigned Kisi controller.")) {
      kind = "controller_unassigned";
    } else if (code === "fad001" || code === "fad002") kind = "locked_down";
    else if (["fad107", "fac001", "fac002", "fac003", "fac004"].includes(code ?? "")) kind = "offline";
    else kind = status === 409 ? "conflict" : "provider_error";
  }
  const seconds = retryAfter && /^\d+$/.test(retryAfter) ? Number(retryAfter) : null;
  return new KisiError(kind, status, code,
    seconds !== null && Number.isSafeInteger(seconds) ? seconds : null);
}

export class KisiClient {
  #origin: string;
  #key: string;
  #unlockEnabled: boolean;
  #fetcher: typeof fetch;
  #timeoutMs: number;

  constructor(options: KisiOptions) {
    this.#fetcher = options.fetcher ?? fetch;
    this.#timeoutMs = integer(options.timeoutMs ?? 10_000, 1, 60_000);
    if (options.environment === "local-sandbox") {
      this.#origin = `http://127.0.0.1:${integer(options.port ?? 8787, 1, 65535)}`;
      this.#key = KISI_SANDBOX_KEY;
      this.#unlockEnabled = true;
    } else {
      if (options.environment !== "hosted" || typeof options.apiKey !== "string" ||
        !options.apiKey || /\s/.test(options.apiKey) || options.apiKey === KISI_SANDBOX_KEY) {
        throw new KisiError("invalid_input");
      }
      this.#origin = "https://api.kisi.io";
      this.#key = options.apiKey;
      this.#unlockEnabled = false;
    }
  }

  async listPlaces(offset = 0, limit = 50): Promise<KisiPage<KisiPlace>> {
    return await this.#page("/places", place, offset, limit);
  }

  async listLocks(placeId: number, offset = 0, limit = 50): Promise<KisiPage<KisiLock>> {
    return await this.#page("/locks", lock, offset, limit, integer(placeId, 1));
  }

  async #page<T>(path: string, parse: (row: unknown) => T,
    offset: number, limit: number, placeId?: number): Promise<KisiPage<T>> {
    const query = new URLSearchParams({ offset: String(integer(offset, 0, 20000)),
      limit: String(integer(limit, 1, 250)) });
    if (placeId !== undefined) query.set("place_id", String(placeId));
    const { body, response } = await this.#request(`${path}?${query}`);
    if (!Array.isArray(body) || body.length > limit) throw new KisiError("invalid_response");
    const items = body.map(parse);
    // Refuse an unexpectedly broad response instead of displaying another place's doors.
    if (placeId !== undefined && items.some(item => (item as KisiLock).placeId !== placeId)) {
      throw new KisiError("invalid_response");
    }
    const range = response.headers.get("X-Collection-Range");
    const match = range?.match(/^(\d+)-(\d+)\/(\d+)$/);
    if (range !== null && (!match || Number(match[1]) !== offset ||
      Number(match[2]) !== offset + limit - 1 || !Number.isSafeInteger(Number(match[3])))) {
      throw new KisiError("invalid_response");
    }
    if (match && items.length !== Math.min(limit, Math.max(0, Number(match[3]) - offset))) {
      throw new KisiError("invalid_response");
    }
    const hasMore = match ? offset + items.length < Number(match[3]) : items.length === limit;
    if (hasMore && (items.length === 0 || offset + limit > 20000)) {
      throw new KisiError("invalid_response");
    }
    return { items, nextOffset: hasMore ? offset + limit : null };
  }

  async unlock(lockId: number, context: KisiUnlockContext = {}): Promise<{ outcome: "accepted" }> {
    integer(lockId, 1);
    if (!this.#unlockEnabled) throw new KisiError("unlock_disabled");
    const body: Record<string, unknown> = {};
    if (context.location !== undefined) {
      const { latitude, longitude } = context.location;
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        Math.abs(latitude) > 90 || Math.abs(longitude) > 180) throw new KisiError("invalid_input");
      body.context = { location: { latitude, longitude } };
    }
    if (context.proximityProof !== undefined) {
      if (typeof context.proximityProof !== "string" || !context.proximityProof.trim()) {
        throw new KisiError("invalid_input");
      }
      body.lock = { proximity_proof: context.proximityProof };
    }
    // One request only. A timeout/5xx cannot prove that the relay did not fire.
    const result = await this.#request(`/locks/${lockId}/unlock`, body);
    if (!result.body || typeof result.body !== "object" || Array.isArray(result.body) ||
      (result.body as Record<string, unknown>).message !== "Unlocked!") {
      throw new KisiError("outcome_unknown", 200);
    }
    return { outcome: "accepted" };
  }

  async #request(path: string, body?: Record<string, unknown>): Promise<{ response: Response; body: unknown }> {
    const mutation = body !== undefined;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeoutMs);
    try {
      const response = await this.#fetcher(this.#origin + path, {
        method: mutation ? "POST" : "GET", redirect: "manual", signal: controller.signal,
        headers: { Authorization: `KISI-LOGIN ${this.#key}`, Accept: "application/json",
          "Content-Type": "application/json" },
        ...(mutation ? { body: JSON.stringify(body) } : {}),
      });
      // No redirect following: never forward credentials or replay an unlock.
      let parsed: unknown;
      try { parsed = await response.json(); } catch { parsed = null; }
      if (response.status !== 200) {
        const error = providerError(response.status, parsed, response.headers.get("Retry-After"));
        if (mutation && (response.status >= 500 || response.status < 400)) {
          throw new KisiError("outcome_unknown", response.status, error.providerCode);
        }
        throw error;
      }
      if (parsed === null) throw new KisiError(mutation ? "outcome_unknown" : "invalid_response", 200);
      return { response, body: parsed };
    } catch (error) {
      if (error instanceof KisiError) throw error;
      throw new KisiError(mutation ? "outcome_unknown" : "transport_error");
    } finally { clearTimeout(timer); }
  }
}
