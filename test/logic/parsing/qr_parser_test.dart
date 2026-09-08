import 'package:test/test.dart';
import 'package:clean_stream_laundry_app/logic/parsing/qr_parser.dart';

void main() {
  group("qr_scanner.parseURL", () {
    test("Returns the valid NayaxDeviceID", () {
      QrScannerParser qrScannerController = QrScannerParser(
        "https://payment.nayax.com/device?id=12345678",
      );
      expect(qrScannerController.getNayaxDeviceID(), equals("12345678"));
    });

    test("Returns null if the URL is invalid", () {
      QrScannerParser qrScannerController = QrScannerParser(
        "https://payment.nayax.com/",
      );
      expect(qrScannerController.getNayaxDeviceID(), isNull);
    });

    test("Returns null if the URL is malformed", () {
      QrScannerParser qrScannerController = QrScannerParser(
        "ht!tp://malformed-url",
      );
      expect(qrScannerController.getNayaxDeviceID(), isNull);
    });

    test("extracts a Clean Stream public machine token", () {
      final parser = QrScannerParser(
        "https://cleanstreamlaundry.com/pay?machine=public-token-123",
      );
      expect(parser.getMachineToken(), "public-token-123");
      expect(parser.getNayaxUniQr(), isNull);
    });

    test("preserves a Nayax UniQR for server-side lookup", () {
      const uniQr = "https://qr.nayax.com/v1/device-token?id=uniqr-42";
      final parser = QrScannerParser(uniQr);
      expect(parser.getNayaxUniQr(), uniQr);
      expect(parser.getMachineToken(), isNull);
    });

    test("extracts a 16-digit Nayax terminal QR", () {
      final parser = QrScannerParser("4434331126150568");
      expect(parser.getNayaxTerminalId(), "4434331126150568");
      expect(parser.getMachineToken(), isNull);
      expect(parser.getNayaxUniQr(), isNull);
    });

    test("rejects an incomplete numeric terminal QR", () {
      final parser = QrScannerParser("150568");
      expect(parser.getNayaxTerminalId(), isNull);
    });
  });
}
