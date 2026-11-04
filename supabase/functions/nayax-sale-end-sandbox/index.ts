import {
  createAdminClient,
  createStripeClient,
  HttpError,
} from "../_shared/cortina.ts";
import { handleNayaxCallback } from "../_shared/cortina_callback.ts";

export async function handler(req: Request): Promise<Response> {
  try {
    const deps = { admin: createAdminClient("nayax-sandbox"), stripe: createStripeClient() };
    return await handleNayaxCallback(req, "sandbox", deps);
  } catch (error) {
    console.error("nayax-sale-end-sandbox", error);
    return Response.json({
      Status: { Verdict: "Declined", Code: 999, StatusMessage: "Internal error" },
    }, { status: error instanceof HttpError && error.code === "key_configuration_unavailable" ? 503 : 200 });
  }
}

if (import.meta.main) Deno.serve(handler);
