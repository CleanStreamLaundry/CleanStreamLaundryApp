export class PortalError extends Error {
  status: number;
  code: string;
  nextStep?: string;
  constructor(
    message: string,
    status = 400,
    code = "invalid_request",
    nextStep?: string,
  ) {
    super(message);
    this.status = status;
    this.code = code;
    this.nextStep = nextStep;
  }
}
export interface PortalDependencies {
  authenticate(token: string): Promise<string>;
  rpc(
    actor: string,
    action: string,
    payload: Record<string, unknown>,
  ): Promise<unknown>;
  invite(actor: string, email: string, locationIds: number[]): Promise<unknown>;
  resend(actor: string, userId: string, locationId: number): Promise<unknown>;
  resolve(
    token: string,
    id: number,
    decision: string,
    note: string,
  ): Promise<unknown>;
}
const dataActions = new Set([
  "identity",
  "locations",
  "machines",
  "rates",
  "maintenance",
  "history",
  "updateMaintenance",
  "credits",
  "team",
  "overview",
  "createLocation",
  "createMachine",
  "deleteMachine",
  "saveRate",
  "saveConfig",
  "removeMember",
  "transactions",
  "audit",
  "assignees",
  "setAvailability",
  "exportRecords",
]);
export async function dispatchPortal(
  token: string,
  body: Record<string, unknown>,
  deps: PortalDependencies,
) {
  if (!token) throw new PortalError("Sign in to continue.", 401);
  const actor = await deps.authenticate(token);
  const action = String(body.action ?? "");
  // Always derive actor from the verified token; never from request JSON.
  if (action === "invite") {
    const email = String(body.email ?? "")
      .trim()
      .toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
      throw new PortalError("Enter a valid email address.");
    }
    if (
      !Array.isArray(body.locationIds) ||
      !body.locationIds.length ||
      body.locationIds.length > 50 ||
      !body.locationIds.every(
        (id) => Number.isSafeInteger(id) && Number(id) > 0,
      )
    ) {
      throw new PortalError("Choose at least one valid location.");
    }
    return deps.invite(actor, email, [
      ...new Set(body.locationIds),
    ] as number[]);
  }
  if (action === "resend") {
    if (
      !/^[0-9a-f-]{36}$/i.test(String(body.userId ?? "")) ||
      !Number.isSafeInteger(body.locationId) ||
      Number(body.locationId) <= 0
    ) {
      throw new PortalError("Invalid team membership.");
    }
    return deps.resend(actor, String(body.userId), Number(body.locationId));
  }
  if (action === "resolveCredit") {
    if (
      !Number.isSafeInteger(body.id) ||
      Number(body.id) <= 0 ||
      !["approved", "denied"].includes(String(body.decision)) ||
      String(body.note ?? "").length > 4000
    ) {
      throw new PortalError("Invalid loyalty credit decision.");
    }
    await deps.rpc(actor, "assertCredit", { id: body.id });
    return deps.resolve(
      token,
      Number(body.id),
      String(body.decision),
      String(body.note ?? ""),
    );
  }
  if (!dataActions.has(action)) throw new PortalError("Unknown admin action.");
  return deps.rpc(actor, action, body);
}
