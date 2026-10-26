import 'package:clean_stream_laundry_app/logic/models/release_policy.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_settings.dart';

class ReleaseGate extends StatefulWidget {
  final FirebaseService service;
  final Widget child;
  const ReleaseGate({super.key, required this.service, required this.child});

  @override
  State<ReleaseGate> createState() => _ReleaseGateState();
}

class _ReleaseGateState extends State<ReleaseGate> with WidgetsBindingObserver {
  String? _dismissed;
  String? _linkError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.service.resume();
  }

  Future<void> _update() async {
    final uri = widget.service.policy.updateUrl;
    if (uri == null) return;
    if (_linkError != null) setState(() => _linkError = null);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Store unavailable');
      }
      await widget.service.log(UsageEvent.updateOpened);
    } catch (_) {
      if (mounted) {
        setState(
          () => _linkError = 'Could not open the app store. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final hasOverlay = Overlay.maybeOf(context) != null;
      final decision = widget.service.decision;
      final hard =
          decision == ReleaseDecision.blocked ||
          decision == ReleaseDecision.maintenance;
      final recommendation = widget.service.policy.recommended.toString();
      final recommend =
          decision == ReleaseDecision.recommended &&
          _dismissed != recommendation;
      return Column(
        children: [
          if (recommend)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SafeArea(
                bottom: false,
                child: ListTile(
                  title: const Text('An update is available'),
                  subtitle: _linkError == null ? null : Text(_linkError!),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.service.policy.updateUrl != null)
                        IconButton(
                          tooltip: hasOverlay ? 'Update' : null,
                          onPressed: _update,
                          icon: Icon(
                            Icons.system_update,
                            semanticLabel: hasOverlay ? null : 'Update',
                          ),
                        ),
                      IconButton(
                        tooltip: hasOverlay ? 'Dismiss' : null,
                        icon: Icon(
                          Icons.close,
                          semanticLabel: hasOverlay ? null : 'Dismiss',
                        ),
                        onPressed: () =>
                            setState(() => _dismissed = recommendation),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Keep route/callback ownership and pending settlement alive underneath.
                ExcludeSemantics(
                  excluding: hard,
                  child: ExcludeFocus(
                    excluding: hard,
                    child: AbsorbPointer(
                      absorbing: hard,
                      // Keep route barriers from excluding the banner semantics.
                      child: Semantics(container: true, child: widget.child),
                    ),
                  ),
                ),
                if (hard)
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: SafeArea(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  decision == ReleaseDecision.maintenance
                                      ? Icons.build_outlined
                                      : Icons.system_update,
                                  size: 40,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  decision == ReleaseDecision.maintenance
                                      ? 'Temporarily unavailable'
                                      : 'Update required',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  decision == ReleaseDecision.maintenance
                                      ? 'Please check again later.'
                                      : 'This version is no longer supported.',
                                  textAlign: TextAlign.center,
                                ),
                                if (widget.service.policy.updateUrl != null)
                                  TextButton.icon(
                                    onPressed: _update,
                                    icon: const Icon(Icons.open_in_new),
                                    label: const Text('Open App Store'),
                                  ),
                                TextButton.icon(
                                  onPressed:
                                      widget.service.refreshReleasePolicy,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Check again'),
                                ),
                                if (_linkError != null) Text(_linkError!),
                                ExpansionTile(
                                  title: const Text(
                                    'Privacy and notifications',
                                  ),
                                  children: [
                                    FirebaseSettings(service: widget.service),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
