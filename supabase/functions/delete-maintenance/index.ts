// Temporary containment only. Authorized deletion requires a separately reviewed
// role, MFA, and location contract. No request payload or credentials are read.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

Deno.serve((req: Request): Response => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  return new Response(
    JSON.stringify({
      error: "Maintenance deletion is temporarily unavailable.",
    }),
    {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});
