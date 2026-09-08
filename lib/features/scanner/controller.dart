import 'package:clean_stream_laundry_app/logic/parsing/qr_parser.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_communication_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerController extends ChangeNotifier {
  final MachineCommunicationService machineCommunicator;

  ScannerController({MachineCommunicationService? machineCommunicator})
    : machineCommunicator =
          machineCommunicator ?? GetIt.instance<MachineCommunicationService>();

  final MobileScannerController cameraController = MobileScannerController(
    cameraResolution: const Size(1280, 720),
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 500,
    formats: const [BarcodeFormat.qrCode],
  );

  String? scannedCode;
  bool _isHandlingCode = false;

  void disposeController() {
    cameraController.dispose();
  }

  Future<void> handleQRCode(
    BarcodeCapture capture, {
    required void Function(String route) onNavigate,
    required Future<void> Function(String title, String message) onError,
  }) async {
    if (_isHandlingCode) return;

    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        _isHandlingCode = true;
        scannedCode = barcode.rawValue;
        notifyListeners();
        final parser = QrScannerParser(scannedCode!);
        final machineToken = parser.getMachineToken();
        final terminalId = parser.getNayaxTerminalId();
        final uniQr = parser.getNayaxUniQr();
        try {
          if (machineToken != null && machineToken.isNotEmpty) {
            debugPrint('Scanner detected a Clean Stream machine QR code.');
            await cameraController.stop();
            onNavigate(
              '/pay?machine=${Uri.encodeQueryComponent(machineToken)}',
            );
          } else if (terminalId != null) {
            debugPrint('Scanner detected a Nayax terminal QR code.');
            await cameraController.stop();
            onNavigate('/pay?terminal=${Uri.encodeQueryComponent(terminalId)}');
          } else if (uniQr != null) {
            debugPrint('Scanner detected a Nayax UniQR code.');
            await cameraController.stop();
            onNavigate('/pay?uniqr=${Uri.encodeQueryComponent(uniQr)}');
          } else {
            debugPrint('Scanner rejected an unsupported QR code.');
            await onError(
              'Invalid QR Code',
              'Scan the Clean Stream QR on the machine.',
            );
          }
        } finally {
          _isHandlingCode = false;
        }
        break;
      }
    }
  }

  Future<void> processNayaxCode(
    String? code, {
    required void Function(String route) onNavigate,
    required void Function(String title, String message) onError,
  }) async {
    cameraController.stop();
    final result = await machineCommunicator.checkAvailability(code!);
    if (result == 'pass') {
      onNavigate('/paymentPage?machineId=$code');
    } else {
      onError('Machine Unavailable', result);
      cameraController.start();
    }
  }
}
