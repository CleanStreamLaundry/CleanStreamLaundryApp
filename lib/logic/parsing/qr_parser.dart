class QrScannerParser {
  Uri? _uri;
  String? _nayaxID;
  String? _nayaxTerminalId;
  String? _machineToken;
  String? _nayaxUniQr;

  QrScannerParser(String url) {
    try {
      final value = url.trim();
      if (RegExp(r'^\d{16}$').hasMatch(value)) {
        _nayaxTerminalId = value;
      }
      _uri = Uri.parse(value);
      _parseUrl();
    } catch (e) {
      _uri = null;
      _nayaxID = null;
    }
  }

  void _parseUrl() {
    _nayaxID = _uri?.queryParameters['id'];
    _machineToken = _uri?.queryParameters['machine'];
    final host = _uri?.host.toLowerCase() ?? '';
    if (host == 'qr.nayax.com' || host.endsWith('.nayax.com')) {
      _nayaxUniQr = _uri.toString();
    }
  }

  String? getNayaxDeviceID() {
    return _nayaxID;
  }

  String? getMachineToken() => _machineToken;

  String? getNayaxTerminalId() => _nayaxTerminalId;

  String? getNayaxUniQr() => _nayaxUniQr;
}
