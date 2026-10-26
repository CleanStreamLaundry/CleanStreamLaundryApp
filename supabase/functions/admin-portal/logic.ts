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
export type PortalRole = "Owner" | "Manager" | "Maintenance";
export function requirePortalAction(role: PortalRole | undefined, action: string, payload: Record<string, unknown> = {}) {
  if (role === "Owner") return;
  if ((role === "Manager" || role === "Maintenance") &&
    ["identity", "locations", "maintenance", "history", "updateMaintenance", "assignees"].includes(action)) return;
  if (role === "Manager" && ["overview", "machines", "team", "setAvailability"].includes(action)) return;
  if (action === "exportRecords" && ((role === "Manager" && ["maintenance", "machines"].includes(String(payload.dataset))) ||
    (role === "Maintenance" && payload.dataset === "maintenance"))) return;
  throw new PortalError("You do not have access to this operation.", 403, "admin_forbidden");
}
export interface PortalDependencies {
  machineIssue?(action: string, payload: Record<string, unknown>): Promise<unknown>;
  manageStaff?(action: string, payload: Record<string, unknown>): Promise<unknown>;
  manageOwners?(action: string, payload: Record<string, unknown>): Promise<unknown>;
  geocode?(actor: string, address: unknown): Promise<unknown>;
  authenticate(token: string): Promise<string>;
  rpc(
    actor: string,
    action: string,
    payload: Record<string, unknown>,
  ): Promise<unknown>;
  invite(actor: string, email: string, locationIds: number[], portalRole?: "Manager" | "Maintenance"): Promise<unknown>;
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
  if (action === "machineIssueReview" || action === "resolveMachineIssue") {
    if (!deps.machineIssue) throw new PortalError("Machine issue review is unavailable.", 503, "admin_unavailable");
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!Number.isSafeInteger(body.id) || Number(body.id) <= 0 ||
      (body.requestId !== undefined && (typeof body.requestId !== "string" || !uuid.test(body.requestId)))) {
      throw new PortalError("Invalid machine issue reference.");
    }
    if (action === "machineIssueReview") return deps.machineIssue(action, {
      id: body.id, ...(body.requestId === undefined ? {} : { requestId: body.requestId }),
    });
    if (typeof body.requestId !== "string" || !uuid.test(body.requestId) ||
      !["wallet_refund", "replacement_vend", "manual_review"].includes(String(body.resolution)) ||
      typeof body.note !== "string" || !body.note.trim() || body.note.trim().length > 4000 ||
      typeof body.atLocation !== "boolean" || typeof body.anotherLoadCompleted !== "boolean" ||
      (body.resolution === "replacement_vend" && (!Number.isSafeInteger(body.replacementMachineId) || Number(body.replacementMachineId) <= 0))) {
      throw new PortalError("Invalid machine issue decision.");
    }
    return deps.machineIssue(action, { id: body.id, requestId: body.requestId, resolution: body.resolution,
      note: body.note.trim(), atLocation: body.atLocation, anotherLoadCompleted: body.anotherLoadCompleted,
      ...(body.resolution === "replacement_vend" ? { replacementMachineId: body.replacementMachineId } : {}),
    });
  }
  if (["setStaffRole", "staffRoleStatus"].includes(action)) {
    if (!deps.manageStaff) throw new PortalError("Staff role management is unavailable.", 503, "admin_unavailable");
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (typeof body.requestId !== "string" || !uuid.test(body.requestId)) throw new PortalError("Invalid request reference.");
    if (action === "staffRoleStatus") return deps.manageStaff(action, { requestId: body.requestId });
    if (typeof body.userId !== "string" || !uuid.test(body.userId) ||
      !["Manager", "Maintenance"].includes(String(body.portalRole)) ||
      !["Manager", "Maintenance"].includes(String(body.expectedPortalRole)) ||
      typeof body.note !== "string" || !body.note.trim() || body.note.trim().length > 4000) {
      throw new PortalError("Invalid staff role change.");
    }
    if (body.userId.toLowerCase() === actor.toLowerCase()) throw new PortalError("You cannot change your own staff role.", 403, "admin_forbidden");
    return deps.manageStaff(action, { userId: body.userId, portalRole: body.portalRole,
      expectedPortalRole: body.expectedPortalRole, requestId: body.requestId, note: body.note.trim() });
  }
  if (["ownerAccounts", "setOwner", "ownerChangeStatus"].includes(action)) {
    if (!deps.manageOwners) throw new PortalError("Owner management is unavailable.", 503, "admin_unavailable");
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (action === "ownerAccounts") {
      if ((body.query !== undefined && (typeof body.query !== "string" || body.query.length > 254)) ||
        (body.page !== undefined && (!Number.isSafeInteger(body.page) || Number(body.page) < 1 || Number(body.page) > 100000))) {
        throw new PortalError("Invalid account lookup.");
      }
      return deps.manageOwners(action, { query: String(body.query ?? "").trim(), page: body.page ?? 1 });
    }
    if (typeof body.requestId !== "string" || !uuid.test(body.requestId)) throw new PortalError("Invalid request reference.");
    if (action === "ownerChangeStatus") return deps.manageOwners(action, { requestId: body.requestId });
    if (typeof body.userId !== "string" || !uuid.test(body.userId) || typeof body.owner !== "boolean" ||
      !["User", "Admin", "Owner"].includes(String(body.expectedRole)) || typeof body.note !== "string" ||
      !body.note.trim() || body.note.trim().length > 4000) throw new PortalError("Invalid Owner change.");
    if (body.userId.toLowerCase() === actor.toLowerCase()) throw new PortalError("You cannot change your own Owner role.", 403, "admin_forbidden");
    return deps.manageOwners(action, {
      userId: body.userId, owner: body.owner, expectedRole: body.expectedRole,
      requestId: body.requestId, note: body.note.trim(),
    });
  }
  if (action === "geocode") {
    if (!deps.geocode) throw new PortalError("Address lookup is unavailable.", 503);
    return deps.geocode(actor, body.address);
  }
  if (action === "invite") {
    const portalRole = body.portalRole ?? "Manager";
    if (portalRole !== "Manager" && portalRole !== "Maintenance") throw new PortalError("Choose a valid staff role.");
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
    ] as number[], portalRole);
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
