import 'dart:math' as math;

import 'package:clean_stream_laundry_app/features/home/controller.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/availability_card.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/map.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/location_selector.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/header.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  static const pageKey = Key('home_page');

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final HomePageController _controller;
  late final MapController _mapController;
  bool _routeCurrent = true;
  bool _initialized = false;
  bool _foreground = true;
  String? _shownError;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _errorSnackBar;
  bool _errorSnackBarVisible = false;

  void refreshAfterWalletActivity() {
    _controller.refreshAfterWalletActivity();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();
    _controller = HomePageController();
    _controller.onZoom = (coords, zoom) => _mapController.move(coords, zoom);
    _controller.addListener(_rebuild);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
    final error = _controller.errorMessage;
    if (error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.errorMessage == null) _closeErrorSnackBar();
      });
    }
    if (_routeCurrent && error != null && error != _shownError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_routeCurrent || _controller.errorMessage != error) {
          return;
        }
        if (_errorSnackBar != null) return;
        final snackBar = ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            onVisible: () {
              _errorSnackBarVisible = true;
              if (_controller.errorMessage == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _controller.errorMessage == null) {
                    _closeErrorSnackBar();
                  }
                });
              }
            },
            content: Text(
              _controller.balance == null
                  ? error
                  : '$error. Showing the last loaded balance.',
            ),
            action: SnackBarAction(
              label: 'Refresh',
              onPressed: _controller.refresh,
            ),
          ),
        );
        _errorSnackBar = snackBar;
        snackBar.closed.then((_) {
          if (identical(_errorSnackBar, snackBar)) {
            _errorSnackBar = null;
            _errorSnackBarVisible = false;
          }
        });
      });
    }
    _shownError = error;
  }

  void _closeErrorSnackBar() {
    // A queued controller closes the current snack, not its own queue entry.
    if (!_errorSnackBarVisible) return;
    _errorSnackBar?.close();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    _controller.setActive(current && _foreground);
    if (!_initialized) {
      _initialized = true;
      _controller.init().catchError(
        (e) => debugPrint('HomePage init error: $e'),
      );
    } else if (current && !_routeCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _routeCurrent && _foreground) {
          _controller.refresh(ifStale: true);
        }
      });
    }
    _routeCurrent = current;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _controller.setActive(_routeCurrent && _foreground);
    if (_foreground && _routeCurrent) {
      _controller.refresh(ifStale: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_rebuild);
    _controller.disposeController();
    _controller.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: HomePage.pageKey,
      headerGradient: Theme.of(context).colorScheme.homeGradient,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 106,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: Theme.of(context).colorScheme.homeGradient,
              ),
            ),
          ),
          SafeArea(
            top: false,
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metrics = _HomeLayoutMetrics.fromConstraints(
                  constraints,
                  enlargedText: MediaQuery.textScalerOf(context).scale(14) > 18,
                );
                final content = _HomeContent(
                  metrics: metrics,
                  controller: _controller,
                  mapController: _mapController,
                  onAddFunds: () => context.go('/loyalty?loadCard=true'),
                  onStartLaundry: () => context.go('/startPage'),
                  onGetDirections: () async {
                    if (_controller.locationSelected &&
                        _controller.selectedName != null) {
                      await _controller.openDirectionsFromAddress(
                        _controller.selectedName,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please select a location to get directions!',
                          ),
                        ),
                      );
                    }
                  },
                );

                return _HomeResponsiveWrapper(
                  metrics: metrics,
                  child: metrics.needsScrollFallback
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                            vertical: metrics.verticalPadding,
                          ),
                          child: content,
                        )
                      : Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: metrics.verticalPadding,
                          ),
                          child: content,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final _HomeLayoutMetrics metrics;
  final HomePageController controller;
  final MapController mapController;
  final VoidCallback onAddFunds;
  final VoidCallback onStartLaundry;
  final VoidCallback onGetDirections;

  const _HomeContent({
    required this.metrics,
    required this.controller,
    required this.mapController,
    required this.onAddFunds,
    required this.onStartLaundry,
    required this.onGetDirections,
  });

  @override
  Widget build(BuildContext context) {
    final header = Header(controller: controller, onAddFunds: onAddFunds);
    final startButton = _StartLaundryButton(onPressed: onStartLaundry);
    final selector = LocationSelector(
      controller: controller,
      onNearestLocationTap: controller.selectNearestLocation,
      onGetDirections: onGetDirections,
    );
    final availability = AvailabilityCard(controller: controller);

    if (metrics.needsScrollFallback) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          SizedBox(height: metrics.gap),
          startButton,
          SizedBox(height: metrics.gap),
          selector,
          SizedBox(height: metrics.gap),
          LocationMap(
            locations: controller.locations,
            mapController: mapController,
            selectedLocation: controller.selectedCoordinates,
            height: metrics.mapHeight,
          ),
          SizedBox(height: metrics.gap),
          availability,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: metrics.gap),
        startButton,
        SizedBox(height: metrics.gap),
        selector,
        SizedBox(height: metrics.gap),
        Expanded(
          child: LocationMap(
            locations: controller.locations,
            mapController: mapController,
            selectedLocation: controller.selectedCoordinates,
            height: null,
          ),
        ),
        SizedBox(height: metrics.gap),
        availability,
      ],
    );
  }
}

class _HomeResponsiveWrapper extends StatelessWidget {
  final _HomeLayoutMetrics metrics;
  final Widget child;

  const _HomeResponsiveWrapper({required this.metrics, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
        child: SizedBox(
          width: metrics.contentWidth,
          height: metrics.availableHeight,
          child: child,
        ),
      ),
    );
  }
}

class _HomeLayoutMetrics {
  final double availableHeight;
  final double horizontalPadding;
  final double contentWidth;
  final double verticalPadding;
  final double gap;
  final double mapHeight;
  final bool needsScrollFallback;

  const _HomeLayoutMetrics({
    required this.availableHeight,
    required this.horizontalPadding,
    required this.contentWidth,
    required this.verticalPadding,
    required this.gap,
    required this.mapHeight,
    required this.needsScrollFallback,
  });

  factory _HomeLayoutMetrics.fromConstraints(
    BoxConstraints constraints, {
    required bool enlargedText,
  }) {
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 390.0;
    final height = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 700.0;
    final horizontalPadding = width < 380 ? 16.0 : 20.0;
    final contentWidth = math.min(
      500.0,
      math.max(0.0, width - (horizontalPadding * 2)),
    );
    final compactHeight = height < 760;
    final verticalPadding = compactHeight ? 4.0 : 8.0;
    final gap = compactHeight ? 6.0 : 8.0;
    final mapHeight = (height * (compactHeight ? 0.17 : 0.20)).clamp(
      118.0,
      180.0,
    );

    return _HomeLayoutMetrics(
      availableHeight: height,
      horizontalPadding: horizontalPadding,
      contentWidth: contentWidth,
      verticalPadding: verticalPadding,
      gap: gap,
      mapHeight: mapHeight,
      needsScrollFallback: enlargedText || height < 580.0,
    );
  }
}

class _StartLaundryButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _StartLaundryButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilledButton(
      key: const ValueKey('home-start-laundry-button'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.local_laundry_service_rounded, size: 23),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Start Laundry',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 30),
        ],
      ),
    );
  }
}
