import { handlePortal } from "./handler.ts";
import { callerPublishableKey, selectNamedSupabaseKey } from "../_shared/supabase_keys.ts";
import { createAdminClient, createStripeClient, startCortinaVend } from "../_shared/cortina.ts";

export const handler = (request: Request) =>
  handlePortal(request, {
    url: Deno.env.get("SUPABASE_URL")!,
    startReplacement: async (sessionId, authorize) => {
      await startCortinaVend(sessionId, { admin: createAdminClient("cortina-vend"), stripe: createStripeClient(), beforeSponsoredStart: authorize });
    },
    get geocodeKey() {
      return Deno.env.get("GEOCODEMAPS_KEY");
    },
    get onboarding() {
      const name = Deno.env.get("CLEANSTREAM_ADMIN_SECRET_KEY_NAME");
      const secretKey = name === undefined ? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
        : selectNamedSupabaseKey(name, Deno.env.get("SUPABASE_SECRET_KEYS"), "secret");
      if (!secretKey) return undefined;
      const origin = Deno.env.get("ADMIN_PORTAL_ORIGIN") || "https://cleanstreamlaundry.com";
      return { secretKey, modernSecret: name !== undefined, redirectTo: new URL("/admin/accept-invite", origin).href };
    },
    get anonKey() {
      return callerPublishableKey(
        (name) => Deno.env.get(name),
        "CLEANSTREAM_ADMIN_PUBLISHABLE_KEY_NAME",
      );
    },
  }, Deno.env.get("ADMIN_PORTAL_ORIGIN") || "https://cleanstreamlaundry.com");

if (import.meta.main) Deno.serve(handler);
