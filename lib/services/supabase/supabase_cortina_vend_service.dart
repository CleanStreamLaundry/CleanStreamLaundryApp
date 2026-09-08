import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseCortinaVendService implements CortinaVendService {
  final SupabaseClient client;

  SupabaseCortinaVendService({required this.client});

  Future<Map<String, dynamic>> _invoke(
    String route,
    Map<String, dynamic> body,
  ) async {
    late final FunctionResponse response;
    try {
      response = await client.functions.invoke(
        'cortina-vend/$route',
        body: body,
      );
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw StateError(details['error'] as String);
      }
      rethrow;
    }
    final data = response.data;
    if (data is! Map) {
      throw StateError('Cortina returned an invalid response');
    }
    final result = Map<String, dynamic>.from(data);
    if (result['error'] != null) {
      throw StateError(result['error'] as String);
    }
    return result;
  }

  Map<String, dynamic> _selector(
    String? machineToken,
    String? terminalId,
    String? uniQr,
  ) => {
    if (machineToken != null && machineToken.isNotEmpty)
      'machineToken': machineToken,
    if (terminalId != null && terminalId.isNotEmpty) 'terminalId': terminalId,
    if (uniQr != null && uniQr.isNotEmpty) 'uniQr': uniQr,
  };

  @override
  Future<CortinaQuote> quote({
    String? machineToken,
    String? terminalId,
    String? uniQr,
  }) async {
    final data = await _invoke(
      'quote',
      _selector(machineToken, terminalId, uniQr),
    );
    return CortinaQuote.fromJson(data);
  }

  @override
  Future<CortinaCardSession> createCardPayment({
    String? machineToken,
    String? terminalId,
    String? uniQr,
    required int amountCents,
    required String clientRequestId,
  }) async {
    final data = await _invoke('card', {
      ..._selector(machineToken, terminalId, uniQr),
      'amountCents': amountCents,
      'channel': 'app',
      'clientRequestId': clientRequestId,
    });
    return CortinaCardSession.fromJson(data);
  }

  @override
  Future<CortinaVendReference> payWithWallet({
    String? machineToken,
    String? terminalId,
    String? uniQr,
    required int amountCents,
    required String clientRequestId,
  }) async {
    final data = await _invoke('wallet', {
      ..._selector(machineToken, terminalId, uniQr),
      'amountCents': amountCents,
      'channel': 'app',
      'clientRequestId': clientRequestId,
    });
    return CortinaVendReference.fromJson(data);
  }

  @override
  Future<void> confirmCardPayment(CortinaVendReference reference) async {
    await _invoke('confirm', {
      'sessionId': reference.sessionId,
      'accessToken': reference.accessToken,
    });
  }

  @override
  Future<CortinaVendStatus> status(CortinaVendReference reference) async {
    final data = await _invoke('status', {
      'sessionId': reference.sessionId,
      'accessToken': reference.accessToken,
    });
    return CortinaVendStatus.fromJson(data);
  }
}
