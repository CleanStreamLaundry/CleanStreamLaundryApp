import type { CortinaVendReference } from "./interfaces/CortinaVendService";

type ReturnLocation = { pathname: string; search: string; hash: string; key?: string };
export type CortinaReturn = {
  sourceUrl: string;
  cleanUrl: string;
  hasReturnReference: boolean;
  reference: CortinaVendReference | null;
};

const relativeUrl = (location: ReturnLocation) => location.pathname + location.search + location.hash;
const hasCredentials = (params: URLSearchParams) => params.has("session") || params.has("access");
const validField = (value: string | null): value is string => Boolean(value && value.length <= 128 &&
  !Array.from(value).some((character) => character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127));

export function parseCortinaReturn(location: ReturnLocation): CortinaReturn {
  const sourceUrl = relativeUrl(location);
  const result: CortinaReturn = { sourceUrl, cleanUrl: sourceUrl, hasReturnReference: false, reference: null };
  if (location.pathname !== "/pay" && location.pathname !== "/pay/") return result;
  const url = new URL(sourceUrl, "https://cortina.invalid");
  if (sourceUrl.length > 8192) {
    return { ...result, cleanUrl: `${url.pathname}?cortina_return=1`, hasReturnReference: true };
  }
  const query = url.searchParams;
  const fragment = new URLSearchParams(url.hash.slice(1));
  const queryCredentials = hasCredentials(query), fragmentCredentials = hasCredentials(fragment);
  result.hasReturnReference = queryCredentials || fragmentCredentials || query.has("cortina_return");
  if (!result.hasReturnReference) return result;

  // Never merge partial references or choose one of two ambiguous capabilities.
  const credentials = queryCredentials && !fragmentCredentials ? query : fragmentCredentials && !queryCredentials ? fragment : null;
  if (credentials?.getAll("session").length === 1 && credentials.getAll("access").length === 1) {
    const sessionId = credentials.get("session"), accessToken = credentials.get("access");
    if (validField(sessionId) && validField(accessToken)) result.reference = { sessionId, accessToken };
  }
  query.delete("session");
  query.delete("access");
  query.set("cortina_return", "1");
  if (fragmentCredentials) {
    fragment.delete("session");
    fragment.delete("access");
    url.hash = fragment.toString();
  }
  result.cleanUrl = relativeUrl(url);
  return result;
}

export function scrubCortinaReturn(snapshot: CortinaReturn): boolean {
  if (!snapshot.hasReturnReference) return true;
  const current = relativeUrl(window.location);
  if (current === snapshot.cleanUrl) return true;
  if (current !== snapshot.sourceUrl) {
    // A late cleanup cannot erase a newer return. MemoryRouter has no browser URL.
    const newer = parseCortinaReturn(window.location);
    return newer.sourceUrl === newer.cleanUrl;
  }
  try {
    window.history.replaceState(window.history.state, "", snapshot.cleanUrl);
    return relativeUrl(window.location) === snapshot.cleanUrl;
  } catch {
    return false;
  }
}

// This module is the first main.tsx import, before any SDK/application evaluation.
let initialReturn: CortinaReturn | null = null;
let initialKey = "default";
if (typeof window !== "undefined") {
  const snapshot = parseCortinaReturn(window.location);
  if (snapshot.hasReturnReference) {
    if (!scrubCortinaReturn(snapshot)) throw new Error("Payment return address could not be cleared");
    initialReturn = snapshot;
    initialKey = typeof window.history.state?.key === "string" ? window.history.state.key : "default";
  }
}

export function initialCortinaReturn(location: ReturnLocation): CortinaReturn | null {
  return initialReturn && location.key === initialKey && relativeUrl(location) === initialReturn.cleanUrl ? initialReturn : null;
}

export function releaseInitialCortinaReturn(): void {
  initialReturn = null;
}
