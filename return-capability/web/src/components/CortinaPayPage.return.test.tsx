import { StrictMode } from "react";
import { act, cleanup, render, screen, waitFor } from "@testing-library/react";
import { BrowserRouter } from "react-router-dom";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { CortinaVendService } from "../interfaces/CortinaVendService";
import CortinaPayPage from "./CortinaPayPage";

const service = {
  quote: vi.fn<CortinaVendService["quote"]>(), createCard: vi.fn<CortinaVendService["createCard"]>(),
  payWithWallet: vi.fn<CortinaVendService["payWithWallet"]>(),
  status: vi.fn<CortinaVendService["status"]>(), hasSession: vi.fn<CortinaVendService["hasSession"]>(),
};
vi.mock("../di/container", () => ({ useCortinaVend: () => service }));
const sessionId = "00000000-0000-4000-8000-000000000001";
const accessToken = "ABCDEF00-0000-4000-8000-000000000002";
const fields = new URLSearchParams({ session: sessionId, access: accessToken }).toString();

beforeEach(() => { vi.resetAllMocks(); window.history.replaceState(null, "", "/"); });
afterEach(() => { cleanup(); vi.restoreAllMocks(); window.history.replaceState(null, "", "/"); });
const open = (path: string) => {
  window.history.replaceState(null, "", path);
  return render(<StrictMode><BrowserRouter><CortinaPayPage /></BrowserRouter></StrictMode>);
};
const noPayments = () => {
  expect(service.createCard).not.toHaveBeenCalled();
  expect(service.payWithWallet).not.toHaveBeenCalled();
  expect(service.quote).not.toHaveBeenCalled();
};

it("fragment return scrubs before status transport and preserves authoritative started outcome", async () => {
  service.status.mockImplementation((reference) => {
    expect(window.location.search).toBe("?cortina_return=1");
    expect(window.location.hash).toBe("");
    expect(reference).toEqual({ sessionId, accessToken });
    return Promise.resolve({ status: "started" });
  });
  open(`/pay?cortina_return=1#${fields}`);
  expect(await screen.findByText("Machine started")).toBeInTheDocument();
  noPayments();
  expect(JSON.stringify(window.history.state)).not.toContain(accessToken);
});

it("legacy query return scrubs before status and preserves confirmed refund display", async () => {
  service.status.mockImplementation((reference) => {
    expect(window.location.href).not.toContain(accessToken);
    expect(window.location.search).toBe("?cortina_return=1");
    expect(reference).toEqual({ sessionId, accessToken });
    return Promise.resolve({ status: "refunded" });
  });
  open(`/pay?${fields}`);
  expect(await screen.findByText("Refund initiated")).toBeInTheDocument();
  noPayments();
});

it("partial mixed and missing fragment returns scrub and remain support-only", async () => {
  for (const path of ["/pay?machine=public&cortina_return=1", `/pay?session=${sessionId}#access=${accessToken}`,
    `/pay?machine=public#access=${accessToken}`]) {
    const view = open(path);
    expect(await screen.findByText("Confirmation unavailable")).toBeInTheDocument();
    expect(window.location.href).not.toContain(accessToken);
    expect(service.status).not.toHaveBeenCalled();
    expect(service.hasSession).not.toHaveBeenCalled();
    noPayments();
    view.unmount();
  }
});

it("reload after scrubbing does not persist a capability or offer another payment", async () => {
  const storage = vi.spyOn(Storage.prototype, "setItem");
  service.status.mockResolvedValue({ status: "support_required" });
  const first = open(`/pay?cortina_return=1#${fields}`);
  expect(await screen.findByText("Confirmation unavailable")).toBeInTheDocument();
  const cleanPath = window.location.pathname + window.location.search + window.location.hash;
  const requests = service.status.mock.calls.length;
  first.unmount();
  open(cleanPath);
  expect(await screen.findByText("Confirmation unavailable")).toBeInTheDocument();
  expect(service.status).toHaveBeenCalledTimes(requests);
  expect(storage).not.toHaveBeenCalled();
  noPayments();
});

it("failure to scrub prevents status and all payment calls without showing diagnostics", async () => {
  window.history.replaceState({ idx: 0 }, "", `/pay?${fields}`);
  vi.spyOn(window.history, "replaceState").mockImplementation(() => { throw new Error(accessToken); });
  render(<BrowserRouter><CortinaPayPage /></BrowserRouter>);
  expect(await screen.findByText("Confirmation unavailable")).toBeInTheDocument();
  expect(screen.queryByText(accessToken)).not.toBeInTheDocument();
  expect(service.status).not.toHaveBeenCalled();
  noPayments();
});

it("a newer fragment return wins over a late status response from the old reference", async () => {
  let finish!: (result: { status: string }) => void;
  const old = new Promise<{ status: string }>((resolve) => { finish = resolve; });
  service.status.mockReturnValueOnce(old).mockResolvedValue({ status: "support_required" });
  open(`/pay?${fields}`);
  await waitFor(() => expect(service.status).toHaveBeenCalledTimes(1));
  await act(async () => {
    window.history.pushState({ idx: 1, key: "new" }, "", "/pay?cortina_return=1#session=new&access=new-secret");
    window.dispatchEvent(new PopStateEvent("popstate"));
  });
  expect(await screen.findByText("Confirmation unavailable")).toBeInTheDocument();
  await act(async () => { finish({ status: "started" }); });
  expect(screen.queryByText("Machine started")).not.toBeInTheDocument();
  expect(window.location.hash).toBe("");
  expect(service.status.mock.calls).toEqual([[{ sessionId, accessToken }], [{ sessionId: "new", accessToken: "new-secret" }]]);
  noPayments();
});
