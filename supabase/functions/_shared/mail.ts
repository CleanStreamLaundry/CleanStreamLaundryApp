import { selectNamedSupabaseKey } from "./supabase_keys.ts";

export type MailKind =
  | "account_welcome"
  | "newsletter_confirm"
  | "newsletter_welcome"
  | "refund_request"
  | "account_deletion_scheduled"
  | "account_restored"
  | "credit_decision"
  | "topup_refund_outcome"
  | "maintenance_resolved"
  | "machine_issue_outcome";
export interface MailJob {
  id: string;
  lease_id: string;
  kind: MailKind;
  email: string;
  consent_id: string | null;
  lifecycle_requested_at?: string | null;
  lifecycle_restore_until?: string | null;
  lifecycle_restored_at?: string | null;
  lifecycle_consent?: {
    policy_version: string;
    acknowledgement: string;
    purchased_balance_cents: number;
    promotional_balance_cents: number;
  } | null;
  credit_notice?: {
    refund_id: string;
    transaction_id: string;
    status: "approved" | "denied";
    amount_cents: number;
    note: string;
  };
  followup_notice?: {
    refund_id: string;
    load_id: string;
    status: "succeeded" | "denied" | "failed" | "canceled";
    amount_cents: number;
    provider_refund_id: string | null;
  } | {
    report_id: string;
    status: "resolved";
  };
  machine_issue_notice?: {
    refund_id: string;
    transaction_id: string;
    resolution: "wallet_refund" | "replacement_vend";
    amount_cents: number;
    paid_amount_cents: number;
    promo_amount_cents: number;
    replacement_machine_id: string | null;
    replacement_machine_name: string | null;
  };
  refund_notice?: {
    refund_id: string;
    transaction_id: string;
    user_id: string;
    amount: string;
    description: string;
  };
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
    postal.length > 500 || tokenSecret.length < 43 ||
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

export function newsletterAvailable(config: MailConfig | null): boolean {
  return Boolean(config && config.postal.trim() && config.postal.length <= 500);
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

function lifecycleTime(value: unknown) {
  const match = typeof value === "string"
    ? /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/
      .exec(value)
    : null;
  const time = match ? Date.parse(value as string) : NaN;
  if (
    !match || !Number.isFinite(time) ||
    new Date(`${match[1]}Z`).toISOString().slice(0, 19) !== match[1]
  ) {
    throw new Error("Invalid lifecycle notice timestamp");
  }
  // Preserve server microseconds rather than rounding the restore boundary.
  return {
    micros: BigInt(time) * 1000n +
      BigInt((match[2] || ".0").slice(1).padEnd(6, "0").slice(3)),
    label: `${new Date(time).toISOString().slice(0, 19).replace("T", " ")}${
      match[2] || ""
    } UTC`,
  };
}

export async function renderMail(job: MailJob, config: MailConfig) {
  let subject = "Welcome to Clean Stream";
  let text =
    "Your email address is verified. Welcome to Clean Stream. This account notice does not subscribe you to our newsletter.";
  const paragraph = (value: string) =>
    `<p style="margin:0 0 20px;">${escapeHtml(value)}</p>`;
  const linkHtml = (url: string, label: string) =>
    `<a href="${
      escapeHtml(url)
    }" style="color:#2073A9;text-decoration:underline;">${
      escapeHtml(label)
    }</a>`;
  let content = paragraph(text), footer = "";
  const headers: Record<string, string> = {};
  let confirmHash: string | null = null, unsubscribeHash: string | null = null;
  if (job.kind === "account_deletion_scheduled" || job.kind === "account_restored") {
    const requested = lifecycleTime(job.lifecycle_requested_at);
    const deadline = lifecycleTime(job.lifecycle_restore_until);
    if (
      job.consent_id !== null ||
      ![720n, 2160n].some((hours) =>
        deadline.micros - requested.micros === hours * 60n * 60n * 1000000n)
    ) {
      throw new Error("Invalid lifecycle notice");
    }
    const information = new URL("/account-deletion", config.pageUrl).href;
    let lines: string[];
    if (job.kind === "account_deletion_scheduled") {
      if (job.lifecycle_restored_at !== null) {
        throw new Error("Invalid lifecycle notice");
      }
      subject = "Your Clean Stream account deletion is scheduled";
      lines = [
        "Your account deletion request was saved. This is not a confirmation of permanent deletion.",
        `Restore your account before ${deadline.label}.`,
        "To restore, open the Clean Stream app, sign in again and verify your identity, then choose Restore account before the deadline. Signing in alone does not restore your account.",
        "Your newsletter subscription is stopped. Restoring your account does not resubscribe you.",
      ];
      if (job.lifecycle_consent != null) {
        const consent = job.lifecycle_consent;
        if (typeof consent.policy_version !== "string" ||
          !consent.policy_version.trim() || consent.policy_version.length > 100 ||
          typeof consent.acknowledgement !== "string" ||
          !consent.acknowledgement.trim() || consent.acknowledgement.length > 4000 ||
          ![consent.purchased_balance_cents, consent.promotional_balance_cents]
            .every((cents) => Number.isSafeInteger(cents) && cents >= 0)) {
          throw new Error("Invalid lifecycle consent notice");
        }
        lines.push(
          `At your request: $${(consent.purchased_balance_cents / 100).toFixed(2)} purchased credit and $${(consent.promotional_balance_cents / 100).toFixed(2)} promotional credit.`,
          `Your acknowledgement (terms ${consent.policy_version}):`,
          consent.acknowledgement,
          "This acknowledgement is not a confirmation that credit has been forfeited or that a refund has been issued.",
        );
      }
    } else {
      const restored = lifecycleTime(job.lifecycle_restored_at);
      if (
        restored.micros <= requested.micros || restored.micros >= deadline.micros
      ) throw new Error("Invalid lifecycle notice");
      subject = "Your Clean Stream account has been restored";
      lines = [
        `Your explicit account restoration completed at ${restored.label}.`,
        "The deletion request for this recovery period is no longer pending. This notice does not confirm permanent deletion or data cleanup.",
        "Open the Clean Stream app to continue. Any required identity verification and account terms still apply.",
        "Your newsletter subscription remains stopped. Restoration does not resubscribe you or create a new account.",
      ];
    }
    const label = "Account deletion and restoration information";
    text = lines.join("\n\n") + `\n\n${label}: ${information}`;
    content = lines.map(paragraph).join("") +
      `<p style="margin:0 0 20px;">${linkHtml(information, label)}</p>`;
  } else if (job.kind === "credit_decision") {
    const notice = job.credit_notice;
    if (
      !notice || job.consent_id !== null ||
      ![notice.refund_id, notice.transaction_id].every((id) =>
        typeof id === "string" && /^[1-9][0-9]{0,18}$/.test(id)
      ) || !["approved", "denied"].includes(notice.status) ||
      !Number.isSafeInteger(notice.amount_cents) || notice.amount_cents <= 0 ||
      notice.amount_cents > 2147483647 ||
      typeof notice.note !== "string" || notice.note.length > 4000
    ) throw new Error("Invalid credit decision notice");
    const amount = (notice.amount_cents / 100).toFixed(2);
    const approved = notice.status === "approved";
    subject = approved
      ? "Your loyalty balance credit was approved"
      : "Your loyalty balance credit request was denied";
    const lines = [
      `Claim #${notice.refund_id} for transaction #${notice.transaction_id}.`,
      approved
        ? `$${amount} in promotional credit was added to your Clean Stream loyalty balance. No money was returned to your original payment method. This is not a cash refund.`
        : `Your request for a $${amount} Clean Stream loyalty balance credit was not approved. This decision did not add a credit or return money to your payment method.`,
      "Open the Clean Stream app to review your account. This transactional notice does not subscribe you to the newsletter.",
    ];
    text = lines.join("\n\n");
    content = lines.map(paragraph).join("");
  } else if (job.kind === "machine_issue_outcome") {
    const notice = job.machine_issue_notice;
    const validId = (value: unknown) => typeof value === "string" && /^[1-9][0-9]{0,18}$/.test(value);
    if (
      !notice || job.consent_id !== null ||
      !validId(notice.refund_id) || !validId(notice.transaction_id) ||
      !["wallet_refund", "replacement_vend"].includes(notice.resolution) ||
      ![notice.amount_cents, notice.paid_amount_cents, notice.promo_amount_cents].every(
        (amount) => Number.isSafeInteger(amount) && amount >= 0 && amount <= 2147483647,
      ) || notice.amount_cents <= 0 ||
      notice.amount_cents !== notice.paid_amount_cents + notice.promo_amount_cents ||
      (notice.resolution === "replacement_vend"
        ? !validId(notice.replacement_machine_id) ||
          typeof notice.replacement_machine_name !== "string" ||
          !notice.replacement_machine_name.trim() || notice.replacement_machine_name.length > 200
        : notice.replacement_machine_id !== null || notice.replacement_machine_name !== null)
    ) throw new Error("Invalid machine issue outcome");
    const wallet = notice.resolution === "wallet_refund";
    subject = wallet
      ? "Your Clean Stream loyalty balance has been restored"
      : "Your Clean Stream replacement cycle has started";
    const lines = [
      `Claim #${notice.refund_id} for transaction #${notice.transaction_id}.`,
      wallet
        ? `$${(notice.amount_cents / 100).toFixed(2)} was returned to your Clean Stream loyalty balance: $${(notice.paid_amount_cents / 100).toFixed(2)} in purchased funds and $${(notice.promo_amount_cents / 100).toFixed(2)} in promotional credit. The original paid and promotional portions were restored; this is not a refund to a card or other payment method.`
        : `Your replacement cycle on ${notice.replacement_machine_name} (machine #${notice.replacement_machine_id}) was confirmed as started. It uses your original $${(notice.amount_cents / 100).toFixed(2)} payment value without another loyalty balance deduction. This confirms the start, not completion of the cycle, and does not issue a cash refund.`,
      "Open the Clean Stream app to review your account. If the issue continues, contact support with your claim reference.",
    ];
    text = lines.join("\n\n");
    content = lines.map(paragraph).join("");
  } else if (job.kind === "topup_refund_outcome") {
    const notice = job.followup_notice;
    if (
      !notice || !("refund_id" in notice) || job.consent_id !== null ||
      typeof notice.refund_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(notice.refund_id) ||
      typeof notice.load_id !== "string" || !/^[1-9][0-9]{0,18}$/.test(notice.load_id) ||
      !["succeeded", "denied", "failed", "canceled"].includes(notice.status) ||
      !Number.isSafeInteger(notice.amount_cents) || notice.amount_cents <= 0 ||
      notice.amount_cents > 2147483647 ||
      (notice.status === "denied"
        ? notice.provider_refund_id !== null
        : typeof notice.provider_refund_id !== "string" ||
          !/^re_[a-zA-Z0-9]{1,200}$/.test(notice.provider_refund_id))
    ) throw new Error("Invalid top-up refund outcome");
    const amount = (notice.amount_cents / 100).toFixed(2);
    const succeeded = notice.status === "succeeded";
    subject = succeeded
      ? "Your Clean Stream top-up refund was confirmed"
      : "Update on your Clean Stream top-up refund request";
    const lines = [
      `Refund request ${notice.refund_id} for top-up #${notice.load_id}.`,
      succeeded
        ? `Stripe has confirmed a $${amount} refund to your original payment method. Your bank or payment provider controls when it appears on your account; this notice does not confirm that it is visible yet.`
        : notice.status === "denied"
        ? `Your request to refund the $${amount} top-up was not approved. No refund was issued for this request. The reserved paid amount has been returned to your Clean Stream loyalty balance.`
        : `The $${amount} top-up refund ${notice.status === "failed" ? "failed" : "was canceled"}. A successful refund has not been confirmed. The reserved paid amount has been returned to your Clean Stream loyalty balance. Contact support if you still need a refund; this request has not confirmed money returned to your payment method.`,
      "Open the Clean Stream app to review your account. Contact support with the request reference if you need help.",
    ];
    text = lines.join("\n\n");
    content = lines.map(paragraph).join("");
  } else if (job.kind === "maintenance_resolved") {
    const notice = job.followup_notice;
    if (
      !notice || !("report_id" in notice) || job.consent_id !== null ||
      typeof notice.report_id !== "string" || !notice.report_id.trim() ||
      notice.report_id.length > 200 || notice.status !== "resolved"
    ) throw new Error("Invalid issue resolution notice");
    subject = "Your Clean Stream issue report has been resolved";
    const lines = [
      `Issue report #${notice.report_id}.`,
      "Clean Stream staff marked your reported issue as resolved. Thank you for letting us know about the problem.",
      "This issue-status update does not confirm a refund, loyalty credit or replacement machine cycle. Any payment outcome is reported separately.",
      "If the issue continues, contact support with your report reference so we can help.",
    ];
    text = lines.join("\n\n");
    content = lines.map(paragraph).join("");
  } else if (job.kind === "refund_request") {
    const notice = job.refund_notice;
    if (
      !notice ||
      ![notice.refund_id, notice.transaction_id].every((id) =>
        typeof id === "string" && /^[1-9][0-9]{0,18}$/.test(id)
      ) ||
      typeof notice.user_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        notice.user_id,
      ) ||
      typeof notice.amount !== "string" ||
      !/^[0-9]+(?:\.[0-9]{1,2})?$/.test(notice.amount) ||
      notice.amount.length > 30 || Number(notice.amount) <= 0 ||
      typeof notice.description !== "string" || notice.description.length > 8000
    ) throw new Error("Invalid refund notice");
    const portal = "https://cleanstreamlaundry.com/admin";
    subject = "New loyalty balance credit request";
    const lines = [
      `Claim #${notice.refund_id} for transaction #${notice.transaction_id}.`,
      `Requested loyalty credit: $${notice.amount}.`,
      `Customer account: ${notice.user_id}`,
      `Reason: ${notice.description || "No reason provided."}`,
      "Review the saved claim in the authenticated staff portal. This alert does not approve a credit or return money.",
    ];
    text = lines.join("\n\n") + `\n\nStaff portal: ${portal}`;
    content = lines.map(paragraph).join("") +
      `<p style="margin:0 0 20px;">${
        linkHtml(portal, "Open staff portal")
      }</p>`;
  } else if (job.kind !== "account_welcome") {
    if (!newsletterAvailable(config)) {
      throw new MailError(503, "mail_disabled");
    }
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
      const introduction =
        "You requested the Clean Stream newsletter. Confirm your choice using this link within 24 hours of your request:";
      const explanation =
        "If you did not request this, ignore this message. You are not subscribed yet.";
      text = `${introduction}\n${link("confirm", confirm)}\n\n${explanation}`;
      content = paragraph(introduction) +
        `<p style="margin:0 0 20px;">${
          linkHtml(link("confirm", confirm), "Confirm newsletter subscription")
        }</p>` + paragraph(explanation);
      confirmHash = await sha256(confirm);
    } else {
      subject = "Welcome to the Clean Stream newsletter";
      text =
        "Your newsletter subscription is confirmed. Thank you for choosing to hear from Clean Stream.";
      content = paragraph(text);
    }
    text +=
      `\n\nUnsubscribe: ${unsubscribeUrl}\nClean Stream\n${config.postal}`;
    footer = `<p style="margin:0 0 16px;">${
      linkHtml(unsubscribeUrl, "Unsubscribe from the newsletter")
    }</p><p style="margin:0 0 16px;">Clean Stream<br>${
      escapeHtml(config.postal).replace(/\n/g, "<br>")
    }</p>`;
    headers["List-Unsubscribe"] = `<${oneClickUrl}>`;
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click";
  }
  text += `\n\nContact: ${config.replyTo}`;
  footer += `<p style="margin:0;">Contact: ${
    linkHtml(`mailto:${config.replyTo}`, config.replyTo)
  }</p>`;
  // Inline styles and presentational tables work without remote assets or fonts.
  // Brand colors reuse docs/theming.md; the plain-text alternative stays intact.
  const html =
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${
      escapeHtml(subject)
    }</title></head><body style="margin:0;padding:0;background-color:#FFFFFF;color:#212121;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.6;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;margin:0 auto;table-layout:fixed;overflow-wrap:anywhere;word-wrap:break-word;">
<tr><td style="padding:20px 24px;background-color:#2073A9;color:#FFFFFF;border-top:4px solid #F3C404;font-size:22px;font-weight:bold;">Clean Stream</td></tr>
<tr><td style="padding:28px 24px 8px;"><h1 style="margin:0 0 20px;font-size:24px;line-height:1.3;">${
      escapeHtml(subject)
    }</h1>${content}</td></tr>
<tr><td style="padding:20px 24px;border-top:1px solid #2073A9;font-size:14px;">${footer}</td></tr>
</table></body></html>`;
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
    const secretName = bearer
      ? undefined
      : env("CLEANSTREAM_MAIL_SECRET_KEY_NAME");
    const namedSecret = secretName !== undefined;
    const publishableName = bearer
      ? env("CLEANSTREAM_MAIL_PUBLISHABLE_KEY_NAME")
      : undefined;
    const key = bearer
      ? publishableName === undefined
        ? env("SUPABASE_ANON_KEY")
        : selectNamedSupabaseKey(
          publishableName,
          env("SUPABASE_PUBLISHABLE_KEYS"),
          "publishable",
        )
      : namedSecret
      ? selectNamedSupabaseKey(
        secretName,
        env("SUPABASE_SECRET_KEYS"),
        "secret",
      )
      : env("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key || env("CLEANSTREAM_MAIL_PROJECT_URL") !== url) {
      throw new MailError(503, "mail_unavailable");
    }
    const response = await transport(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: key,
        ...(bearer
          ? { Authorization: bearer }
          : namedSecret
          ? {}
          : { Authorization: `Bearer ${key}` }),
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
  const job = await rpc<MailJob | null>("mail_claim", {
    p_include_newsletter: newsletterAvailable(config),
  });
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
  try {
    // Preserve a leading BOM so webhook verification sees the exact wire bytes.
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(
      bytes,
    );
  } catch {
    throw new MailError(400, "invalid_body");
  }
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
