import type Stripe from "npm:stripe";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type FundingAdmission, requireFundingAdmission } from "../_shared/wallet_funding_admission.ts";
import { requireNewPayments } from "../_shared/new_payment_control.ts";
import { ActionConsentError, assertConsentProviderBinding, bindConsentProvider, consentMetadata,
  requireWalletLoadConsent, type WalletLoadConsent, type WalletLoadConsentReceipt } from "../_shared/loyalty_action_consent.ts";

export interface PaymentIntentDeps {
  stripe: Stripe;
  supabaseAdmin?: SupabaseClient;
  fundingAdmission?: FundingAdmission;
  walletLoadConsent?: WalletLoadConsent;
}

export interface PaymentIntentResult {
  clientSecret: string | null;
  paymentIntentId: string;
}

export type PaymentPurpose = "walletLoad" | "directMachinePayment";

export function validateAmount(amount: unknown): number {
  if (amount === undefined || amount === null) {
    throw new Error("Missing amount");
  }
  if (typeof amount !== "number" || !Number.isInteger(amount) || amount <= 0) {
    throw new Error("Invalid amount: must be a positive integer (cents)");
  }
  return amount;
}

export async function createPaymentIntent(
  stripe: Stripe,
  amount: number,
  userId = "test-user",
  purpose: PaymentPurpose = "directMachinePayment",
  walletAccountId?: string,
  consent?: WalletLoadConsentReceipt,
): Promise<PaymentIntentResult> {
  if (purpose === "walletLoad" && !consent) throw new ActionConsentError();
  const metadata: Record<string, string> = {
    user_id: userId,
    purpose: purpose === "walletLoad"
      ? "wallet_load"
      : "direct_machine_payment",
    amount_cents: String(amount),
  };

  if (walletAccountId) {
    metadata.wallet_account_id = walletAccountId;
  }
  if (consent) Object.assign(metadata, consentMetadata(consent));

  const intent = consent?.provider_reference
    ? await stripe.paymentIntents.retrieve(consent.provider_reference)
    : await stripe.paymentIntents.create({
    amount,
    currency: "usd",
    payment_method_types: ["card"],
    metadata,
  }, consent ? { idempotencyKey: `loyalty-load:${consent.context_id}` } : undefined);
  if (consent) {
    if (consent.provider_reference && intent.id !== consent.provider_reference) {
      throw new ActionConsentError("consent_provider_mismatch");
    }
    assertConsentProviderBinding(consent, intent.amount, intent.currency, intent.metadata);
  }

  return { clientSecret: intent.client_secret, paymentIntentId: intent.id };
}

export async function getAuthenticatedUserId(
  req: Request,
  supabaseAdmin: SupabaseClient
): Promise<string> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    throw new Error("Unauthorized");
  }

  const token = authorization.replace("Bearer ", "");
  if (!token || token === authorization) {
    throw new Error("Unauthorized");
  }

  const {
    data: { user },
    error,
  } = await supabaseAdmin.auth.getUser(token);

  if (error || !user) {
    throw new Error("Unauthorized");
  }

  return user.id;
}

export async function getOrCreateWalletAccount(
  supabaseAdmin: SupabaseClient,
  userId: string
): Promise<string> {
  const { data, error } = await supabaseAdmin.rpc("get_or_create_wallet_account", {
    target_user_id: userId,
  });

  if (error || !data) {
    throw new Error(error?.message ?? "Unable to create wallet account");
  }

  return data as string;
}

export async function handleCreatePaymentIntent(
  req: Request,
  deps: PaymentIntentDeps
): Promise<Response> {
  const body = await req.json();
  const amount = validateAmount(body?.amount);
  const purpose = body?.purpose === "walletLoad"
    ? "walletLoad"
    : "directMachinePayment";
  if (purpose === "walletLoad" && !deps.supabaseAdmin) {
    throw new Error("Supabase admin client required");
  }
  if (purpose === "walletLoad" && (!Number.isSafeInteger(amount) || amount > 2147483647)) {
    throw new Error("Invalid amount");
  }

  const userId = deps.supabaseAdmin
    ? await getAuthenticatedUserId(req, deps.supabaseAdmin)
    : "test-user";
  if (purpose === "walletLoad") {
    await requireFundingAdmission(deps.fundingAdmission, userId);
    await requireNewPayments(deps.supabaseAdmin);
  }
  const walletAccountId = purpose === "walletLoad" && deps.supabaseAdmin
    ? await getOrCreateWalletAccount(deps.supabaseAdmin, userId)
    : undefined;
  if (purpose === "walletLoad") {
    await requireFundingAdmission(deps.fundingAdmission, userId);
  }
  const consent = purpose === "walletLoad"
    ? await requireWalletLoadConsent(deps.walletLoadConsent, body?.consent, userId, amount, "payment_intent")
    : undefined;
  if (consent && consent.wallet_account_id !== walletAccountId) {
    throw new ActionConsentError("consent_context_invalid");
  }
  if (consent) await requireFundingAdmission(deps.fundingAdmission, userId);
  await requireNewPayments(deps.supabaseAdmin);
  const result = await createPaymentIntent(
    deps.stripe,
    amount,
    userId,
    purpose,
    walletAccountId,
    consent,
  );
  if (consent) {
    await bindConsentProvider(deps.supabaseAdmin!, consent, result.paymentIntentId);
    await requireFundingAdmission(deps.fundingAdmission, userId);
  }

  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}
