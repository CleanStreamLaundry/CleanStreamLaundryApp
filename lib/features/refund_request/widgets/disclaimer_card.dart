import 'package:flutter/material.dart';

class DisclaimerCard extends StatelessWidget {
  const DisclaimerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.secondary, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: colors.onSurface),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Report a machine failure while you are at the location and on '
              'the same local calendar day. For an approved claim, we arrange '
              'an available replacement machine for the same amount, or credit '
              'your wallet if you already completed a replacement load. '
              'We email you when the issue is resolved. Payment errors and '
              'rights required by law are reviewed separately.',
              style: TextStyle(
                letterSpacing: 0,
                fontSize: 12,
                color: colors.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
