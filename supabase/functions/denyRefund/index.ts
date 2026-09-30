import { handleRefundResolution } from "../_shared/refund_resolution.ts";
import {
  capturedBearer,
  createCreditDependencies,
} from "../admin-portal/backend.ts";

Deno.serve((request) =>
  handleRefundResolution(
    request,
    "denied",
    createCreditDependencies(capturedBearer(request), {
      url: Deno.env.get("SUPABASE_URL")!,
      anonKey: Deno.env.get("SUPABASE_ANON_KEY")!,
    }),
  )
);
