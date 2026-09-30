import { serve } from "https://deno.land/std@0.182.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.14.0";
import { handleDeleteUser } from "./logic.ts";

const callerClient = (jwt: string) =>
  createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );

export const handler = (req: Request) =>
  handleDeleteUser(req, {
    async getUser(jwt) {
      const { data, error } = await callerClient(jwt).auth.getUser(jwt);
      return { userId: data.user?.id ?? null, error: !!error };
    },
    async requestDeletion(jwt) {
      return await callerClient(jwt).rpc("request_account_deletion");
    },
  });

if (import.meta.main) serve(handler);
