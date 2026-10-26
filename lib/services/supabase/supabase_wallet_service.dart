import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_ledger_entry.dart';
import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseWalletService implements WalletService {
  final SupabaseClient client;
  final PaymentService paymentService;

  SupabaseWalletService({required this.client, required this.paymentService});

  Future<dynamic> _refundRpc(
    Session session,
    String rpc,
    Map<String, dynamic> params,
  ) async {
    void checkSession() {
      if (!identical(client.auth.currentSession, session) ||
          client.auth.currentUser?.id != session.user.id ||
          session.accessToken.isEmpty ||
          session.expiresAt == null ||
          session.isExpired) {
        throw StateError('The refund account session changed');
      }
    }

    checkSession();
    var changed = false;
    final subscription = client.auth.onAuthStateChange.listen(
      (state) {
        // This SDK stream replays its latest event to a new subscriber.
        if (!identical(state.session, session) ||
            state.event == AuthChangeEvent.signedOut) {
          changed = true;
        }
      },
      onError: (Object _) {
        changed = true;
      },
      onDone: () {
        changed = true;
      },
    );
    final bearer = 'Bearer ${session.accessToken}';
    try {
      // The SDK can await refresh before HTTP dispatch. Never substitute its
      // later user/token for the caller that opened this operation.
      final result = await client
          .rpc(rpc, params: params)
          .setHeader('Authorization', bearer)
          .timeout(const Duration(seconds: 10));
      checkSession();
      if (changed) throw StateError('The refund session generation changed');
      return result;
    } finally {
      await subscription.cancel();
    }
  }

  List<T> _refundPage<T>(Object? response, T Function(Object?) parse) {
    if (response is! List ||
        response.length > WalletService.topupRefundPageSize) {
      throw const FormatException('Invalid refund page');
    }
    return response.map(parse).toList(growable: false);
  }

  TopupRefund _ownedRefund(Object? value, Session session) {
    final refund = TopupRefund.fromJson(value);
    if (refund.customerId != session.user.id) {
      throw const FormatException('Refund customer mismatch');
    }
    return refund;
  }

  @override
  Future<List<RefundableTopup>> listRefundableTopups({
    required Session session,
    String? beforeLoadId,
  }) async {
    final result =
        await _refundRpc(session, 'list_voluntary_topup_refund_topups', {
          'p_before_load_id': beforeLoadId == null
              ? null
              : topupRefundLoadId(beforeLoadId),
        });
    final page = _refundPage(result, RefundableTopup.fromJson);
    for (final row in page) {
      if (row.refund != null && row.refund!.customerId != session.user.id) {
        throw const FormatException('Top-up customer mismatch');
      }
    }
    return page;
  }

  @override
  Future<List<TopupRefund>> listTopupRefunds({
    required Session session,
    TopupRefund? before,
  }) async {
    if (before != null && before.customerId != session.user.id) {
      throw StateError('Refund cursor account changed');
    }
    return _refundPage(
      await _refundRpc(session, 'list_voluntary_topup_refunds', {
        'p_before': before?.requestedAt.toUtc().toIso8601String(),
        'p_before_id': before?.id,
      }),
      (value) => _ownedRefund(value, session),
    );
  }

  @override
  Future<TopupRefund> requestTopupRefund({
    required Session session,
    required String loadId,
  }) async {
    final result = _ownedRefund(
      await _refundRpc(session, 'request_voluntary_topup_refund', {
        'p_load_id': topupRefundLoadId(loadId),
      }),
      session,
    );
    if (result.loadId != loadId) {
      throw const FormatException('Refund load mismatch');
    }
    return result;
  }

  String get _userId {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No user logged in');
    }
    return userId;
  }

  @override
  Future<WalletBalance> getBalance() async {
    final response = await client
        .from('wallet_balances')
        .select()
        .eq('user_id', _userId)
        .maybeSingle();

    if (response == null) {
      return WalletBalance.empty();
    }

    return WalletBalance.fromJson(response);
  }

  @override
  Future<void> loadCard(int amountCents) async {
    await paymentService.makePayment(
      amountCents / 100.0,
      purpose: PaymentPurpose.walletLoad,
    );
  }

  @override
  Future<Map<String, dynamic>> redeemForMachine({
    required int machineId,
    required int amountCents,
    String? note,
  }) async {
    final response = await client.rpc(
      'redeem_wallet_for_machine',
      params: {
        'target_user_id': _userId,
        'target_machine_id': machineId,
        'amount_cents': amountCents,
        'redemption_note': note,
      },
    );

    return Map<String, dynamic>.from(response as Map);
  }

  @override
  Future<List<WalletLedgerEntry>> getLedger({
    required String userId,
    required String walletAccountId,
    required DateTime since,
    WalletLedgerEntry? before,
    bool rewardsOnly = false,
  }) async {
    if (_userId != userId) throw StateError('Wallet account changed');
    if (walletAccountId.isEmpty) {
      return [];
    }

    var query = client
        .from('wallet_ledger_entries')
        .select()
        .eq('wallet_account_id', walletAccountId)
        .gt('created_at', since.toUtc().toIso8601String());
    if (before != null) {
      final timestamp = before.createdAt.toUtc().toIso8601String();
      query = query.or(
        'created_at.lt.$timestamp,and(created_at.eq.$timestamp,id.lt.${before.id})',
      );
    }
    if (rewardsOnly) {
      query = query.or(
        'entry_type.eq.load_bonus,and(amount_cents.gt.0,promo_amount_cents.gt.0)',
      );
    }
    final response = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(WalletService.ledgerPageSize + 1);
    if (_userId != userId) throw StateError('Wallet account changed');

    return (response as List)
        .map(
          (entry) => WalletLedgerEntry.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList();
  }
}
