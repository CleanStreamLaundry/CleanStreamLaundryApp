export interface NewPaymentControlClient {
  rpc(name: "new_payments_enabled"): {
    abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }>;
  };
}

export class NewPaymentsUnavailableError extends Error {
  constructor() {
    super("new_payments_unavailable");
  }
}

// Reuse each adapter's configured SDK transport, including named-secret headers.
// This fixed reader is operational state, never human admission or settlement.
export async function requireNewPayments(client: NewPaymentControlClient | undefined): Promise<void> {
  try {
    if (!client) throw new NewPaymentsUnavailableError();
    const { data, error } = await client.rpc("new_payments_enabled")
      .abortSignal(AbortSignal.timeout(8000));
    if (error || data !== true) throw new NewPaymentsUnavailableError();
  } catch {
    throw new NewPaymentsUnavailableError();
  }
}
