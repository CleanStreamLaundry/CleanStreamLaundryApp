import 'dart:math' as math;

import 'package:flutter/material.dart';

class WalletPassCard extends StatelessWidget {
  final String? username;
  final double balance;

  const WalletPassCard({
    super.key,
    required this.username,
    required this.balance,
  });

  String get _displayName {
    final trimmed = username?.trim();
    return trimmed == null || trimmed.isEmpty ? 'John Doe' : trimmed;
  }

  String get _formattedBalance => '\$${balance.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final width = math.min(availableWidth, 500.0);
        final height = (width * 0.48).clamp(164.0, 192.0).toDouble();

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Material(
              color: Colors.transparent,
              elevation: 9,
              shadowColor: colors.primary.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.secondary, width: 2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.primary, const Color(0xFF13BDFA)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      children: [
                        const Positioned.fill(child: _WalletPassBackground()),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.water_drop_rounded,
                                            color: Colors.white,
                                            size: 21,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Clean Stream',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      height: 1,
                                                    ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'For $_displayName',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.82,
                                                          ),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const _PassBadge(label: 'Laundry credit'),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                'Where freshness flows.',
                                key: const ValueKey('wallet-pass-slogan'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0,
                                    ),
                              ),
                              const SizedBox(height: 11),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Available balance',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: Colors.white.withValues(
                                                  alpha: 0.82,
                                                ),
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            _formattedBalance,
                                            key: const ValueKey(
                                              'wallet-pass-balance',
                                            ),
                                            maxLines: 1,
                                            style: Theme.of(context)
                                                .textTheme
                                                .displaySmall
                                                ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                  height: 1,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  const _PassBadge(
                                    label: 'Ready to use',
                                    accented: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PassBadge extends StatelessWidget {
  final String label;
  final bool accented;

  const _PassBadge({required this.label, this.accented = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accented
            ? colors.secondary
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _WalletPassBackground extends StatelessWidget {
  const _WalletPassBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _WalletPassPainter());
  }
}

class _WalletPassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final softWave = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final brightWave = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..style = PaintingStyle.fill;

    final wave = Path()
      ..moveTo(size.width * -0.05, size.height * 0.38)
      ..cubicTo(
        size.width * 0.24,
        size.height * 0.22,
        size.width * 0.52,
        size.height * 0.55,
        size.width * 0.83,
        size.height * 0.36,
      )
      ..cubicTo(
        size.width * 0.96,
        size.height * 0.28,
        size.width * 1.08,
        size.height * 0.28,
        size.width * 1.18,
        size.height * 0.34,
      );
    canvas.drawPath(wave, softWave);

    final bottomShape = Path()
      ..moveTo(0, size.height * 0.78)
      ..cubicTo(
        size.width * 0.24,
        size.height * 0.68,
        size.width * 0.45,
        size.height * 0.93,
        size.width * 0.73,
        size.height * 0.82,
      )
      ..cubicTo(
        size.width * 0.88,
        size.height * 0.76,
        size.width,
        size.height * 0.77,
        size.width,
        size.height * 0.77,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(bottomShape, brightWave);

    canvas.drawCircle(
      Offset(size.width * 0.93, size.height * 0.16),
      size.width * 0.15,
      highlight,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
