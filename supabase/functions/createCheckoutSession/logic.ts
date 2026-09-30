import Stripe from "npm:stripe@^14.0.0";
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface CheckoutDeps {
  stripe: Stripe;
  supabase: SupabaseClient;
  supabaseAdmin?: SupabaseClient;
}

export interface CheckoutResult {
  url: string | null;
  session_id: string;
}

export type PaymentPurpose = "walletLoad" | "directMachinePayment";

export async function getAuthenticatedUser(supabase: SupabaseClient) {
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    throw new Error("Unauthorized");
  }

  return user;
}

export async function createCheckoutSession(
  stripe: Stripe,
  amount: number,
  userId: string,
  purposeOrBaseUrl: PaymentPurpose | string = "directMachinePayment",
  walletAccountId?: string,
  baseUrl = "http://localhost:8080"
): Promise<CheckoutResult> {
  if (!amount || typeof amount !== "number" || amount <= 0) {
    throw new Error("Invalid amount");
  }

  const purpose: PaymentPurpose =
    purposeOrBaseUrl === "walletLoad" ? "walletLoad" : "directMachinePayment";
  if (purposeOrBaseUrl !== "walletLoad" &&
      purposeOrBaseUrl !== "directMachinePayment") {
    baseUrl = purposeOrBaseUrl;
  }

  const metadata: Record<string, string> = {
    user_id: userId,
    purpose: purpose === "walletLoad" ? "wallet_load" : "direct_machine_payment",
    amount_cents: String(amount),
  };

  if (walletAccountId) {
    metadata.wallet_account_id = walletAccountId;
  }

  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    payment_method_types: ["card"],
    line_items: [
      {
        price_data: {
          currency: "usd",
          product_data: {
            name: purpose === "walletLoad"
              ? "Clean Stream Loyalty Card"
              : "Clean Stream Laundry Service",
          },
          unit_amount: amount,
        },
        quantity: 1,
      },
    ],
    metadata,
    payment_intent_data: { metadata },
    success_url: `${baseUrl}/homePage`,
    cancel_url: `${baseUrl}/homePage`,
  });

  return { url: session.url, session_id: session.id };
}


export async function handleCheckout(
  req: Request,
  deps: CheckoutDeps,
  baseUrl?: string
): Promise<Response> {
  const { amount, purpose: rawPurpose } = await req.json();
  const purpose = rawPurpose === "walletLoad"
    ? "walletLoad"
    : "directMachinePayment";

  const user = await getAuthenticatedUser(deps.supabase);
  let walletAccountId: string | undefined;

  if (purpose === "walletLoad") {
    if (!deps.supabaseAdmin) {
      throw new Error("Supabase admin client required");
    }

    const { data, error } = await deps.supabaseAdmin.rpc(
      "get_or_create_wallet_account",
      { target_user_id: user.id },
    );

    if (error || !data) {
      throw new Error(error?.message ?? "Unable to create wallet account");
    }

    walletAccountId = data as string;
  }

  const result = await createCheckoutSession(
    deps.stripe,
    amount,
    user.id,
    purpose,
    walletAccountId,
    baseUrl
  );

  return new Response(JSON.stringify(result), {
    headers: { "Content-Type": "application/json" },
  });
}
