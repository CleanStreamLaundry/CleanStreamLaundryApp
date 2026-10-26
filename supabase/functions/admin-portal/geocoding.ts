import { PortalError } from "./logic.ts";

export function parseGeocodeAddress(value: unknown): string {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new PortalError("Enter a complete address.");
  }
  const address = value as Record<string, unknown>;
  const fields = { address: 200, city: 100, state: 100, zipCode: 20, country: 100 };
  const parts = Object.entries(fields).map(([name, max]) => {
    const part = address[name];
    // Explicitly reject control characters in user-supplied address fields.
    // deno-lint-ignore no-control-regex
    if (typeof part !== "string" || !part.trim() || part.length > max || /[\u0000-\u001f\u007f]/.test(part)) {
      throw new PortalError("Enter a complete address within the allowed length.");
    }
    return part.trim();
  });
  return parts.join(" ");
}

const unavailable = () => new PortalError("Address lookup is unavailable. Try again later.", 503, "geocode_unavailable");

export async function geocodeAddress(
  query: string,
  key: string | undefined,
  request: typeof fetch = fetch,
): Promise<{ lat: number; lon: number } | null> {
  if (!key?.trim()) throw unavailable();
  const url = new URL("https://geocode.maps.co/search");
  url.search = new URLSearchParams({
    q: query, limit: "1", format: "json", addressdetails: "0", extratags: "0", namedetails: "0",
  }).toString();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  try {
    const response = await request(url, {
      headers: { Authorization: `Bearer ${key}` },
      signal: controller.signal,
      redirect: "error",
    });
    if (response.status === 429) {
      throw new PortalError("Address lookup is busy. Try again later.", 429, "geocode_rate_limited");
    }
    if (!response.ok || !response.body) throw unavailable();
    reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 16384) throw unavailable();
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const results: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (!Array.isArray(results) || results.length > 1) throw unavailable();
    if (!results.length) return null;
    const first = results[0];
    const coordinate = (value: unknown, limit: number) => {
      if (typeof value !== "number" && (typeof value !== "string" || !/^-?\d+(\.\d+)?$/.test(value))) throw unavailable();
      const number = Number(value);
      if (!Number.isFinite(number) || Math.abs(number) > limit) throw unavailable();
      return number;
    };
    if (!first || typeof first !== "object") throw unavailable();
    return { lat: coordinate(first.lat, 90), lon: coordinate(first.lon, 180) };
  } catch (error) {
    // Never return or log provider bodies, addresses, request URLs or credentials.
    if (error instanceof PortalError) throw error;
    throw unavailable();
  } finally {
    controller.abort();
    clearTimeout(timeout);
    await reader?.cancel().catch(() => {});
  }
}
