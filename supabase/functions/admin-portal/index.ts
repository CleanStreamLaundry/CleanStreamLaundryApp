import { handlePortal } from "./handler.ts";

Deno.serve((request) =>
  handlePortal(request, {
    url: Deno.env.get("SUPABASE_URL")!,
    anonKey: Deno.env.get("SUPABASE_ANON_KEY")!,
  }, Deno.env.get("ADMIN_PORTAL_ORIGIN") || "https://cleanstreamlaundry.com")
);
