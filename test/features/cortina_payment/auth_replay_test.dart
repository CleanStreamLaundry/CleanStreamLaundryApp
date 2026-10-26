import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_cortina_vend_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Wallet extends Mock implements WalletService {}

void main() {
  late SupabaseClient client;
  late CortinaPaymentController subject;
  late _Wallet wallet;
  late List<String> requests;
  late String account;
  late int sessionNumber;
  Completer<void>? quoteHold;
  late Completer<void> quoteStarted;

  Map<String, Object> session() {
    String encode(Map<String, Object> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return {
      'access_token':
          '${encode({'alg': 'none', 'typ': 'JWT'})}.'
          '${encode({'sub': account, 'exp': 4102444800, 'session_id': '$sessionNumber'})}.fixture',
      'refresh_token': 'fixture-refresh-$sessionNumber',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': account,
        'aud': 'authenticated',
        'created_at': '',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'is_anonymous': false,
      },
    };
  }

  Future<void> signIn() async {
    await client.auth.signInWithPassword(
      email: '$account@fixture.invalid',
      password: 'synthetic-only',
    );
  }

  Future<void> drain() => Future<void>.delayed(Duration.zero);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    requests = [];
    account = 'customer';
    sessionNumber = 0;
    quoteHold = null;
    quoteStarted = Completer<void>();
    final transport = MockClient((request) async {
      expect(request.url.origin, 'https://fixture.invalid');
      requests.add(request.url.path);
      Object body;
      switch (request.url.path) {
        case '/auth/v1/token':
        case '/auth/v1/verify':
          sessionNumber++;
          body = session();
        case '/auth/v1/logout':
          return http.Response('', 204);
        case '/functions/v1/cortina-vend/quote':
          expect(jsonDecode(request.body), {'machineToken': 'washer-qr'});
          if (!quoteStarted.isCompleted) quoteStarted.complete();
          await quoteHold?.future;
          body = {
            'machineId': 1,
            'machineName': 'Washer 1',
            'machineType': 'washer',
            'washerSizeLabel': '12 kg',
            'amountCents': 400,
            'dryer': null,
          };
        default:
          throw StateError(
            'Unexpected HTTP or financial request: ${request.url.path}',
          );
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    client = SupabaseClient(
      'https://fixture.invalid',
      'sb_publishable_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: transport,
    );
    wallet = _Wallet();
    when(() => wallet.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'fixture-wallet',
        status: 'active',
        paidBalanceCents: 0,
        promoBalanceCents: 0,
        totalBalanceCents: 0,
      ),
    );
    subject = CortinaPaymentController(
      machineToken: 'washer-qr',
      terminalId: null,
      uniQr: null,
      vendService: SupabaseCortinaVendService(client: client),
      authService: SupabaseAuthService(client: client),
      walletService: wallet,
      pendingStore: CortinaPendingStore(project: 'https://fixture.invalid'),
      presentPaymentSheet: (_) async => fail('No payment sheet expected'),
    );
  });

  tearDown(() async {
    subject.dispose();
    expect(client.getChannels(), isEmpty);
    expect(client.realtime.isConnected, isFalse);
    await client.dispose();
  });

  test(
    'existing real-SDK sign-in replay permits the quote and retry',
    () async {
      await signIn();
      await subject.init();
      expect(subject.quote?.machineName, 'Washer 1');
      expect(subject.amountCents, 400);
      expect(subject.paymentLocked, isFalse);
      expect(subject.errorMessage, isNull);
      await subject.init();
      expect(subject.paymentLocked, isFalse);
      expect(requests.where((p) => p.endsWith('/quote')), hasLength(2));
    },
  );

  test('restored initial session permits the quote', () async {
    await client.auth.setInitialSession(jsonEncode(session()));
    await subject.init();
    expect(subject.quote?.machineName, 'Washer 1');
    expect(subject.paymentLocked, isFalse);
  });

  test('initial recovery replay still invalidates checkout', () async {
    await client.auth.verifyOTP(
      email: '$account@fixture.invalid',
      token: '123456',
      type: OtpType.recovery,
    );
    await subject.init();
    expect(subject.isCurrentScope, isFalse);
    expect(subject.quote, isNull);
    expect(subject.paymentLocked, isTrue);
    verifyNever(() => wallet.getBalance());
  });

  test(
    'first sign-in without a captured session invalidates checkout',
    () async {
      quoteHold = Completer<void>();
      final loading = subject.init();
      await quoteStarted.future;
      await signIn();
      await drain();
      quoteHold!.complete();
      await loading;
      expect(subject.isCurrentScope, isFalse);
      expect(subject.quote, isNull);
      expect(subject.paymentLocked, isTrue);
      verifyNever(() => wallet.getBalance());
    },
  );

  for (final transition in [
    'same-user',
    'same-token',
    'other-user',
    'sign-out',
    'recovery',
  ]) {
    test('$transition after replay invalidates the pending quote', () async {
      await signIn();
      quoteHold = Completer<void>();
      final loading = subject.init();
      await quoteStarted.future;
      await drain();
      if (transition == 'sign-out') {
        await client.auth.signOut();
      } else if (transition == 'recovery') {
        await client.auth.verifyOTP(
          email: '$account@fixture.invalid',
          token: '123456',
          type: OtpType.recovery,
        );
      } else {
        if (transition == 'other-user') account = 'different-customer';
        if (transition == 'same-token') sessionNumber--;
        await signIn();
      }
      await drain();
      quoteHold!.complete();
      await loading;
      expect(subject.isCurrentScope, isFalse);
      expect(subject.quote, isNull);
      expect(subject.paymentLocked, isTrue);
      final beforeRetry = requests.length;
      await subject.init();
      expect(requests, hasLength(beforeRetry));
      verifyNever(() => wallet.getBalance());
    });
  }
}
