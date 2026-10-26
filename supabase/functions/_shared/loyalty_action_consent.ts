import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callerPublishableKey } from "./supabase_keys.ts";
import { FUNDING_PUBLIC_KEY_SELECTOR } from "./wallet_funding_admission.ts";

export type ConsentChannel = "payment_intent" | "checkout";
export interface WalletLoadConsentReceipt {
  context_id: string;
  subject_id: string;
  wallet_account_id: string;
  amount_cents: number;
  channel: ConsentChannel;
  accepted_at: string;
  policy_version: string;
  policy_sha256: string;
  provider_reference: string | null;
}
export type WalletLoadConsent = (
  consent: unknown, subject: string, amount: number, channel: ConsentChannel,
) => Promise<WalletLoadConsentReceipt>;

export class ActionConsentError extends Error {
  constructor(message = "consent_required", public readonly status = 409) {
    super(message);
  }
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function consentContextId(consent: unknown): string {
  if (!consent || typeof consent !== "object" || Array.isArray(consent)) {
    throw new ActionConsentError();
  }
  const value = consent as Record<string, unknown>;
  if (value.acknowledged !== true || typeof value.context_id !== "string" || !uuid.test(value.context_id)) {
    throw new ActionConsentError();
  }
  return value.context_id;
}

export function captureWalletLoadConsent(
  request: Request,
  env: (name: string) => string | undefined,
  transport: typeof fetch = fetch,
): WalletLoadConsent {
  const authorization = request.headers.get("Authorization");
  return async (consent, subject, amount, channel) => {
    const contextId = consentContextId(consent);
    if (!authorization || !/^Bearer \S+$/i.test(authorization)) {
      throw new ActionConsentError("session_invalid", 401);
    }
    const url = env("SUPABASE_URL");
    if (!url) throw new ActionConsentError("consent_unavailable", 503);
    try {
      const response = await transport(`${url.replace(/\/$/, "")}/rest/v1/rpc/accept_wallet_load_consent`, {
        method: "POST",
        headers: {
          apikey: callerPublishableKey(env, FUNDING_PUBLIC_KEY_SELECTOR),
          Authorization: authorization,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ p_context_id: contextId, p_acknowledged: true,
          p_amount_cents: amount, p_channel: channel }),
        redirect: "error",
        signal: AbortSignal.timeout(8000),
      });
      const data = await response.json();
      if (!response.ok) {
        const allowed = new Set(["consent_required", "consent_context_invalid", "consent_context_stale",
          "consent_replay_mismatch", "payment_reconciliation_required", "account_restricted",
          "session_invalid", "new_payments_unavailable"]);
        throw new ActionConsentError(allowed.has(data?.message) ? data.message : "consent_unavailable",
          [401, 403, 409].includes(response.status) ? response.status : 503);
      }
      if (!data || data.context_id !== contextId || data.subject_id !== subject ||
        data.amount_cents !== amount || data.channel !== channel ||
        typeof data.wallet_account_id !== "string" || !uuid.test(data.wallet_account_id) ||
        typeof data.accepted_at !== "string" || !Number.isFinite(Date.parse(data.accepted_at)) ||
        typeof data.policy_version !== "string" || !data.policy_version ||
        typeof data.policy_sha256 !== "string" || !/^[a-f0-9]{64}$/.test(data.policy_sha256) ||
        !(data.provider_reference === null || (typeof data.provider_reference === "string" &&
          (channel === "payment_intent" ? /^pi_[A-Za-z0-9_]+$/ : /^cs_[A-Za-z0-9_]+$/).test(data.provider_reference)))) {
        throw new ActionConsentError("consent_unavailable", 503);
      }
      return data as WalletLoadConsentReceipt;
    } catch (error) {
      if (error instanceof ActionConsentError) throw error;
      throw new ActionConsentError("consent_unavailable", 503);
    }
  };
}

export async function requireWalletLoadConsent(
  accept: WalletLoadConsent | undefined, consent: unknown, subject: string,
  amount: number, channel: ConsentChannel,
): Promise<WalletLoadConsentReceipt> {
  consentContextId(consent);
  if (!accept) throw new ActionConsentError("consent_unavailable", 503);
  return await accept(consent, subject, amount, channel);
}

export function consentMetadata(receipt: WalletLoadConsentReceipt): Record<string, string> {
  return { consent_context_id: receipt.context_id, consent_policy_version: receipt.policy_version,
    consent_policy_sha256: receipt.policy_sha256 };
}

export function assertConsentProviderBinding(
  receipt: WalletLoadConsentReceipt, amount: number | null, currency: string | null,
  metadata: Record<string, string> | null,
) {
  if (amount !== receipt.amount_cents || currency !== "usd" ||
    metadata?.user_id !== receipt.subject_id || metadata?.purpose !== "wallet_load" ||
    metadata?.wallet_account_id !== receipt.wallet_account_id ||
    metadata?.amount_cents !== String(amount) ||
    metadata?.consent_context_id !== receipt.context_id ||
    metadata?.consent_policy_version !== receipt.policy_version ||
    metadata?.consent_policy_sha256 !== receipt.policy_sha256) {
    throw new ActionConsentError("consent_provider_mismatch");
  }
}

export async function bindConsentProvider(
  admin: SupabaseClient, receipt: WalletLoadConsentReceipt, reference: string,
) {
  const { error } = await admin.rpc("bind_wallet_load_consent_provider", {
    p_context_id: receipt.context_id, p_subject_id: receipt.subject_id,
    p_amount_cents: receipt.amount_cents, p_channel: receipt.channel, p_provider_reference: reference,
  });
  if (error) throw new ActionConsentError("consent_receipt_pending", 503);
}
