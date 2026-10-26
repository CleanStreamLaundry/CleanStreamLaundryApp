export type MachineIssueResolutionKind = "wallet_refund" | "replacement_vend" | "manual_review";
export type MachineIssueResolutionState = "recorded" | "pending" | "completed" | "support_required";

export interface MachineIssueReceipt {
  requestId: string;
  resolution: MachineIssueResolutionKind;
  state: MachineIssueResolutionState;
}

export interface MachineIssueReview {
  refundId: number;
  transactionId: number;
  status: "pending" | "approved" | "denied";
  policyVersion: "legacy_14_day" | "same_day_v1";
  amountCents: number | null;
  paidAmountCents: number | null;
  promoAmountCents: number | null;
  locationId: number | null;
  locationTimezone: string | null;
  transactionAt: string | null;
  receivedAt: string;
  sameDayEligible: boolean;
  manualReviewReason: string | null;
  financialResolution: { kind: "wallet_refund" | "replacement_vend"; state: "pending" | "completed" | "support_required"; requestId: string } | null;
  receipt: MachineIssueReceipt | null;
  capabilities: { walletRefund: boolean; replacementVend: boolean };
  replacementMachines: Array<{ id: number; name: string; amountCents: number }>;
  replacementUnavailableReason: string | null;
}

export interface MachineIssueResolutionResult {
  success: true;
  alreadyResolved: boolean;
  review: MachineIssueReview;
}
