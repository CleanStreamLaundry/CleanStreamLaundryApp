import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';

abstract class CortinaVendService {
  Future<CortinaQuote> quote({
    String? machineToken,
    String? terminalId,
    String? uniQr,
  });

  Future<CortinaCardSession> createCardPayment({
    String? machineToken,
    String? terminalId,
    String? uniQr,
    required int amountCents,
    required String clientRequestId,
  });

  Future<CortinaVendReference> payWithWallet({
    String? machineToken,
    String? terminalId,
    String? uniQr,
    required int amountCents,
    required String clientRequestId,
  });

  Future<void> confirmCardPayment(CortinaVendReference reference);

  Future<CortinaVendStatus> status(CortinaVendReference reference);
}
