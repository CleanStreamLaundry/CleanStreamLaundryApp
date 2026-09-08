import 'package:clean_stream_laundry_app/features/scanner/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockMachineCommunicationService mockMachineCommunicator;

  setUp(() {
    mockMachineCommunicator = MockMachineCommunicationService();
  });

  ScannerController buildController() =>
      ScannerController(machineCommunicator: mockMachineCommunicator);

  group('processNayaxCode', () {
    test('calls checkAvailability with the provided code', () async {
      when(
        () => mockMachineCommunicator.checkAvailability(any()),
      ).thenAnswer((_) async => 'pass');

      final controller = buildController();
      await controller.processNayaxCode(
        'machine123',
        onNavigate: (_) {},
        onError: (_, __) {},
      );

      verify(
        () => mockMachineCommunicator.checkAvailability('machine123'),
      ).called(1);

      controller.disposeController();
    });

    test('calls onNavigate with correct route when result is pass', () async {
      when(
        () => mockMachineCommunicator.checkAvailability(any()),
      ).thenAnswer((_) async => 'pass');

      String? navigatedRoute;
      final controller = buildController();
      await controller.processNayaxCode(
        'machine123',
        onNavigate: (route) => navigatedRoute = route,
        onError: (_, __) {},
      );

      expect(navigatedRoute, '/paymentPage?machineId=machine123');
      controller.disposeController();
    });

    test('calls onError with correct title when result is not pass', () async {
      when(
        () => mockMachineCommunicator.checkAvailability(any()),
      ).thenAnswer((_) async => 'fail');

      String? errorTitle;
      String? errorMessage;
      final controller = buildController();
      await controller.processNayaxCode(
        'machine123',
        onNavigate: (_) {},
        onError: (title, message) {
          errorTitle = title;
          errorMessage = message;
        },
      );

      expect(errorTitle, 'Machine Unavailable');
      expect(errorMessage, 'fail');
      controller.disposeController();
    });

    test('does not call onNavigate when result is not pass', () async {
      when(
        () => mockMachineCommunicator.checkAvailability(any()),
      ).thenAnswer((_) async => 'fail');

      var navigateCalled = false;
      final controller = buildController();
      await controller.processNayaxCode(
        'machine123',
        onNavigate: (_) => navigateCalled = true,
        onError: (_, __) {},
      );

      expect(navigateCalled, isFalse);
      controller.disposeController();
    });

    test('does not call onError when result is pass', () async {
      when(
        () => mockMachineCommunicator.checkAvailability(any()),
      ).thenAnswer((_) async => 'pass');

      var errorCalled = false;
      final controller = buildController();
      await controller.processNayaxCode(
        'machine123',
        onNavigate: (_) {},
        onError: (_, __) => errorCalled = true,
      );

      expect(errorCalled, isFalse);
      controller.disposeController();
    });
  });

  group('Lifecycle', () {
    test('disposeController disposes camera without error', () {
      final controller = buildController();
      expect(() => controller.disposeController(), returnsNormally);
    });

    test('cameraController is not null after construction', () {
      final controller = buildController();
      expect(controller.cameraController, isNotNull);
      expect(
        controller.cameraController.cameraResolution,
        const Size(1280, 720),
      );
      expect(controller.cameraController.autoZoom, isFalse);
      expect(controller.cameraController.formats, const [BarcodeFormat.qrCode]);
      controller.disposeController();
    });
  });
}
