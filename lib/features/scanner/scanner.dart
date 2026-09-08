import 'controller.dart';
import 'widgets/scanner_overlay.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:clean_stream_laundry_app/features/widgets/status_dialog_box.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  late final ScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScannerController();
  }

  @override
  void dispose() {
    _controller.disposeController();
    _controller.dispose();
    super.dispose();
  }

  Future<void> processNayaxCode(String? code) => _controller.processNayaxCode(
    code,
    onNavigate: (route) {
      if (mounted) context.go(route);
    },
    onError: (title, message) {
      if (mounted) {
        statusDialog(context, title: title, message: message, isSuccess: false);
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    return BasePage(
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final scanWindow = Rect.fromCenter(
                center: constraints.biggest.center(Offset.zero),
                width: 250,
                height: 250,
              );
              return MobileScanner(
                controller: _controller.cameraController,
                scanWindow: scanWindow,
                tapToFocus: true,
                onDetect: (capture) => _controller.handleQRCode(
                  capture,
                  onNavigate: (route) {
                    if (mounted) context.go(route);
                  },
                  onError: (title, message) async {
                    if (mounted) {
                      await statusDialog(
                        context,
                        title: title,
                        message: message,
                        isSuccess: false,
                      );
                    }
                  },
                ),
              );
            },
          ),
          ScannerOverlay(onCancel: () => context.go('/startPage')),
        ],
      ),
    );
  }
}
