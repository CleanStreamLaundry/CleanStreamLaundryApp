import 'package:clean_stream_laundry_app/features/loading/controller.dart';
import 'package:clean_stream_laundry_app/features/loading/widgets/error_view.dart';
import 'package:clean_stream_laundry_app/features/loading/widgets/logo.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key, this.controller});

  final LoadingPageController? controller;

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  late final LoadingPageController _controller;

  @override
  void initState() {
    super.initState();
    final router = GoRouter.of(context);
    final entryUri = router.routerDelegate.currentConfiguration.uri;
    _controller = widget.controller ?? LoadingPageController();
    _controller.init(
      navigate: (route, {extra}) => context.go(route, extra: extra),
      isMounted: () =>
          mounted && router.routerDelegate.currentConfiguration.uri == entryUri,
    );
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.disposeController();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: _controller.error != null
            ? ErrorView(error: _controller.error!)
            : const Logo(),
      ),
    );
  }
}
