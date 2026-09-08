import 'package:flutter/material.dart';

class ScannerOverlay extends StatelessWidget {
  final VoidCallback onCancel;

  const ScannerOverlay({super.key, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.all(16),
            child: const Text(
              'Center the machine QR code',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),

        // Cancel button
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton.extended(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
              backgroundColor: Colors.red,
            ),
          ),
        ),

        // Center scanning frame
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}
