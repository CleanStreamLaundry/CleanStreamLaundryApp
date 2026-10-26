import 'package:clean_stream_laundry_app/features/home/controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';
import 'package:flutter/material.dart';

class AvailabilityCard extends StatefulWidget {
  final HomePageController controller;
  final DateTime Function() now;
  const AvailabilityCard({
    super.key,
    required this.controller,
    this.now = DateTime.now,
  });
  @override
  State<AvailabilityCard> createState() => _AvailabilityCardState();
}

class _AvailabilityCardState extends State<AvailabilityCard>
    with WidgetsBindingObserver {
  MachineAvailability? _data;
  bool _checking = false;
  bool _manualRefresh = false;
  bool _failed = false;
  bool _active = true;
  bool _routeCurrent = false;
  DateTime? _lastRefresh;
  int? _location;
  int _generation = 0;
  Object? _scope;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_locationChanged);
    _location = widget.controller.locationIDSelected;
    _scope = _currentScope;
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    if (current && !_routeCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _routeCurrent) _refresh(ifStale: true);
      });
    }
    _routeCurrent = current;
  }

  @override
  void didUpdateWidget(covariant AvailabilityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_locationChanged);
      widget.controller.addListener(_locationChanged);
    }
    _locationChanged();
  }

  void _locationChanged() {
    final next = widget.controller.locationIDSelected;
    if (_scope == _currentScope) return;
    setState(() {
      _generation++;
      _scope = _currentScope;
      _location = next;
      _data = null;
      _checking = false;
      _failed = false;
      _lastRefresh = null;
    });
    _refresh();
  }

  Object get _currentScope => (
    widget.controller,
    widget.controller.accountId,
    widget.controller.accountEpoch,
    widget.controller.locationIDSelected,
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && _routeCurrent) _refresh(ifStale: true);
  }

  Future<void> _refresh({
    bool ifStale = false,
    bool userInitiated = false,
  }) async {
    if (_checking || !_active || !_routeCurrent || _location == null) return;
    if (ifStale &&
        !_failed &&
        _lastRefresh != null &&
        widget.now().difference(_lastRefresh!) <
            HomePageController.refreshMaxAge) {
      return;
    }
    final generation = _generation;
    final scope = _currentScope;
    setState(() {
      _checking = true;
      _manualRefresh = userInitiated;
    });
    try {
      final data = await widget.controller.getAvailability();
      if (!mounted || generation != _generation || scope != _currentScope) {
        return;
      }
      setState(() {
        _data = data;
        _failed = false;
        _checking = false;
        _lastRefresh = widget.now();
      });
    } catch (_) {
      if (!mounted || generation != _generation || scope != _currentScope) {
        return;
      }
      setState(() {
        _failed = true;
        _checking = false;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.controller.removeListener(_locationChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final data = _scope == _currentScope ? _data : null;
    final showProgress = _checking && (data == null || _manualRefresh);
    // This is a snapshot as of checkedAt. The backend checks freshness when
    // fetched; keep the displayed snapshot stable until Home opens or Refresh.
    final unavailable = _failed;
    String message;
    if (_location == null) {
      message = 'Select a location';
    } else if (showProgress) {
      message = 'Checking availability…';
    } else if (unavailable) {
      message = 'Status unavailable';
    } else if (data?.configured == false) {
      message = 'Machine status not connected';
    } else if (data?.unknown != null && data!.unknown > 0) {
      message =
          '${data.unknown} machine${data.unknown == 1 ? '' : 's'} with unconfirmed status';
    } else if (data?.checkedAt != null) {
      final time = MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(data!.checkedAt!));
      message = 'Last checked $time';
    } else {
      message = 'No connected machines';
    }
    return Card(
      elevation: 5,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      color: colors.homeCard,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.homeAccent.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 4, 9, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colors.homeAccent.withValues(alpha: .10),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    color: colors.homeAccent,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Availability',
                        style: TextStyle(
                          color: colors.homeAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.homeAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh availability',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  onPressed: showProgress || _location == null
                      ? null
                      : () {
                          widget.controller.refresh();
                          _refresh(userInitiated: true);
                        },
                  icon: showProgress
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 22),
                  color: colors.homeAccent,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _MachineAvailabilityStat(
                    label: 'washers',
                    available: unavailable
                        ? null
                        : data?.washers.displayedAvailable,
                    total: data?.washers.total ?? 0,
                    accentColor: colors.homeAccent,
                    icon: Icons.local_laundry_service_outlined,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _MachineAvailabilityStat(
                    label: 'dryers',
                    available: unavailable
                        ? null
                        : data?.dryers.displayedAvailable,
                    total: data?.dryers.total ?? 0,
                    accentColor: colors.secondary,
                    icon: Icons.local_laundry_service_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineAvailabilityStat extends StatelessWidget {
  final String label;
  final int? available;
  final int total;
  final Color accentColor;
  final IconData icon;

  const _MachineAvailabilityStat({
    required this.label,
    required this.available,
    required this.total,
    required this.accentColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = total <= 0
        ? 0.0
        : ((available ?? 0) / total).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 136;
        final compact = constraints.maxWidth < 150;
        final ringSize = tight ? 58.0 : (compact ? 63.0 : 70.0);
        final countSize = tight ? 26.0 : (compact ? 29.0 : 32.0);
        final iconSize = tight ? 23.0 : (compact ? 25.0 : 27.0);
        final labelSize = tight ? 11.5 : (compact ? 12.5 : 13.0);

        return Semantics(
          container: true,
          excludeSemantics: true,
          label: available == null
              ? '$label status unavailable'
              : '$available of $total $label ready',
          child: Container(
            constraints: const BoxConstraints(minHeight: 80),
            padding: EdgeInsets.symmetric(
              horizontal: tight ? 5 : (compact ? 6 : 8),
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: ringSize,
                  child: _AvailabilityRing(
                    progress: progress,
                    accentColor: accentColor,
                    icon: icon,
                    iconSize: iconSize,
                    strokeWidth: tight ? 6.5 : 7.5,
                  ),
                ),
                SizedBox(width: tight ? 7 : (compact ? 8 : 9)),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          available?.toString() ?? '—',
                          style: TextStyle(
                            color: colorScheme.homeAccent,
                            fontSize: countSize,
                            fontWeight: FontWeight.w700,
                            height: 0.95,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$label\navailable',
                          softWrap: false,
                          style: TextStyle(
                            color: colorScheme.fontInverted,
                            fontSize: labelSize,
                            fontWeight: FontWeight.w400,
                            height: 1.08,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AvailabilityRing extends StatelessWidget {
  final double progress;
  final Color accentColor;
  final IconData icon;
  final double iconSize;
  final double strokeWidth;

  const _AvailabilityRing({
    required this.progress,
    required this.accentColor,
    required this.icon,
    required this.iconSize,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final trackColor = Colors.grey.withValues(alpha: 0.18);

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: trackColor, width: strokeWidth),
            ),
          ),
        ),
        if (progress > 0)
          Positioned.fill(
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: strokeWidth,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.transparent,
              color: accentColor,
            ),
          ),
        Icon(icon, color: accentColor, size: iconSize),
      ],
    );
  }
}
