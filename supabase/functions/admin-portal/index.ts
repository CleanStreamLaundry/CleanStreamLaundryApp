import { handlePortal } from "./handler.ts";
import { callerPublishableKey } from "../_shared/supabase_keys.ts";

export const handler = (request: Request) =>
  handlePortal(request, {
    url: Deno.env.get("SUPABASE_URL")!,
    get anonKey() {
      return callerPublishableKey(
        (name) => Deno.env.get(name),
        "CLEANSTREAM_ADMIN_PUBLISHABLE_KEY_NAME",
      );
    },
  }, Deno.env.get("ADMIN_PORTAL_ORIGIN") || "https://cleanstreamlaundry.com");

if (import.meta.main) Deno.serve(handler);
