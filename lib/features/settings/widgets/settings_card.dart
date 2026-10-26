import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double? trailingWidth;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool isDestructive;
  final bool showDivider;

  const SettingsCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingWidth,
    this.onTap,
    this.showChevron = false,
    this.isDestructive = false,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final textColor = isDestructive
        ? (isDark ? colorScheme.fontInverted : Colors.red.shade700)
        : colorScheme.fontSecondary;
    final iconColor = isDestructive ? Colors.red.shade700 : colorScheme.primary;
    final dividerColor = colorScheme.outlineVariant.withValues(alpha: 0.24);
    final effectiveTrailing =
        trailing ??
        (showChevron
            ? Icon(
                Icons.chevron_right,
                color: colorScheme.fontSecondary.withValues(alpha: 0.45),
                size: 22,
              )
            : null);
    final titleStyle = TextStyle(
      color: textColor,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.15,
    );
    final subtitleStyle = TextStyle(
      color: isDark
          ? colorScheme.fontSecondary
          : colorScheme.fontSecondary.withValues(alpha: 0.68),
      fontSize: 12,
      height: 1.2,
    );
    final control = effectiveTrailing == null
        ? null
        : SizedBox(width: trailingWidth, child: effectiveTrailing);

    final row = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(bottom: BorderSide(color: dividerColor))
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textWidth =
                  constraints.maxWidth - 34 - 12 - 10 - (trailingWidth ?? 0);
              bool truncates(String value, TextStyle style) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: value,
                    style: DefaultTextStyle.of(context).style.merge(style),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 2,
                )..layout(maxWidth: textWidth);
                final result = painter.didExceedMaxLines;
                painter.dispose();
                return result;
              }

              final stackControl =
                  control != null &&
                  trailingWidth != null &&
                  (textWidth <= 0 ||
                      truncates(title, titleStyle) ||
                      (subtitle != null &&
                          truncates(subtitle!, subtitleStyle)));
              return Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: stackControl ? null : 2,
                          overflow: stackControl
                              ? TextOverflow.clip
                              : TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            maxLines: stackControl ? null : 2,
                            overflow: stackControl
                                ? TextOverflow.clip
                                : TextOverflow.ellipsis,
                            style: subtitleStyle,
                          ),
                        ],
                        if (stackControl) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: control,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (control != null && !stackControl) ...[
                    const SizedBox(width: 10),
                    control,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
    return onTap == null ? row : Semantics(button: true, child: row);
  }
}
