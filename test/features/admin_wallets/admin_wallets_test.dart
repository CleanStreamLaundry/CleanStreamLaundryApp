import 'dart:async';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/admin_wallets/admin_wallets.dart';
import 'package:clean_stream_laundry_app/logic/services/admin_wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../topup_refunds/fixtures.dart';

const _walletId = '33333333-3333-4333-8333-333333333333';
const _balance = <String, dynamic>{
  'wallet_account_id': _walletId,
  'user_id': customerB,
  'status': 'active',
  'paid_balance_cents': 12345,
  'promo_balance_cents': 500,
  'total_balance_cents': 12845,
};
Map<String, dynamic> _detail() => {
  'balance': _balance, 'loads': [], 'redemptions': [], 'ledger': [],
};

class _ExpiringSession extends Mock implements Session {}

class _Wallet implements AdminWalletService {
  final Session? Function() currentSession;
  _Wallet(this.currentSession);
  int searches = 0, details = 0;
  final writes = <Map<String, dynamic>>[];
  final callers = <Session?>[];
  Future<List<Map<String, dynamic>>>? pendingSearch;
  Future<Map<String, dynamic>>? pendingDetail;
  Future<void>? pendingWrite;
  Object? writeError;

  @override
  Future<List<Map<String, dynamic>>> searchWallets(String query) async {
    searches++;
    final pending = pendingSearch;
    if (pending != null) return pending;
    return [_balance];
  }

  @override
  Future<Map<String, dynamic>> getWalletDetail(String walletAccountId) async {
    details++;
    expect(walletAccountId, _walletId);
    final pending = pendingDetail;
    if (pending != null) return pending;
    return _detail();
  }

  Future<void> _write(Map<String, dynamic> value) async {
    writes.add(value);
    callers.add(currentSession());
    if (writeError != null) throw writeError!;
    if (pendingWrite != null) await pendingWrite;
  }

  @override
  Future<void> adjustWallet({required String walletAccountId,
    required int amountCents, required int paidAmountCents,
    required int promoAmountCents, required String note}) => _write({
    'kind': 'adjust', 'id': walletAccountId, 'amount': amountCents,
    'paid': paidAmountCents, 'promo': promoAmountCents, 'note': note,
  });

  @override
  Future<void> lockWallet(String walletAccountId, bool locked) => _write({
    'kind': 'lock', 'id': walletAccountId, 'locked': locked,
  });

  @override
  Future<void> recordCashRedemptionOrStripeRefund({required String walletAccountId,
    required int amountCents, required String note}) => _write({
    'kind': 'cash', 'id': walletAccountId, 'amount': amountCents, 'note': note,
  });

  @override
  Future<void> recordDeletedAccountComplaint({required String walletAccountId,
    required String note, String resolution = 'denied'}) => _write({
    'kind': 'complaint', 'id': walletAccountId, 'note': note, 'resolution': resolution,
  });
}

void main() {
  late RefundAuth auth;
  late _Wallet wallet;
  late StreamController<AuthState> changes;
  late ValueNotifier<bool> pageVisible;
  Session? session;
  GoRouter? router;

  setUp(() {
    session = refundSession();
    pageVisible = ValueNotifier(true);
    auth = RefundAuth();
    changes = StreamController<AuthState>.broadcast(sync: true);
    when(() => auth.currentSession).thenAnswer((_) => session);
    when(() => auth.getCurrentUserId).thenAnswer((_) => session?.user.id);
    when(() => auth.authStateChanges).thenAnswer((_) => changes.stream);
    wallet = _Wallet(() => session);
    GetIt.I.registerSingleton<AuthService>(auth);
    GetIt.I.registerSingleton<AdminWalletService>(wallet);
  });
  tearDown(() async {
    router?.dispose();
    router = null;
    pageVisible.dispose();
    await changes.close();
    await GetIt.I.reset();
  });

  void change(Session? next) {
    session = next;
    changes.add(AuthState(next == null ? AuthChangeEvent.signedOut : AuthChangeEvent.signedIn, next));
  }

  Future<void> show(WidgetTester tester, {bool select = true}) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(initialLocation: '/adminWallets', routes: [
      GoRoute(path: '/adminWallets', builder: (_, _) => ValueListenableBuilder<bool>(
        valueListenable: pageVisible,
        builder: (_, visible, _) => visible ? const AdminWalletsPage() : const SizedBox.shrink(),
      )),
      GoRoute(path: '/gone', builder: (_, _) => const Scaffold(body: Text('Gone'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(theme: lightMode, routerConfig: router));
    // Bounded pumps also support an intentionally unresolved initial read.
    await tester.pump();
    if (select) {
      await tester.tap(find.text(_walletId));
      await tester.pumpAndSettle();
    }
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> openMoney(WidgetTester tester, String action) async {
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(field('Amount'), '12.34');
    await tester.enterText(field('Required note'), '  reviewed note  ');
  }

  for (final action in ['Adjust', 'Cash/Refund']) {
    testWidgets('$action delayed modal preserves caller target cents and workflow', (tester) async {
      final original = session;
      await show(tester);
      await openMoney(tester, action);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(wallet.writes, [
        {'kind': action == 'Adjust' ? 'adjust' : 'cash', 'id': _walletId,
          'amount': 1234, if (action == 'Adjust') 'paid': 0,
          if (action == 'Adjust') 'promo': 1234, 'note': 'reviewed note'},
      ]);
      expect(wallet.callers.single, same(original));
      expect(wallet.details, 2);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('$action cancel leaves money untouched', (tester) async {
      await show(tester);
      await openMoney(tester, action);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(wallet.writes, isEmpty);
      expect(wallet.details, 1);
    });

    for (final switchKind in ['A-B', 'A-B-A', 'signout']) {
      testWidgets('$action modal cannot dispatch after $switchKind', (tester) async {
        final original = session;
        await show(tester);
        await openMoney(tester, action);
        change(switchKind == 'signout' ? null : refundSession(id: customerB));
        if (switchKind == 'A-B-A') change(original);
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(wallet.writes, isEmpty);
        expect(wallet.searches, 1);
        expect(wallet.details, 1);
        expect(find.text(_walletId), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('modal rechecks current identity even before Auth event arrives', (tester) async {
    await show(tester);
    await openMoney(tester, 'Adjust');
    session = refundSession(id: customerB);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(wallet.writes, isEmpty);
    expect(wallet.details, 1);
  });

  testWidgets('modal rejects expired caller without a write', (tester) async {
    final original = session!;
    final expiring = _ExpiringSession();
    var expired = false;
    when(() => expiring.user).thenReturn(original.user);
    when(() => expiring.accessToken).thenReturn(original.accessToken);
    when(() => expiring.expiresAt).thenReturn(original.expiresAt);
    when(() => expiring.isExpired).thenAnswer((_) => expired);
    session = expiring;
    await show(tester);
    await openMoney(tester, 'Adjust');
    // Same identity/object; only token validity changes across the dialog.
    expired = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(wallet.writes, isEmpty);
  });

  testWidgets('unmounted page cannot dispatch a delayed modal result', (tester) async {
    await show(tester);
    await openMoney(tester, 'Adjust');
    pageVisible.value = false;
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(wallet.writes, isEmpty);
    expect(wallet.details, 1);
    expect(changes.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['Adjust', 'Cash/Refund', 'Lock', 'Record Complaint']) {
    testWidgets('$action late write completion cannot refresh a replacement caller', (tester) async {
      final pending = Completer<void>();
      wallet.pendingWrite = pending.future;
      await show(tester);
      if (action == 'Adjust' || action == 'Cash/Refund') {
        await openMoney(tester, action);
        await tester.tap(find.text('Save'));
      } else {
        if (action == 'Record Complaint') {
          await tester.enterText(field('Deleted-account complaint note'), 'reviewed complaint');
        }
        await tester.tap(find.text(action));
      }
      await tester.pumpAndSettle();
      expect(wallet.writes, hasLength(1));
      change(refundSession(id: customerB));
      pending.complete();
      await tester.pumpAndSettle();
      expect(wallet.writes, hasLength(1));
      expect(wallet.searches, 1);
      expect(wallet.details, 1);
      expect(find.text(_walletId), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('same caller lock and complaint retain parameters and followup reads', (tester) async {
    final original = session;
    await show(tester);
    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Deleted-account complaint note'), '  reviewed complaint  ');
    await tester.tap(find.text('Record Complaint'));
    await tester.pumpAndSettle();
    expect(wallet.writes, [
      {'kind': 'lock', 'id': _walletId, 'locked': true},
      {'kind': 'lock', 'id': _walletId, 'locked': false},
      {'kind': 'complaint', 'id': _walletId, 'note': 'reviewed complaint', 'resolution': 'denied'},
    ]);
    expect(wallet.callers, everyElement(same(original)));
    expect(wallet.searches, 3);
    expect(wallet.details, 4);
    expect(tester.widget<TextField>(field('Deleted-account complaint note')).controller!.text, isEmpty);
  });

  testWidgets('late initial search cannot expose previous caller rows', (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    wallet.pendingSearch = pending.future;
    await show(tester, select: false);
    change(refundSession(id: customerB));
    pending.complete([_balance]);
    await tester.pumpAndSettle();
    expect(find.text(_walletId), findsNothing);
    expect(wallet.details, 0);
  });

  testWidgets('late detail cannot restore controls after A-B-A', (tester) async {
    final original = session;
    final pending = Completer<Map<String, dynamic>>();
    wallet.pendingDetail = pending.future;
    await show(tester);
    change(refundSession(id: customerB));
    change(original);
    pending.complete(_detail());
    await tester.pumpAndSettle();
    expect(find.text('Adjust'), findsNothing);
    expect(wallet.writes, isEmpty);
  });

  for (final invalid in ['missing', 'expired']) {
    testWidgets('$invalid initial caller has no reads or controls', (tester) async {
      session = invalid == 'missing' ? null : refundSession(seconds: -60);
      await show(tester, select: false);
      await tester.pumpAndSettle();
      expect(wallet.searches, 0);
      expect(wallet.details, 0);
      expect(find.text('Adjust'), findsNothing);
      expect(find.text('Current wallet owner session required.'), findsOneWidget);
    });
  }

  testWidgets('uncertain write error remains visible without replay or success', (tester) async {
    wallet.writeError = TimeoutException('Wallet request timed out');
    await show(tester);
    await openMoney(tester, 'Adjust');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(wallet.writes, hasLength(1));
    expect(wallet.details, 1);
    expect(find.textContaining('Wallet request timed out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
