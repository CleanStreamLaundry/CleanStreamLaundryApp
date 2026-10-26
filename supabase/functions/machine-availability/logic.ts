export type RecordData = Record<string, unknown>;
export type Availability = {
  status: "idle" | "busy" | "unknown";
  event_code: number | null;
  event_at: string | null;
  reason: string | null;
};

// Nayax's GMT field sometimes omits the Z. Never interpret a VMC-local time as UTC.
export function utcMillis(value: unknown): number {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T/.test(value)) return NaN;
  return Date.parse(/[zZ]$|[+-]\d{2}:\d{2}$/.test(value) ? value : `${value}Z`);
}

export function deriveAvailability(
  alerts: RecordData[], stats: RecordData, now: number, previous?: RecordData,
): Availability {
  const unknown = (reason: string): Availability => ({ status: "unknown", event_code: null, event_at: null, reason });
  if (stats.MachineMQTTStatus !== true) return unknown("offline");
  const deviceEvents = alerts.filter((e) =>
    e.EventSourceName === "Device" && e.EventGroupName === "Vending" &&
    e.EventCategoryName === "Vending" && Number.isFinite(utcMillis(e.EventDateTimeGMT)) &&
    utcMillis(e.EventDateTimeGMT) <= now + 120_000
  );
  const pulses = deviceEvents.filter((e) => [70, 71].includes(Number(e.EventCode)))
    .sort((a, b) => utcMillis(b.EventDateTimeGMT) - utcMillis(a.EventDateTimeGMT));
  const latest = pulses[0];
  if (!latest) return unknown("no_signal");
  const at = utcMillis(latest.EventDateTimeGMT);
  if (pulses.some((e) => utcMillis(e.EventDateTimeGMT) === at && Number(e.EventCode) !== Number(latest.EventCode))) {
    return unknown("conflicting_signals");
  }
  // Readers also report VMC power-up as code 24 (observed on reader 0568).
  if (deviceEvents.some((e) => [1, 24].includes(Number(e.EventCode)) && utcMillis(e.EventDateTimeGMT) >= at)) {
    return unknown("awaiting_signal_after_restart");
  }
  // Statistics provide a restart timestamp even when it has left lastAlerts.
  // Unlike EventDateTimeGMT, accept these dates only with an explicit UTC offset.
  const powerUp = stats.LastPowerUpDateTime;
  if (typeof powerUp === "string" && /[zZ]$|[+-]\d{2}:\d{2}$/.test(powerUp) && utcMillis(powerUp) >= at) {
    return unknown("awaiting_signal_after_restart");
  }
  const priorEvent = utcMillis(previous?.event_at);
  if (Number.isFinite(priorEvent) && priorEvent > at) return unknown("stale_event_history");
  // Following a reported disconnect, an old idle event cannot establish readiness.
  const gap = utcMillis(previous?.reconcile_after);
  if (Number.isFinite(gap) && at <= gap) return unknown("awaiting_signal_after_disconnect");
  return { status: Number(latest.EventCode) === 70 ? "busy" : "idle", event_code: Number(latest.EventCode), event_at: new Date(at).toISOString(), reason: null };
}

export function summarize(machines: RecordData[], states: RecordData[], now: number) {
  const groups = { washers: { total: 0, available: 0, busy: 0, unknown: 0 }, dryers: { total: 0, available: 0, busy: 0, unknown: 0 } };
  for (const machine of machines) {
    const group = machine.Machine_type === "Washer" ? groups.washers : machine.Machine_type === "Dryer" ? groups.dryers : null;
    if (!group) continue;
    group.total++;
    const row = states.find((s) => s.machine_id === machine.id);
    const checked = utcMillis(row?.checked_at);
    const status = Number.isFinite(checked) && now - checked <= 30_000 ? row?.status : "unknown";
    const operating = ["idle", "busy", "running", "unknown", "offline"].includes(String(machine.Status).toLowerCase());
    if (status === "idle" && operating) group.available++;
    else if (status === "busy" || !operating) group.busy++;
    else group.unknown++;
  }
  const times = states.map((s) => utcMillis(s.checked_at)).filter(Number.isFinite);
  return { ...groups, checkedAt: times.length ? new Date(Math.min(...times)).toISOString() : null };
}
