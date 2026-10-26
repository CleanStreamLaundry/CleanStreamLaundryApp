import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_ledger_entry.dart';
import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class WalletService {
  static const ledgerPageSize = 25;
  static const topupRefundPageSize = 100;

  Future<List<RefundableTopup>> listRefundableTopups({
    required Session session,
    String? beforeLoadId,
  });
  Future<List<TopupRefund>> listTopupRefunds({
    required Session session,
    TopupRefund? before,
  });
  Future<TopupRefund> requestTopupRefund({
    required Session session,
    required String loadId,
  });

  Future<WalletBalance> getBalance();
  Future<void> loadCard(int amountCents);
  Future<Map<String, dynamic>> redeemForMachine({
    required int machineId,
    required int amountCents,
    String? note,
  });
  // Returns at most pageSize + 1 rows; the extra row signals another page.
  Future<List<WalletLedgerEntry>> getLedger({
    required String userId,
    required String walletAccountId,
    required DateTime since,
    WalletLedgerEntry? before,
    bool rewardsOnly = false,
  });
}
