import type Stripe from "npm:stripe";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type FundingAdmission, requireFundingAdmission } from "../_shared/wallet_funding_admission.ts";
import { requireNewPayments } from "../_shared/new_payment_control.ts";

export interface PaymentIntentDeps {
  stripe: Stripe;
  supabaseAdmin?: SupabaseClient;
  fundingAdmission?: FundingAdmission;
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
  walletAccountId?: string
): Promise<PaymentIntentResult> {
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

  const intent = await stripe.paymentIntents.create({
    amount,
    currency: "usd",
    payment_method_types: ["card"],
    metadata,
  });

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
  await requireNewPayments(deps.supabaseAdmin);
  const result = await createPaymentIntent(
    deps.stripe,
    amount,
    userId,
    purpose,
    walletAccountId
  );

  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}
