import {
  assertEquals,
  assertMatch,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { callbackTestHelpers } from "../_shared/cortina_callback.ts";

Deno.test("extracts transaction identifiers from Nayax callbacks", () => {
  assertEquals(
    callbackTestHelpers.transactionId({ BasicInfo: { TransactionId: "clean-123" } }),
    "clean-123",
  );
  assertEquals(callbackTestHelpers.transactionId({}), null);
  assertEquals(
    callbackTestHelpers.transactionId({ PaymentInfo: { SrvTranId: "clean-456" } }),
    null,
  );
});

Deno.test("extracts terminal ID without treating hardware serial as TerminalId", () => {
  assertEquals(
    callbackTestHelpers.callbackTerminalId({ MachineInfo: { TerminalId: 1234 } }),
    "1234",
  );
  assertEquals(
    callbackTestHelpers.callbackTerminalId({ DeviceInfo: { HwSerial: "hw-1" } }),
    null,
  );
});

Deno.test("formats Nayax timestamps as ddMMyyHHmmss", () => {
  assertMatch(
    callbackTestHelpers.nayaxTimestamp(new Date("2026-08-03T15:04:05Z")),
    /^030826150405$/,
  );
});

Deno.test("reads the final amount from SaleEnd PaymentInfo", () => {
  assertEquals(
    callbackTestHelpers.callbackAmountCents({
      PaymentInfo: { AuthAmount: 1.5, SettAmount: 1.25 },
    }),
    125,
  );
});

Deno.test("callback audit payload excludes card and token data", () => {
  const payload = callbackTestHelpers.auditPayload({
    BasicInfo: { TransactionId: "clean-123", Amount: 1.5, CurrencyCode: "USD" },
    CardInfo: { CardNumber: "sensitive-track-data" },
    PaymentInfo: { RRN: "support-1", Token: "sensitive-token" },
  });

  assertEquals(payload.BasicInfo.TransactionId, "clean-123");
  assertEquals(payload.PaymentInfo.RRN, "support-1");
  assertEquals(payload.CardInfo, undefined);
  assertEquals(payload.PaymentInfo.Token, undefined);
});

Deno.test("callback audit preserves the supported top-level Nayax transaction ID", () => {
  const payload = callbackTestHelpers.auditPayload({
    BasicInfo: { TransactionId: "clean-123", Amount: 4, CurrencyCode: "USD" },
    NayaxTransactionId: 1234567,
  });
  assertEquals(payload.BasicInfo.NayaxTransactionId, 1234567);
});
