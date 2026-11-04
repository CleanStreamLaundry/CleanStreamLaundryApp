import {
  CORS_HEADERS,
  createAdminClient,
  createStripeClient,
  errorResponse,
} from "../_shared/cortina.ts";
import { handleCortinaVend } from "./logic.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  try {
    const admin = createAdminClient("cortina-vend");
    const stripe = createStripeClient();
    return await handleCortinaVend(req, { admin, stripe });
  } catch (error) {
    console.error("cortina-vend", error);
    return errorResponse(error);
  }
}

if (import.meta.main) Deno.serve(handler);
