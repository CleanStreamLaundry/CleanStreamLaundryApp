import { handleRefundResolution } from "../_shared/refund_resolution.ts";
import { callerPublishableKey } from "../_shared/supabase_keys.ts";
import {
  capturedBearer,
  createCreditDependencies,
} from "../admin-portal/backend.ts";

export const handler = (request: Request) =>
  handleRefundResolution(
    request,
    "denied",
    createCreditDependencies(capturedBearer(request), {
      url: Deno.env.get("SUPABASE_URL")!,
      get anonKey() {
        return callerPublishableKey(
          (name) => Deno.env.get(name),
          "CLEANSTREAM_ADMIN_PUBLISHABLE_KEY_NAME",
        );
      },
    }),
  );

if (import.meta.main) Deno.serve(handler);
