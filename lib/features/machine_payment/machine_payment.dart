import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:flutter/material.dart';

import 'widgets/back_to_home.dart';

class MachinePayment extends StatelessWidget {
  final String machineId;

  const MachinePayment({super.key, required this.machineId});

  @override
  Widget build(BuildContext context) {
    return BasePage(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  'Payment link unavailable',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                const Text(
                  'If you already attempted a payment, contact Clean Stream '
                  'support before paying again. Its status cannot be confirmed here.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const BackToHome(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
