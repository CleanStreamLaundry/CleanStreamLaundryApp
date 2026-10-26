import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class NotificationLead extends StatelessWidget {
  final int value;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const NotificationLead({
    super.key,
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlButton(
          icon: Icons.remove,
          tooltip: 'Decrease notification lead time',
          onPressed: onDecrement,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.fontSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ControlButton(
          icon: Icons.add,
          tooltip: 'Increase notification lead time',
          onPressed: onIncrement,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, color: Colors.white, size: 19),
        onPressed: onPressed,
      ),
    );
  }
}
