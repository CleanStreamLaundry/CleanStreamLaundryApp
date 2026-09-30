export type MailKind =
  | "account_welcome"
  | "newsletter_confirm"
  | "newsletter_welcome";
export interface MailJob {
  id: string;
  lease_id: string;
  kind: MailKind;
  email: string;
  consent_id: string | null;
}
export interface NewsletterStatus {
  subject_id: string;
  state:
    | "not_subscribed"
    | "pending"
    | "expired"
    | "subscribed"
    | "unsubscribed"
    | "suppressed";
  requested_at: string | null;
  confirmed_at: string | null;
  unsubscribed_at: string | null;
  consent_version: string;
  consent_text: string;
  enabled: boolean;
}
export type NewsletterRequest =
  | { action: "status" | "withdraw" }
  | {
    action: "request";
    opt_in: boolean;
    version: string;
    source: "signup" | "settings";
  }
  | { action: "confirm" | "unsubscribe"; token: string };
export type Env = (name: string) => string | undefined;
export type Rpc = <T>(
  name: string,
  args?: Record<string, unknown>,
  bearer?: string,
) => Promise<T>;
export class MailError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
export interface MailConfig {
  key: string;
  from: string;
  replyTo: string;
  postal: string;
  publicUrl: string;
  pageUrl: string;
  tokenSecret: string;
}

export function newsletterPage(env: Env): string | null {
  const value = env("CLEANSTREAM_NEWSLETTER_PAGE_URL");
  if (!value || env("CLEANSTREAM_MAIL_LINKS_APPROVED") !== "true") return null;
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:" || url.username || url.password || url.search ||
      url.hash ||
      !/(^|\.)cleanstreamlaundry\.com$/.test(url.hostname) ||
      !(env("CLEANSTREAM_MAIL_CORS_ORIGINS") || "").split(",").includes(
        url.origin,
      )
    ) return null;
    return value;
  } catch {
    return null;
  }
}

export function mailConfig(env: Env): MailConfig | null {
  const key = env("CLEANSTREAM_RESEND_API_KEY") || "";
  const from = env("CLEANSTREAM_MAIL_FROM") || "";
  const replyTo = env("CLEANSTREAM_MAIL_REPLY_TO") || "";
  const postal = env("CLEANSTREAM_MAIL_POSTAL_ADDRESS") || "";
  const publicUrl = env("CLEANSTREAM_NEWSLETTER_URL") || "";
  const tokenSecret = env("CLEANSTREAM_MAIL_TOKEN_SECRET") || "";
  const project = env("CLEANSTREAM_MAIL_PROJECT_URL");
  const pageUrl = newsletterPage(env);
  const address =
    /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@(?:[a-z0-9-]+\.)*cleanstreamlaundry\.com$/;
  if (
    env("CLEANSTREAM_MAIL_ENABLED") !== "true" || !key.startsWith("re_") ||
    !address.test(from) || !address.test(replyTo) ||
    env("CLEANSTREAM_MAIL_VERIFIED_FROM") !== from ||
    env("CLEANSTREAM_MAIL_CONTENT_APPROVED") !== "true" ||
    !postal.trim() || postal.length > 500 || tokenSecret.length < 43 ||
    !project || project !== env("SUPABASE_URL") || !pageUrl
  ) return null;
  try {
    const url = new URL(publicUrl);
    if (
      url.protocol !== "https:" || url.username || url.password || url.search ||
      url.hash ||
      url.origin !== new URL(project).origin ||
      url.pathname !== "/functions/v1/newsletter"
    ) return null;
  } catch {
    return null;
  }
  return { key, from, replyTo, postal, publicUrl, pageUrl, tokenSecret };
}

const enc = new TextEncoder();
const hex = (b: ArrayBuffer) =>
  Array.from(new Uint8Array(b), (x) => x.toString(16).padStart(2, "0")).join(
    "",
  );
export async function sha256(value: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", enc.encode(value)));
}
export async function token(
  secret: string,
  purpose: "confirm" | "unsubscribe",
  id: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(
    await crypto.subtle.sign(
      "HMAC",
      key,
      enc.encode(`cleanstream-mail-v1:${purpose}:${id}`),
    ),
  );
}
export async function equalSecret(a: string, b: string): Promise<boolean> {
  const x = await sha256(a), y = await sha256(b);
  let difference = 0;
  for (let i = 0; i < x.length; i++) {
    difference |= x.charCodeAt(i) ^ y.charCodeAt(i);
  }
  return difference === 0;
}
export const escapeHtml = (s: string) =>
  s.replace(
    /[&<>"']/g,
    (c) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[c]!),
  );

export async function renderMail(job: MailJob, config: MailConfig) {
  let subject = "Welcome to Clean Stream";
  let text =
    "Your email address is verified. Welcome to Clean Stream. This account notice does not subscribe you to our newsletter.";
  const headers: Record<string, string> = {};
  let confirmHash: string | null = null, unsubscribeHash: string | null = null;
  if (job.kind !== "account_welcome") {
    if (!job.consent_id) throw new Error("Missing consent");
    const confirm = await token(config.tokenSecret, "confirm", job.consent_id);
    const unsubscribe = await token(
      config.tokenSecret,
      "unsubscribe",
      job.consent_id,
    );
    const link = (action: string, capability: string) =>
      `${config.pageUrl}#action=${action}&token=${capability}`;
    const unsubscribeUrl = link("unsubscribe", unsubscribe);
    const oneClickUrl =
      `${config.publicUrl}?action=unsubscribe&token=${unsubscribe}`;
    unsubscribeHash = await sha256(unsubscribe);
    if (job.kind === "newsletter_confirm") {
      subject = "Confirm your Clean Stream newsletter request";
      text =
        `You requested the Clean Stream newsletter. Confirm your choice using this link within 24 hours of your request:\n${
          link("confirm", confirm)
        }\n\nIf you did not request this, ignore this message. You are not subscribed yet.`;
      confirmHash = await sha256(confirm);
    } else {
      subject = "Welcome to the Clean Stream newsletter";
      text =
        "Your newsletter subscription is confirmed. Thank you for choosing to hear from Clean Stream.";
    }
    text +=
      `\n\nUnsubscribe: ${unsubscribeUrl}\nClean Stream\n${config.postal}`;
    headers["List-Unsubscribe"] = `<${oneClickUrl}>`;
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click";
  }
  text += `\n\nContact: ${config.replyTo}`;
  const html =
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${
      escapeHtml(subject)
    }</title></head><body><h1>${escapeHtml(subject)}</h1><p>${
      escapeHtml(text).replace(/https:\/\/[^\s<]+/g, (url) =>
        `<a href="${url}">${url}</a>`).replace(/\n/g, "<br>")
    }</p></body></html>`;
  const payload = {
    from: `Clean Stream <${config.from}>`,
    to: [job.email],
    reply_to: config.replyTo,
    subject,
    text,
    html,
    headers,
    tags: [{ name: "outbox_id", value: job.id }],
  };
  return {
    payload,
    confirmHash,
    unsubscribeHash,
    payloadHash: await sha256(JSON.stringify(payload)),
  };
}

export function databaseRpc(env: Env, transport: typeof fetch = fetch): Rpc {
  return async <T>(
    name: string,
    args: Record<string, unknown> = {},
    bearer?: string,
  ): Promise<T> => {
    const url = env("SUPABASE_URL");
    const key = env(bearer ? "SUPABASE_ANON_KEY" : "SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key || env("CLEANSTREAM_MAIL_PROJECT_URL") !== url) {
      throw new MailError(503, "mail_unavailable");
    }
    const response = await transport(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: bearer || `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(args),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) {
      const status = [400, 401, 403, 429].includes(response.status)
        ? response.status
        : 503;
      throw new MailError(
        status,
        status === 429 ? "newsletter_rate_limited" : "mail_request_failed",
      );
    }
    const raw = await response.text();
    return (raw ? JSON.parse(raw) : null) as T;
  };
}

// Dispatch exactly once per claimed attempt. Only an explicit rate-limit rejection
// is automatically retryable. All ambiguous acceptance goes to reconciliation.
export async function deliverOne(
  rpc: Rpc,
  config: MailConfig,
  transport: typeof fetch = fetch,
): Promise<string> {
  const job = await rpc<MailJob | null>("mail_claim");
  if (!job) return "idle";
  const rendered = await renderMail(job, config);
  const prepared = await rpc<boolean>("mail_prepare", {
    p_id: job.id,
    p_lease: job.lease_id,
    p_payload_hash: rendered.payloadHash,
    p_confirm_hash: rendered.confirmHash,
    p_unsubscribe_hash: rendered.unsubscribeHash,
  });
  if (!prepared) return "skipped";
  let result = "uncertain", providerId: string | null = null;
  try {
    const response = await transport("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.key}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `cleanstream/${job.id}`,
      },
      body: JSON.stringify(rendered.payload),
      signal: AbortSignal.timeout(10000),
    });
    if (response.ok) {
      const body = await response.json();
      if (
        typeof body.id === "string" && body.id.length > 0 &&
        body.id.length <= 200
      ) {
        result = "accepted";
        providerId = body.id;
      }
    } else if (response.status === 429) result = "rate_limited";
    else if ([400, 401, 403, 404, 422].includes(response.status)) {
      result = "failed";
    }
  } catch { /* May already be accepted: never replay here. */ }
  await rpc("mail_finish", {
    p_id: job.id,
    p_lease: job.lease_id,
    p_result: result,
    p_provider_id: providerId,
  });
  return result;
}

export async function readBounded(
  request: Request,
  limit: number,
): Promise<string> {
  const reader = request.body?.getReader();
  if (!reader) return "";
  let size = 0;
  const parts: Uint8Array[] = [];
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.length;
      if (size > limit) {
        await reader.cancel();
        throw new MailError(413, "body_too_large");
      }
      parts.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const part of parts) {
    bytes.set(part, offset);
    offset += part.length;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

export function json(
  body: unknown,
  status = 200,
  headers: HeadersInit = {},
): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      ...headers,
    },
  });
}

// Svix's documented HMAC algorithm, verified by the official published test vector.
// Raw bytes are decoded strictly and never parsed/re-serialized before verification.
export async function verifyWebhook(
  raw: string,
  headers: Headers,
  secret: string,
  now = Date.now(),
): Promise<void> {
  const id = headers.get("svix-id") || "",
    timestamp = headers.get("svix-timestamp") || "";
  const signatures = headers.get("svix-signature") || "";
  if (
    !id || id.length > 200 || !/^\d{1,12}$/.test(timestamp) ||
    Math.abs(now / 1000 - Number(timestamp)) > 300 ||
    !secret.startsWith("whsec_") || signatures.length > 2000
  ) {
    throw new MailError(400, "invalid_signature");
  }
  try {
    const bytes = Uint8Array.from(
      atob(secret.slice(6)),
      (c) => c.charCodeAt(0),
    );
    const key = await crypto.subtle.importKey(
      "raw",
      bytes,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    for (const signature of signatures.split(" ")) {
      const [version, value] = signature.split(",");
      if (version !== "v1" || !value) continue;
      let signed: Uint8Array<ArrayBuffer>;
      try {
        signed = Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
      } catch {
        continue;
      }
      if (
        await crypto.subtle.verify(
          "HMAC",
          key,
          signed,
          enc.encode(`${id}.${timestamp}.${raw}`),
        )
      ) return;
    }
  } catch { /* Fail closed on malformed secrets and signatures. */ }
  throw new MailError(400, "invalid_signature");
}
