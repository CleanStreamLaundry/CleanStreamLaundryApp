import 'package:flutter/material.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/core/storage/storage_service.dart';

class ThemeManager with ChangeNotifier {
  ThemeData _themeData = lightMode;
  final StorageService storage;
  late final Future<void> initialized;

  ThemeManager({StorageService? storage}) : storage = storage ?? StorageService() {
    initialized = _initTheme();
  }

  ThemeData get themeData => _themeData;

  set themeData(ThemeData value) {
    _themeData = value;
    notifyListeners();
  }

  void toggleTheme() async {
    if (_themeData == lightMode) {
      themeData = darkMode;
      await storage.setValue("themeData", "darkMode");
    } else {
      themeData = lightMode;
      await storage.setValue("themeData", "lightMode");
    }
  }

  Future<void> _initTheme() async {
    try {
      await storage.init();
      final savedTheme = await storage.getValue("themeData");

      if (savedTheme == "darkMode") {
        _themeData = darkMode;
      } else {
        _themeData = lightMode;
      }
    } catch (_) {
      _themeData = lightMode;
    }

    notifyListeners();
  }
}
