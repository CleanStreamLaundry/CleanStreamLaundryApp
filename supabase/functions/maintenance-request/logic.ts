export interface MaintenanceUser {
  id: string;
  is_anonymous?: boolean;
}

export interface MaintenanceSubmission {
  user_id: string;
  category: string;
  description: string;
  location: string;
  location_id: string | null;
  attachment: { name: string } | null;
}

export interface MaintenanceDeps {
  storageUrl: string;
  authenticate(token: string): Promise<MaintenanceUser | null>;
  submit(request: MaintenanceSubmission): Promise<{
    data: unknown;
    error: { code?: string; message?: string } | null;
  }>;
}

const maxBodyBytes = 32 * 1024;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const categories = new Set([
  "Washer/Dryer Maintenance",
  "App Maintenance",
  "Location Maintenance",
  "Other",
]);
const errors = {
  unauthorized: [401, "Sign in to submit a maintenance request."],
  user_mismatch: [403, "The request does not match the signed-in account."],
  account_restricted: [
    403,
    "This account cannot submit a maintenance request.",
  ],
  invalid_request: [400, "Invalid maintenance request."],
  request_too_large: [413, "Maintenance request is too large."],
  maintenance_unavailable: [503, "Maintenance request unavailable."],
} as const;

class RequestError extends Error {
  constructor(readonly code: keyof typeof errors) {
    super(code);
  }
}

function fail(code: keyof typeof errors): never {
  throw new RequestError(code);
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  if (Number(req.headers.get("content-length")) > maxBodyBytes) {
    fail("request_too_large");
  }
  if (!req.body) fail("invalid_request");
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBodyBytes) {
        await reader.cancel();
        fail("request_too_large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const body = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      fail("invalid_request");
    }
    return body;
  } catch {
    fail("invalid_request");
  }
}

function requiredText(value: unknown, maxLength: number): string {
  if (
    typeof value !== "string" || !value.trim() || value.length > maxLength ||
    value.includes("\0")
  ) fail("invalid_request");
  return value;
}

function attachmentName(image: string, storageUrl: string): string {
  const base = new URL(storageUrl);
  let url: URL;
  try {
    url = new URL(image);
  } catch {
    fail("invalid_request");
  }
  const prefix = "/storage/v1/object/public/maintenance-images/";
  if (
    url.origin !== base.origin || url.username || url.password ||
    image !== url.href || /[?#\\]/.test(image) ||
    !url.pathname.startsWith(prefix)
  ) fail("invalid_request");
  let parts: string[];
  try {
    parts = url.pathname.slice(prefix.length).split("/").map(
      decodeURIComponent,
    );
  } catch {
    fail("invalid_request");
  }
  if (
    parts.some((part) =>
      !part || part === "." || part === ".." || /[/\\]/.test(part) ||
      [...part].some((c) => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127)
    ) ||
    parts.map(encodeURIComponent).join("/") !==
      url.pathname.slice(prefix.length)
  ) fail("invalid_request");
  return parts.join("/");
}

function isObject(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

export async function handleMaintenance(
  req: Request,
  createDeps: (token: string) => MaintenanceDeps,
) {
  try {
    const token = /^Bearer\s+(\S+)$/i.exec(
      req.headers.get("authorization") ?? "",
    )
      ?.[1];
    if (!token) fail("unauthorized");
    const deps = createDeps(token);
    const user = await deps.authenticate(token);
    if (!user || !uuid.test(user.id) || user.is_anonymous !== false) {
      fail("unauthorized");
    }
    const body = await readBody(req);
    if (body.user_id !== undefined) {
      if (typeof body.user_id !== "string" || !uuid.test(body.user_id)) {
        fail("invalid_request");
      }
      if (body.user_id.toLowerCase() !== user.id.toLowerCase()) {
        fail("user_mismatch");
      }
    }
    const category = requiredText(body.category, 64);
    if (!categories.has(category)) fail("invalid_request");
    const description = requiredText(body.description, 4000);
    const location = requiredText(body.location, 1000);
    const image = body.image == null ? null : requiredText(body.image, 2048);
    const locationId = body.location_id ?? null;
    if (
      locationId !== null && (typeof locationId !== "string" ||
        !/^[1-9][0-9]{0,18}$/.test(locationId) ||
        BigInt(locationId) > 9223372036854775807n)
    ) fail("invalid_request");
    const attachment = image === null
      ? null
      : { name: attachmentName(image, deps.storageUrl) };
    const { data, error } = await deps.submit({
      user_id: user.id,
      category,
      description,
      location,
      location_id: locationId,
      attachment,
    });
    if (error) {
      if (error.code === "PT401") fail("unauthorized");
      if (error.code === "PT403") {
        fail(
          error.message === "user_mismatch"
            ? "user_mismatch"
            : "account_restricted",
        );
      }
      if (error.code === "PT400") fail("invalid_request");
      fail("maintenance_unavailable");
    }
    const records = isObject(data) ? data.record : null;
    const row = Array.isArray(records) && records.length === 1
      ? records[0]
      : null;
    if (
      !isObject(data) || data.success !== true ||
      data.message !== "Request logged" ||
      !isObject(row) || row.user_id !== user.id ||
      typeof row.maint_id !== "number" || !Number.isSafeInteger(row.maint_id) ||
      row.maint_id < 1 ||
      (locationId === null
        ? row.location_id !== null
        : typeof row.location_id !== "number" ||
          !Number.isSafeInteger(row.location_id) ||
          String(row.location_id) !== locationId) ||
      typeof row.created_at !== "string" ||
      !Number.isFinite(Date.parse(row.created_at)) ||
      row.category !== category || row.description !== description ||
      row.location !== location ||
      row.image_data !== null ||
      (attachment === null
        ? row.attachment_ref !== null
        : !isObject(row.attachment_ref) ||
          row.attachment_ref.bucket !== "maintenance-images" ||
          typeof row.attachment_ref.id !== "string" ||
          !uuid.test(row.attachment_ref.id) ||
          row.attachment_ref.name !== attachment.name ||
          (row.attachment_ref.version !== null &&
            typeof row.attachment_ref.version !== "string"))
    ) fail("maintenance_unavailable");
    return { status: 200, body: data };
  } catch (error) {
    const code = error instanceof RequestError
      ? error.code
      : "maintenance_unavailable";
    const [status, message] = errors[code];
    return { status, body: { error: message, code } };
  }
}
