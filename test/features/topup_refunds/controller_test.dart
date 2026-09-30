import 'dart:async';

import 'package:clean_stream_laundry_app/features/topup_refunds/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures.dart';

void main() {
  late RefundHarness h;
  late TopupRefundsController c;
  setUp(() {
    h = RefundHarness()..register();
    c = TopupRefundsController();
  });
  tearDown(() async {
    c.dispose();
    await h.dispose();
  });

  test('loads both lists through existing WalletService', () async {
    await c.initialize();
    expect(c.topups.single.loadId, '9007199254740993');
    expect(c.refunds, isEmpty);
    expect(c.canRequest(c.topups.single, c.generation), isTrue);
    expect(h.topupReads, 1);
    expect(h.refundReads, 1);
  });
  test('preserves content and disables mutation on refresh errors', () async {
    h.refunds = [TopupRefund.fromJson(refundJson(load: '4'))];
    await c.initialize();
    h.topupError = h.refundError = StateError('offline');
    await c.refresh();
    expect(c.topups, hasLength(1));
    expect(c.refunds, hasLength(1));
    expect(c.topupsError, contains('out of date'));
    expect(c.refundsError, contains('out of date'));
    expect(c.canRequest(c.topups.single, c.generation), isFalse);
  });
  test('both independent keyset cursors and exact 100-row boundary', () async {
    h.topups = List.generate(
      100,
      (i) => RefundableTopup.fromJson(topupJson(load: '${200 - i}')),
    );
    h.refunds = List.generate(
      100,
      (i) => TopupRefund.fromJson(
        refundJson(
          load: '${200 - i}',
          id: '33333333-3333-3333-3333-${(200 - i).toString().padLeft(12, '0')}',
        ),
      ),
    );
    await c.initialize();
    expect(c.moreTopups && c.moreRefunds, isTrue);
    final cursor = c.refunds.last;
    h.topups = [RefundableTopup.fromJson(topupJson(load: '100'))];
    h.refunds = [];
    await c.loadMoreTopups();
    await c.loadMoreRefunds();
    expect(h.loadCursors.last, '101');
    expect(h.requestCursors.last, same(cursor));
    expect(c.topups, hasLength(101));
    expect(c.refunds, hasLength(100));
    expect(c.moreTopups || c.moreRefunds, isFalse);
  });
  test('failed pagination preserves cursor for explicit read retry', () async {
    h.topups = List.generate(
      100,
      (i) => RefundableTopup.fromJson(topupJson(load: '${200 - i}')),
    );
    await c.initialize();
    h.topupError = StateError('offline');
    await c.loadMoreTopups();
    expect(c.topups, hasLength(100));
    expect(c.moreTopups, isTrue);
    h.topupError = null;
    h.topups = [];
    await c.loadMoreTopups();
    expect(h.loadCursors, [null, '101', '101']);
  });
  test('double click captures one actor and writes once, then lists', () async {
    await c.initialize();
    final gate = Completer<TopupRefund>();
    h.nextWrite = gate.future;
    final row = c.topups.single;
    final epoch = c.generation;
    final first = c.request(row, expectedGeneration: epoch);
    await c.request(row, expectedGeneration: epoch);
    expect(h.writes, 1);
    expect(c.writing, isTrue);
    expect(h.dispatchedSessions.single, same(h.session));
    gate.complete(TopupRefund.fromJson(refundJson()));
    await first;
    expect(h.topupReads, 2);
    expect(h.refundReads, 2);
    expect(c.message, contains('not confirmation of repayment'));
  });
  test(
    'uncertain request reconciles lists and cannot blindly replay',
    () async {
      await c.initialize();
      h.writeError = TimeoutException('synthetic');
      await c.request(c.topups.single, expectedGeneration: c.generation);
      expect(c.message, contains('not yet confirmed'));
      expect(h.topupReads, 2);
      expect(h.refundReads, 2);
      expect(c.isUncertain(c.topups.single.loadId), isTrue);
      await c.request(c.topups.single, expectedGeneration: c.generation);
      expect(h.writes, 1);
      h.refunds = [TopupRefund.fromJson(refundJson())];
      await c.refresh();
      expect(c.isUncertain(c.topups.single.loadId), isFalse);
      expect(c.canRequest(c.topups.single, c.generation), isFalse);
    },
  );
  test(
    'uncertain read failure retains cached content and blocked load',
    () async {
      await c.initialize();
      h.writeError = h.topupError = h.refundError = StateError('offline');
      await c.request(c.topups.single, expectedGeneration: c.generation);
      expect(c.topups, hasLength(1));
      expect(c.isUncertain(c.topups.single.loadId), isTrue);
      expect(c.writing, isFalse);
    },
  );
  for (final code in ['PT401', 'PT403', 'PT404', 'PT409']) {
    test(
      'sanitized server rejection $code still refreshes eligibility',
      () async {
        await c.initialize();
        h.writeError = PostgrestException(
          message: 'private synthetic detail',
          code: code,
        );
        await c.request(c.topups.single, expectedGeneration: c.generation);
        expect(c.message, isNot(contains('private synthetic detail')));
        expect(h.writes, 1);
        expect(h.topupReads, 2);
      },
    );
  }
  test('A-B-A invalidates old confirmation before dispatch', () async {
    await c.initialize();
    final old = c.topups.single;
    final epoch = c.generation;
    final a = h.session;
    h.change(refundSession(id: customerB));
    h.change(a);
    await c.request(old, expectedGeneration: epoch);
    expect(h.writes, 0);
  });
  test('A-B-A suppresses late request effects and reconciliation', () async {
    await c.initialize();
    final gate = Completer<TopupRefund>();
    h.nextWrite = gate.future;
    final pending = c.request(
      c.topups.single,
      expectedGeneration: c.generation,
    );
    final a = h.session;
    h.change(refundSession(id: customerB));
    h.change(a);
    await Future<void>.delayed(Duration.zero);
    final reads = h.topupReads;
    gate.complete(TopupRefund.fromJson(refundJson()));
    await pending;
    expect(c.message, isNull);
    expect(c.refunds, isEmpty);
    expect(h.topupReads, reads);
  });
  test('late list never restores prior user content', () async {
    final gate = Completer<List<RefundableTopup>>();
    h.nextTopups = gate.future;
    final pending = c.initialize();
    h.topups = [];
    h.change(refundSession(id: customerB));
    gate.complete([RefundableTopup.fromJson(topupJson())]);
    await pending;
    expect(c.topups, isEmpty);
  });
  test(
    'deactivation invalidates confirmation and suppresses late failure',
    () async {
      await c.initialize();
      final gate = Completer<TopupRefund>();
      h.nextWrite = gate.future;
      final pending = c.request(
        c.topups.single,
        expectedGeneration: c.generation,
      );
      c.setActive(false);
      gate.completeError(StateError('late'));
      await pending;
      expect(c.message, isNull);
      expect(c.topups, isEmpty);
      expect(h.topupReads, 1);
    },
  );
  test('expired session cannot read or write', () async {
    h.session = refundSession(seconds: -1);
    await c.initialize();
    expect(h.topupReads, 0);
    expect(h.refundReads, 0);
    expect(h.writes, 0);
    expect(c.message, contains('signed-in'));
  });

  test(
    'mismatched full-principal acknowledgement stays uncertain, lists only',
    () async {
      await c.initialize();
      h.nextWrite = Future.value(
        TopupRefund.fromJson(refundJson()..['principal_cents'] = 1000),
      );
      await c.request(c.topups.single, expectedGeneration: c.generation);
      expect(c.message, contains('not yet confirmed'));
      expect(c.refunds, isEmpty);
      expect(c.isUncertain(c.topups.single.loadId), isTrue);
      expect(h.writes, 1);
      expect(h.topupReads, 2);
    },
  );

  test(
    'late failure after A-B-A cannot overwrite current account message',
    () async {
      await c.initialize();
      final gate = Completer<TopupRefund>();
      h.nextWrite = gate.future;
      final pending = c.request(
        c.topups.single,
        expectedGeneration: c.generation,
      );
      final a = h.session;
      h.change(refundSession(id: customerB));
      h.change(a);
      await Future<void>.delayed(Duration.zero);
      gate.completeError(StateError('late private failure'));
      await pending;
      expect(c.message, isNull);
      expect(c.writing, isFalse);
    },
  );
}
