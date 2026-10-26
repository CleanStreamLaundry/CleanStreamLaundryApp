import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CortinaPendingPayment {
  final String requestId;
  final String method;
  final int amountCents;
  final CortinaVendReference? reference;

  const CortinaPendingPayment({
    required this.requestId,
    required this.method,
    required this.amountCents,
    this.reference,
  });

  Map<String, Object?> toJson() => {
    'version': 1,
    'requestId': requestId,
    'method': method,
    'amountCents': amountCents,
    'sessionId': reference?.sessionId,
    'accessToken': reference?.accessToken,
  };

  factory CortinaPendingPayment.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['requestId'] is! String ||
        (value['requestId'] as String).isEmpty ||
        !const {'card', 'wallet'}.contains(value['method']) ||
        value['amountCents'] is! int ||
        (value['amountCents'] as int) <= 0) {
      throw const FormatException('Invalid pending payment');
    }
    final sessionId = value['sessionId'];
    final accessToken = value['accessToken'];
    if ((sessionId != null || accessToken != null) &&
        (sessionId is! String || sessionId.isEmpty ||
            accessToken is! String || accessToken.isEmpty)) {
      throw const FormatException('Invalid pending reference');
    }
    return CortinaPendingPayment(
      requestId: value['requestId'] as String,
      method: value['method'] as String,
      amountCents: value['amountCents'] as int,
      reference: sessionId == null ? null : CortinaVendReference(
        sessionId: sessionId as String,
        accessToken: accessToken as String,
      ),
    );
  }
}

// Local recovery only. Server idempotency remains authoritative across devices.
// References/request IDs are capabilities: never log or export their values.
class CortinaPendingStore {
  final String project;
  final FlutterSecureStorage _storage;
  static Future<void>? _writes;

  CortinaPendingStore({
    required this.project,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage(
         aOptions: AndroidOptions(resetOnError: false),
         iOptions: IOSOptions(
           accessibility: KeychainAccessibility.unlocked_this_device,
         ),
       ) {
    if (project.trim().isEmpty) throw ArgumentError('Missing payment project');
  }

  String scope({required String? accountId, required int machineId}) {
    if (machineId <= 0) throw ArgumentError('Invalid payment machine');
    return 'cortina.pending.v1.${Uri.encodeComponent(jsonEncode([
      project, accountId, machineId,
    ]))}';
  }

  Future<T> _serialized<T>(Future<T> Function(FlutterSecureStorage) action) async {
    final previous = _writes;
    final done = Completer<void>();
    _writes = done.future;
    if (previous != null) await previous;
    try {
      return await action(_storage);
    } finally {
      // An idle queue must not retain a completed future's originating zone.
      if (identical(_writes, done.future)) _writes = null;
      done.complete();
    }
  }

  Future<CortinaPendingPayment?> _read(FlutterSecureStorage storage, String scope) async {
    final raw = await storage.read(key: scope);
    return raw == null ? null : CortinaPendingPayment.fromJson(jsonDecode(raw));
  }

  Future<CortinaPendingPayment?> read(String scope) =>
      _serialized((storage) async => _read(storage, scope));

  Future<void> claim(String scope, CortinaPendingPayment payment) =>
      _serialized((storage) async {
        if (await _read(storage, scope) != null) {
          throw StateError('A payment is already pending');
        }
        await _write(storage, scope, payment);
      });

  Future<void> attach(
    String scope,
    String requestId,
    CortinaVendReference reference,
  ) => _serialized((storage) async {
    final current = await _read(storage, scope);
    if (current == null || current.requestId != requestId ||
        (current.reference != null &&
            (current.reference!.sessionId != reference.sessionId ||
                current.reference!.accessToken != reference.accessToken))) {
      throw StateError('Pending payment changed');
    }
    await _write(storage, scope, CortinaPendingPayment(
      requestId: current.requestId,
      method: current.method,
      amountCents: current.amountCents,
      reference: reference,
    ));
  });

  Future<void> clear(String scope, String requestId) =>
      _serialized((storage) async {
        final current = await _read(storage, scope);
        if (current == null || current.requestId != requestId) {
          throw StateError('Pending payment changed');
        }
        await storage.delete(key: scope);
        if (await storage.read(key: scope) != null) {
          throw StateError('Could not clear pending payment');
        }
      });

  Future<void> _write(
    FlutterSecureStorage storage,
    String scope,
    CortinaPendingPayment payment,
  ) async {
    // Validate writes too; malformed references must leave the claim intact.
    CortinaPendingPayment.fromJson(payment.toJson());
    final encoded = jsonEncode(payment.toJson());
    await storage.write(key: scope, value: encoded);
    if (await storage.read(key: scope) != encoded) {
      throw StateError('Could not save pending payment');
    }
  }
}
