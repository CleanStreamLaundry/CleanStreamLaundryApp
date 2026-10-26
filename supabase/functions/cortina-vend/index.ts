import {
  CORS_HEADERS,
  createAdminClient,
  createStripeClient,
} from "../_shared/cortina.ts";
import { handleCortinaVend } from "./logic.ts";
import { cortinaPublicError, cortinaPublicResponse } from "./public_controls.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  try {
    const admin = createAdminClient("cortina-vend");
    const stripe = createStripeClient();
    return cortinaPublicResponse(await handleCortinaVend(req, { admin, stripe }));
  } catch (error) {
    const response = cortinaPublicError(error);
    console.error("cortina-vend request failed", response.status);
    return response;
  }
}

if (import.meta.main) Deno.serve(handler);
