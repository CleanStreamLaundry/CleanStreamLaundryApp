import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class TapToPayCard extends StatelessWidget {
  final VoidCallback? onTap;
  final double layoutScale;

  const TapToPayCard({super.key, this.onTap, this.layoutScale = 1});

  double _gap(double value) => value * layoutScale;

  double _size(double value) => value * layoutScale;

  double _font(double value) =>
      (value * layoutScale).clamp(value * 0.88, value * 1.03).toDouble();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cardColor = colors.brightness == Brightness.dark
        ? const Color(0xFF262626)
        : Colors.white;

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      child: Material(
        color: cardColor,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            constraints: BoxConstraints(minHeight: _size(84)),
            padding: EdgeInsets.symmetric(
              horizontal: _gap(15),
              vertical: _gap(10),
            ),
            decoration: BoxDecoration(
              border: Border.all(color: colors.primary.withValues(alpha: 0.72)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: _size(48),
                  height: _size(48),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.tap_and_play,
                    color: colors.primary,
                    size: _size(28),
                  ),
                ),
                SizedBox(width: _gap(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Tap to Pay',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colors.fontInverted,
                          fontSize: _font(20),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: _gap(3)),
                      Text(
                        'Use your mobile wallet at the reader.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.fontSecondary,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  SizedBox(width: _gap(8)),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.primary,
                    size: _size(26),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
