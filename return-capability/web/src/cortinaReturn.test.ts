import mainSource from "./main.tsx?raw";
import htmlSource from "../index.html?raw";
import { afterEach, describe, expect, it, vi } from "vitest";
import { parseCortinaReturn, releaseInitialCortinaReturn, scrubCortinaReturn } from "./cortinaReturn";

const reference = { sessionId: "00000000-0000-4000-8000-000000000001", accessToken: "ABCDEF00-0000-4000-8000-000000000002" };
const fragment = new URLSearchParams({ session: reference.sessionId, access: reference.accessToken }).toString();
const location = (url: string) => new URL(url, window.location.origin);

afterEach(() => {
  vi.restoreAllMocks();
  releaseInitialCortinaReturn();
  window.history.replaceState(null, "", "/");
});

describe("Cortina return capture", () => {
  it("captures a new fragment exactly and leaves only the nonsecret return marker", () => {
    const result = parseCortinaReturn(location(`/pay?cortina_return=1#${fragment}`));
    expect(result.reference).toEqual(reference);
    expect(result.cleanUrl).toBe("/pay?cortina_return=1");
    expect(result.hasReturnReference).toBe(true);
  });

  it("accepts old query links and removes every authority field without changing public selectors", () => {
    const result = parseCortinaReturn(location(`/pay?machine=public-qr&${fragment}&campaign=summer#section`));
    expect(result.reference).toEqual(reference);
    expect(result.cleanUrl).toBe("/pay?machine=public-qr&campaign=summer&cortina_return=1#section");
  });

  it("does not decode trim or case-fold a capability twice", () => {
    const accessToken = " Upper+%2F & token ";
    const result = parseCortinaReturn(location(`/pay#${new URLSearchParams({ session: reference.sessionId, access: accessToken })}`));
    expect(result.reference).toEqual({ ...reference, accessToken });
  });

  it("never merges partial query and fragment credentials", () => {
    const result = parseCortinaReturn(location(`/pay?session=${reference.sessionId}#access=${reference.accessToken}`));
    expect(result.reference).toBeNull();
    expect(result.hasReturnReference).toBe(true);
    expect(result.cleanUrl).toBe("/pay?cortina_return=1");
  });

  it("rejects duplicate and conflicting pairs but scrubs every copy", () => {
    for (const url of [`/pay?${fragment}&access=other`, `/pay#${fragment}&session=other`, `/pay?${fragment}#${fragment}`]) {
      const result = parseCortinaReturn(location(url));
      expect(result.reference).toBeNull();
      expect(result.cleanUrl).toBe("/pay?cortina_return=1");
    }
  });

  it("empty partial oversized and control-bearing returns remain support-only", () => {
    for (const fields of ["session=", "access=", "session=one", "access=two", "session=one&access=",
      `session=one&access=${"x".repeat(129)}`, "session=one&access=a%0Ab"]) {
      const result = parseCortinaReturn(location(`/pay?machine=public#${fields}`));
      expect(result.reference).toBeNull();
      expect(result.hasReturnReference).toBe(true);
      expect(result.cleanUrl).toBe("/pay?machine=public&cortina_return=1");
    }
  });

  it("a scrubbed reload or stripped new fragment cannot become a fresh checkout", () => {
    const result = parseCortinaReturn(location("/pay?machine=public&cortina_return=1"));
    expect(result.hasReturnReference).toBe(true);
    expect(result.reference).toBeNull();
    expect(result.cleanUrl).toBe(result.sourceUrl);
  });

  it("leaves plain public machine and nonpayment auth routes untouched", () => {
    for (const path of ["/pay?machine=public#section", "/pay?uniqr=qr", "/admin?session=auth&access=token#access_token=auth"]) {
      const result = parseCortinaReturn(location(path));
      expect(result.hasReturnReference).toBe(false);
      expect(result.cleanUrl).toBe(path);
    }
  });

  it("drops an oversized return URL without retaining capability or inviting checkout", () => {
    const result = parseCortinaReturn(location(`/pay?access=${"x".repeat(8192)}`));
    expect(result.reference).toBeNull();
    expect(result.hasReturnReference).toBe(true);
    expect(result.cleanUrl).toBe("/pay?cortina_return=1");
  });

  it("replaces rather than pushes history and does not persist the authority", () => {
    window.history.replaceState({ key: "existing", idx: 4 }, "", `/pay?${fragment}`);
    const snapshot = parseCortinaReturn(window.location);
    const replace = vi.spyOn(window.history, "replaceState");
    const push = vi.spyOn(window.history, "pushState");
    const storage = vi.spyOn(Storage.prototype, "setItem");
    expect(scrubCortinaReturn(snapshot)).toBe(true);
    expect(replace).toHaveBeenCalledExactlyOnceWith({ key: "existing", idx: 4 }, "", "/pay?cortina_return=1");
    expect(push).not.toHaveBeenCalled();
    expect(storage).not.toHaveBeenCalled();
    expect(JSON.stringify(window.history.state)).not.toContain(reference.accessToken);
    expect(window.location.href).not.toContain(reference.accessToken);
    expect(scrubCortinaReturn(snapshot)).toBe(true);
    expect(replace).toHaveBeenCalledTimes(1);
  });

  it("late cleanup refuses to overwrite a different return", () => {
    const old = parseCortinaReturn(location(`/pay?${fragment}`));
    window.history.replaceState(null, "", "/pay#session=new&access=new-secret");
    const replace = vi.spyOn(window.history, "replaceState");
    expect(scrubCortinaReturn(old)).toBe(false);
    expect(replace).not.toHaveBeenCalled();
    expect(window.location.hash).toBe("#session=new&access=new-secret");
  });

  it("history failure is not treated as a scrubbed return", () => {
    window.history.replaceState(null, "", `/pay?${fragment}`);
    const snapshot = parseCortinaReturn(window.location);
    vi.spyOn(window.history, "replaceState").mockImplementation(() => { throw new Error(reference.accessToken); });
    expect(scrubCortinaReturn(snapshot)).toBe(false);
  });

  it("bootstrap captures before the app, stays memory-only and is bound to its entry", async () => {
    window.history.replaceState({ key: "entry", idx: 1 }, "", `/pay?${fragment}`);
    const storage = vi.spyOn(Storage.prototype, "setItem");
    vi.resetModules();
    const boot = await import("./cortinaReturn");
    expect(window.location.search).toBe("?cortina_return=1");
    const entry = { pathname: "/pay", search: "?cortina_return=1", hash: "", key: "entry" };
    expect(boot.initialCortinaReturn(entry)?.reference).toEqual(reference);
    expect(boot.initialCortinaReturn({ ...entry, key: "other" })).toBeNull();
    expect(storage).not.toHaveBeenCalled();
    boot.releaseInitialCortinaReturn();
    expect(boot.initialCortinaReturn(entry)).toBeNull();
  });

  it("bootstrap fails closed with a fixed error if authority cannot be removed", async () => {
    window.history.replaceState(null, "", `/pay?${fragment}`);
    vi.spyOn(window.history, "replaceState").mockImplementation(() => { throw new Error(reference.accessToken); });
    vi.resetModules();
    await expect(import("./cortinaReturn")).rejects.toThrow("Payment return address could not be cleared");
  });

  it("entry imports capture before application modules and HTML suppresses referrers before assets", () => {
    expect(mainSource.trimStart().startsWith('import "./cortinaReturn";')).toBe(true);
    const html = new DOMParser().parseFromString(htmlSource, "text/html");
    const meta = html.querySelector('meta[name="referrer"]');
    expect(meta?.getAttribute("content")).toBe("no-referrer");
    for (const resource of html.querySelectorAll("link[href],script[src]")) {
      expect(Boolean(meta!.compareDocumentPosition(resource) & Node.DOCUMENT_POSITION_FOLLOWING)).toBe(true);
    }
  });
});
