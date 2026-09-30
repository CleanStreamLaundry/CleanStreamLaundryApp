import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const customerA = '11111111-1111-1111-1111-111111111111';
const customerB = '22222222-2222-2222-2222-222222222222';
const refundId = '33333333-3333-3333-3333-333333333333';

Session refundSession({String id = customerA, int seconds = 3600}) {
  String part(Object data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return Session(
    accessToken:
        '${part({'alg': 'HS256'})}.${part({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds})}.synthetic',
    tokenType: 'bearer',
    refreshToken: 'synthetic-refresh',
    user: User(
      id: id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '',
    ),
  );
}

Map<String, dynamic> refundJson({
  String load = '9007199254740993',
  String status = 'requested',
  String customer = customerA,
  String id = refundId,
}) => {
  'id': id,
  'load_id': load,
  'customer_id': customer,
  'status': status,
  'principal_cents': 2000,
  'bonus_reserved_cents': 500,
  'currency': 'usd',
  'requested_at': '2026-09-30T10:00:00+00:00',
  'payment_succeeded_at': '2026-09-29T10:00:00+00:00',
  'reviewed_at': status == 'requested' ? null : '2026-09-30T11:00:00+00:00',
  'completed_at': status == 'succeeded' ? '2026-09-30T12:00:00+00:00' : null,
  'policy_version': 'voluntary-topup-v1',
  'location_id': null,
  'review_note': null,
};

Map<String, dynamic> topupJson({
  String load = '9007199254740993',
  String? reason,
  Map<String, dynamic>? refund,
}) => {
  'load_id': load,
  'principal_cents': 2000,
  'currency': 'usd',
  'payment_succeeded_at': '2026-09-29T10:00:00+00:00',
  'request_deadline': '2026-10-01T10:00:00+00:00',
  'ineligible_reason': reason,
  'refund': refund,
};

class RefundAuth extends Mock implements AuthService {}

class RefundWallet extends Mock implements WalletService {}

class RefundHarness {
  final auth = RefundAuth();
  final wallet = RefundWallet();
  final changes = StreamController<AuthState>.broadcast(sync: true);
  Session? session = refundSession();
  List<RefundableTopup> topups = [RefundableTopup.fromJson(topupJson())];
  List<TopupRefund> refunds = [];
  int writes = 0, topupReads = 0, refundReads = 0;
  Object? topupError, refundError, writeError;
  Future<List<RefundableTopup>>? nextTopups;
  Future<List<TopupRefund>>? nextRefunds;
  Future<TopupRefund>? nextWrite;
  final loadCursors = <String?>[];
  final requestCursors = <TopupRefund?>[];
  final dispatchedSessions = <Session>[];

  void register() {
    registerFallbackValue(refundSession());
    when(() => auth.currentSession).thenAnswer((_) => session);
    when(() => auth.getCurrentUserId).thenAnswer((_) => session?.user.id);
    when(() => auth.authStateChanges).thenAnswer((_) => changes.stream);
    when(
      () => wallet.listRefundableTopups(
        session: any(named: 'session'),
        beforeLoadId: any(named: 'beforeLoadId'),
      ),
    ).thenAnswer((call) async {
      topupReads++;
      loadCursors.add(call.namedArguments[#beforeLoadId] as String?);
      final pending = nextTopups;
      nextTopups = null;
      if (pending != null) return pending;
      if (topupError != null) throw topupError!;
      return topups;
    });
    when(
      () => wallet.listTopupRefunds(
        session: any(named: 'session'),
        before: any(named: 'before'),
      ),
    ).thenAnswer((call) async {
      refundReads++;
      requestCursors.add(call.namedArguments[#before] as TopupRefund?);
      final pending = nextRefunds;
      nextRefunds = null;
      if (pending != null) return pending;
      if (refundError != null) throw refundError!;
      return refunds;
    });
    when(
      () => wallet.requestTopupRefund(
        session: any(named: 'session'),
        loadId: any(named: 'loadId'),
      ),
    ).thenAnswer((call) async {
      writes++;
      dispatchedSessions.add(call.namedArguments[#session] as Session);
      if (nextWrite != null) return nextWrite!;
      if (writeError != null) throw writeError!;
      final result = TopupRefund.fromJson(
        refundJson(load: call.namedArguments[#loadId] as String),
      );
      refunds = [result];
      return result;
    });
    GetIt.I.registerSingleton<AuthService>(auth);
    GetIt.I.registerSingleton<WalletService>(wallet);
  }

  void change(Session? next) {
    session = next;
    changes.add(
      AuthState(
        next == null ? AuthChangeEvent.signedOut : AuthChangeEvent.signedIn,
        next,
      ),
    );
  }

  Future<void> dispose() async {
    await changes.close();
    await GetIt.I.reset();
  }
}
