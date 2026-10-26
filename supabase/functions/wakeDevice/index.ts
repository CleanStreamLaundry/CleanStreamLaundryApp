// Retired legacy endpoint. No payload, credentials, database or provider access.
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
      success: false,
      error: "upgrade_required",
      message:
        "This legacy endpoint is retired. Update Clean Stream to continue.",
    }),
    {
      status: 410,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});

export {};
