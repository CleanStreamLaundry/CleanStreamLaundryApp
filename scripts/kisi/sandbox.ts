// Deliberately synthetic, in-memory provider simulator. Never forwards requests.
import { createServer } from "node:http";
import type { Server } from "node:http";
import { KISI_SANDBOX_KEY } from "../../supabase/functions/_shared/kisi.ts";

const scenarios = [
  [101, "Ready door", "ready"],
  [102, "Controller pending", "unassigned"],
  [103, "Offline door", "offline"],
  [104, "Locked-down door", "locked_down"],
  [105, "Access denied", "denied"],
  [106, "Rate limited", "rate_limited"],
  [107, "Provider failure", "provider_error"],
  [108, "Response lost after acceptance", "response_lost"],
] as const;

export function createKisiSandbox() {
  const accepted: number[] = [];
  const requests: Array<{ method: string; path: string }> = [];
  const handler = async (request: Request): Promise<Response> => {
    const url = new URL(request.url);
    const json = (body: unknown, status = 200, headers = {}) => Response.json(body, {
      status, headers: { "X-CleanStream-Simulation": "true", ...headers },
    });
    if (request.headers.get("authorization") !== `KISI-LOGIN ${KISI_SANDBOX_KEY}`) {
      return json({ error: "Invalid simulation credential." }, 401);
    }
    requests.push({ method: request.method, path: url.pathname });
    const page = (rows: unknown[]) => {
      const limit = Number(url.searchParams.get("limit") ?? 50);
      const offset = Number(url.searchParams.get("offset") ?? 0);
      if (!Number.isInteger(limit) || limit < 1 || limit > 250 ||
        !Number.isInteger(offset) || offset < 0 || offset > 20000) return json({ error: "Invalid page." }, 400);
      return json(rows.slice(offset, offset + limit), 200,
        { "X-Collection-Range": `${offset}-${offset + limit - 1}/${rows.length}` });
    };
    if (request.method === "GET" && url.pathname === "/places") {
      return page([{ id: 1, name: "Clean Stream LOCAL simulation" }]);
    }
    if (request.method === "GET" && url.pathname === "/locks") {
      const rows = url.searchParams.get("place_id") === "1" ? scenarios.map(([id, name, scenario]) => ({
        id, name, place_id: 1, configured: scenario !== "unassigned",
        online: !["unassigned", "offline"].includes(scenario),
        unlocked: accepted.includes(id), locked_down: scenario === "locked_down",
      })) : [];
      return page(rows);
    }
    const match = url.pathname.match(/^\/locks\/(\d+)\/unlock$/);
    if (request.method !== "POST" || !match) return json({ error: "Unknown simulation route." }, 404);
    const id = Number(match[1]);
    const scenario = scenarios.find(row => row[0] === id)?.[2];
    switch (scenario) {
      case "unassigned": return json({ error: "The door has no assigned Kisi controller.", code: "ff420a" }, 409);
      case "offline": return json({ error: "The Kisi controller is currently unavailable.", code: "fac001" }, 503);
      case "locked_down": return json({ error: "The door is currently locked down.", code: "fad001" }, 409);
      case "denied": return json({ error: "Access denied.", code: "afc496" }, 403);
      case "rate_limited": return json({ error: "Too many requests." }, 429, { "Retry-After": "2" });
      case "provider_error": return json({ error: "Simulated failure." }, 500);
      case "ready": accepted.push(id); return json({ message: "Unlocked!" });
      case "response_lost":
        accepted.push(id);
        throw new Error("Simulated connection lost after relay acceptance");
      default: return json({ error: "Unknown door." }, 404);
    }
  };
  return { handler, accepted, requests };
}

export async function startKisiSandbox(port = 8787): Promise<{ server: Server; port: number; close: () => Promise<void> }> {
  const sandbox = createKisiSandbox();
  const server = createServer(async (incoming, outgoing) => {
    // Fixed base, loopback binding, no CORS, and no outbound network client.
    const headers = new Headers();
    for (const [key, value] of Object.entries(incoming.headers)) {
      if (value) headers.set(key, Array.isArray(value) ? value.join(",") : value);
    }
    try {
      incoming.resume(); // This limited simulator has no body-driven behavior.
      const response = await sandbox.handler(new Request(`http://127.0.0.1${incoming.url}`, {
        method: incoming.method, headers,
      }));
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      outgoing.end(await response.text());
    } catch { incoming.socket.destroy(); }
  });
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", resolve);
  });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Simulation listener unavailable");
  return { server, port: address.port, close: () => new Promise<void>((resolve, reject) => {
    server.close(error => error ? reject(error) : resolve());
    server.closeAllConnections();
  }) };
}
