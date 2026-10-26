import 'dart:async';

import 'package:clean_stream_laundry_app/logic/services/admin_wallet_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAdminWalletService implements AdminWalletService {
  final SupabaseClient client;

  SupabaseAdminWalletService({required this.client});

  @override
  Future<List<Map<String, dynamic>>> searchWallets(String query) async {
    return await _readWallet('search', {'query': query.trim()});
  }

  @override
  Future<Map<String, dynamic>> getWalletDetail(String walletAccountId) async {
    return await _readWallet('detail', {'walletId': walletAccountId});
  }

  List<Map<String, dynamic>> _rows(Object? value, int limit) {
    if (value is! List ||
        value.length > limit ||
        value.any((row) => row is! Map)) {
      throw const FormatException('Invalid wallet rows');
    }
    return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  String? _historyId(Object? id) {
    if (id is int) {
      return id.toString();
    }
    if (id is String && RegExp(r'^-?[0-9]+$').hasMatch(id)) {
      return BigInt.tryParse(id)?.toString();
    }
    return null;
  }

  Future<T> _withCaller<T>(
    Future<T> Function(
      Future<dynamic> Function(String, Map<String, dynamic>) rpc,
    ) operation,
  ) async {
    final session = client.auth.currentSession;
    if (session == null) {
      throw StateError('Wallet owner session required');
    }
    void checkSession() {
      if (!identical(client.auth.currentSession, session) ||
          client.auth.currentUser?.id != session.user.id ||
          session.accessToken.isEmpty ||
          session.expiresAt == null ||
          session.isExpired) {
        throw StateError('Wallet owner session changed');
      }
    }

    checkSession();
    var changed = false;
    final subscription = client.auth.onAuthStateChange.listen(
      (state) {
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
    Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
      checkSession();
      if (changed) {
        throw StateError('Wallet owner session generation changed');
      }
      // Bind transport even when the SDK awaits refresh before dispatch.
      // Session rejection cannot undo an already dispatched mutation.
      final response = await client
          .rpc(name, params: params)
          .setHeader('Authorization', bearer);
      checkSession();
      if (changed) {
        throw StateError('Wallet owner session generation changed');
      }
      return response;
    }

    try {
      final result = await operation(rpc);
      checkSession();
      if (changed) {
        throw StateError('Wallet owner session generation changed');
      }
      return result;
    } finally {
      await subscription.cancel();
    }
  }

  Future<dynamic> _readWallet(String action, Map<String, dynamic> payload) {
    final clock = Stopwatch()..start();
    const deadline = Duration(seconds: 10);
    return _withCaller((rpc) async {
      const refreshNeeded = 'Wallet data changed or is incomplete; refresh needed';
      final items = <Map<String, dynamic>>[];
      final walletIds = <String>{};
      final detail = <String, List<Map<String, dynamic>>>{
        'loads': [],
        'redemptions': [],
        'ledger': [],
      };
      final detailIds = <String, Set<String>>{
        for (final name in detail.keys) name: <String>{},
      };
      Map<String, dynamic>? balance;
      Object? after;
      var page = 1;
      while (true) {
        final remaining = deadline - clock.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('Wallet read timed out');
        }
        final response = await rpc('admin_wallet_read', {
          'action': action,
          'payload': {...payload, 'page': page, if (page > 1) 'after': after},
        }).timeout(remaining);
        final pageSize = action == 'search' ? 25 : 100;
        if (response is! Map ||
            response['page'] != page ||
            response['pageSize'] != pageSize) {
          throw const FormatException('Invalid wallet page');
        }
        if (action == 'search') {
          final rows = _rows(response['items'], 25);
          final total = response['total'];
          if (total is! int || total < 0 || !response.containsKey('nextCursor')) {
            throw const FormatException('Invalid wallet search count');
          }
          final next = response['nextCursor'];
          if (next != null &&
              (next is! String ||
                  rows.length != 25 ||
                  next != rows.last['wallet_account_id'] ||
                  !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(next) ||
                  (after is String && next.toLowerCase().compareTo(after.toLowerCase()) <= 0))) {
            throw const FormatException('Invalid wallet search cursor');
          }
          for (final row in rows) {
            final id = row['wallet_account_id'];
            if (id is! String ||
                id.trim().isEmpty ||
                !walletIds.add(id.toLowerCase())) {
              throw StateError(refreshNeeded);
            }
          }
          items.addAll(rows);
          final limit = (payload['query'] as String).isEmpty ? 25 : 100;
          if (items.length >= limit || next == null) {
            return items;
          }
          after = next;
        } else {
          if (response['balance'] is! Map ||
              response['hasMore'] is! Map || response['nextCursor'] is! Map) {
            throw const FormatException('Invalid wallet detail');
          }
          final pageBalance = Map<String, dynamic>.from(
            response['balance'] as Map,
          );
          if (pageBalance['wallet_account_id'] != payload['walletId']) {
            throw const FormatException('Wallet detail mismatch');
          }
          if (balance != null &&
              const [
                'user_id',
                'status',
                'paid_balance_cents',
                'promo_balance_cents',
                'total_balance_cents',
              ].any((field) => balance![field] != pageBalance[field])) {
            throw StateError(refreshNeeded);
          }
          balance ??= pageBalance;
          var hasMore = false;
          final nextCursors = <String, Object?>{};
          for (final name in detail.keys) {
            final rows = _rows(response[name], 100);
            final more = (response['hasMore'] as Map)[name];
            if (more is! bool || (more && rows.length != 100)) {
              throw const FormatException('Invalid wallet continuation');
            }
            // Cursor continuation still fails closed on repeated identities.
            for (final row in rows) {
              final key = _historyId(row['id']);
              if (key == null || !detailIds[name]!.add(key)) {
                throw StateError(refreshNeeded);
              }
            }
            final cursors = response['nextCursor'] as Map;
            if (!cursors.containsKey(name)) {
              throw const FormatException('Missing wallet cursor');
            }
            final next = cursors[name];
            final previous = after is Map ? after[name] : null;
            if (page > 1 && previous == null && (rows.isNotEmpty || more)) {
              throw StateError(refreshNeeded);
            }
            if (more) {
              if (next is! Map ||
                  next['createdAt'] is! String || next['id'] is! String) {
                throw const FormatException('Invalid wallet detail cursor');
              }
              final timestamp = DateTime.tryParse(next['createdAt'] as String);
              final id = _historyId(next['id']);
              if (timestamp == null || id == null || BigInt.parse(id) <= BigInt.zero ||
                  next['createdAt'] != rows.last['created_at'] ||
                  id != _historyId(rows.last['id'])) {
                throw const FormatException('Invalid wallet detail cursor');
              }
              if (previous is Map) {
                final previousTime = DateTime.parse(previous['createdAt'] as String);
                if (timestamp.isAfter(previousTime) ||
                    (timestamp.isAtSameMomentAs(previousTime) &&
                        BigInt.parse(id) >= BigInt.parse(previous['id'] as String))) {
                  throw StateError(refreshNeeded);
                }
              }
              // Preserve timestamp precision and decimal ID bytes on the wire.
              nextCursors[name] = {'createdAt': next['createdAt'], 'id': next['id']};
            } else {
              if (next != null) {
                throw const FormatException('Unexpected wallet cursor');
              }
              nextCursors[name] = null;
            }
            detail[name]!.addAll(rows);
            hasMore = hasMore || more;
          }
          if (!hasMore) {
            return {'balance': balance, ...detail};
          }
          after = nextCursors;
        }
        page++;
      }
    }).whenComplete(clock.stop);
  }

  @override
  Future<void> adjustWallet({
    required String walletAccountId,
    required int amountCents,
    required int paidAmountCents,
    required int promoAmountCents,
    required String note,
  }) async {
    await _withCaller((rpc) => rpc(
      'admin_adjust_wallet',
      {
        'wallet_id': walletAccountId,
        'amount_cents': amountCents,
        'paid_amount_cents': paidAmountCents,
        'promo_amount_cents': promoAmountCents,
        'adjustment_note': note,
      },
    ));
  }

  @override
  Future<void> lockWallet(String walletAccountId, bool locked) async {
    await _withCaller((rpc) => rpc(
      'admin_set_wallet_status',
      {
        'wallet_id': walletAccountId,
        'new_status': locked ? 'locked' : 'active',
        'status_note': locked
            ? 'Wallet locked by admin'
            : 'Wallet unlocked by admin',
      },
    ));
  }

  @override
  Future<void> recordCashRedemptionOrStripeRefund({
    required String walletAccountId,
    required int amountCents,
    required String note,
  }) async {
    await _withCaller((rpc) => rpc(
      'admin_record_legal_cash_redemption',
      {
        'wallet_id': walletAccountId,
        'amount_cents': amountCents.abs(),
        'stripe_refund_id': null,
        'redemption_note': note,
      },
    ));
  }

  @override
  Future<void> recordDeletedAccountComplaint({
    required String walletAccountId,
    required String note,
    String resolution = 'denied',
  }) async {
    await _withCaller((rpc) => rpc(
      'record_deleted_account_complaint',
      {
        'wallet_id': walletAccountId,
        'complaint_note': note,
        'resolution': resolution,
      },
    ));
  }
}
