import 'dart:async';

import 'package:clean_stream_laundry_app/features/admission/admission.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/features/mfa/controller.dart';
import 'package:clean_stream_laundry_app/features/mfa/mfa.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Presentation gate only. Every protected API must also enforce admission.
class AdmissionGate extends StatefulWidget {
  final AdmissionController controller;
  final AuthService auth;
  final ProfileService profiles;
  final String location;
  final Widget child;

  const AdmissionGate({
    super.key,
    required this.controller,
    required this.auth,
    required this.profiles,
    required this.location,
    required this.child,
  });

  @override
  State<AdmissionGate> createState() => _AdmissionGateState();
}

class _AdmissionGateState extends State<AdmissionGate>
    with WidgetsBindingObserver {
  MfaController? _mfa;
  String? _mfaSubject;
  String? _presentedLocation;
  String? _presentedSubject;
  int? _checkedGeneration;
  bool _scheduled = false;
  bool _optionalMfa = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    unawaited(widget.controller.revalidate());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _mfa == null) {
      unawaited(widget.controller.revalidate());
    }
  }

  void _changed() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    // Resolve the gate in the same frame as its listening fallback page.
    // Build-time notifications still need the deferred update below.
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
    }
    // SDK events may arrive during a child build (notably MFA factor loading).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final controller = widget.controller;
      final session = widget.auth.currentSession;
      if (_mfa != null &&
          (_mfaSubject != session?.user.id ||
              _mfa!.stage == MfaStage.expired)) {
        _closeMfa();
      }
      if (controller.status == null &&
          controller.error == null &&
          !controller.isChecking &&
          session != null &&
          !session.isExpired &&
          _checkedGeneration != controller.generation) {
        _checkedGeneration = controller.generation;
        unawaited(controller.revalidate());
      }
      setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _closeMfa() {
    _mfa?.dispose();
    _mfa = null;
    _mfaSubject = null;
    _optionalMfa = false;
  }

  void _signInAgain() {
    widget.controller.invalidate();
    context.go('/login');
  }

  Future<void> _support() async {
    final opened = await launchUrl(
      Uri.parse('https://cleanstreamlaundry.com/support'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open support. Please try again.'),
        ),
      );
    }
  }

  Future<void> _restore() async {
    await widget.profiles.restoreAccount();
    if (mounted) await widget.controller.revalidate();
  }

  Future<void> _verified() async {
    final controller = widget.controller;
    await controller.revalidate();
    if (!mounted) return;
    if (controller.status == null) {
      throw StateError('Account access has not been confirmed');
    }
    if (_optionalMfa && controller.canEnterHome) context.go('/settings');
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    _closeMfa();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final session = widget.auth.currentSession;
    final step = controller.status?.nextStep;
    final path = Uri.parse(widget.location).path;
    final optional = path == '/security/mfa';
    final needsMfa = step == 'enroll_totp' || step == 'challenge_totp';
    if (_mfa == null && (needsMfa || (optional && controller.canEnterHome))) {
      _optionalMfa = optional && !needsMfa;
      _mfaSubject = session?.user.id;
      _mfa = MfaController(
        authService: widget.auth,
        mode: step == 'challenge_totp' ? MfaMode.challenge : MfaMode.enrollment,
      );
    }
    // Factor listing refreshes Auth. Keep that exact flow mounted until a
    // server check resolves it, rather than restarting enrollment on refresh.
    if (_mfa != null &&
        _mfaSubject == session?.user.id &&
        (needsMfa || controller.status == null || optional)) {
      return MfaPage(
        controller: _mfa!,
        onVerified: _verified,
        onSupport: _support,
        requiredForAccess: !_optionalMfa,
        onNotNow: _optionalMfa ? () => context.go('/settings') : null,
        onSignInAgain: _optionalMfa ? null : _signInAgain,
        accountEmail: session?.user.email,
      );
    }
    if (_mfa != null) _closeMfa();

    final admitted = switch (path) {
      '/maintenancePage' => controller.canUseMaintenance,
      '/topup-refunds' => controller.canUseTopupRefunds,
      _ => controller.canEnterHome,
    };
    if (admitted && path == '/admission') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.canEnterHome) context.go('/homePage');
      });
    } else if (admitted) {
      _presentedLocation = widget.location;
      _presentedSubject = session?.user.id;
    }
    final retained =
        controller.status == null &&
        controller.retainSafePresentation &&
        _presentedLocation == widget.location &&
        _presentedSubject == session?.user.id;
    if (path != '/admission' && (admitted || retained)) {
      return PopScope(
        canPop: admitted,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AbsorbPointer(
              absorbing: !admitted,
              child: ExcludeFocus(
                excluding: !admitted,
                child: ExcludeSemantics(
                  excluding: !admitted,
                  child: KeyedSubtree(
                    key: ValueKey(_presentedSubject),
                    child: widget.child,
                  ),
                ),
              ),
            ),
            if (!admitted && controller.error != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(
                    top: false,
                    child: ListTile(
                      title: const Text('Unable to confirm account access.'),
                      trailing: IconButton(
                        tooltip: 'Retry account access',
                        onPressed: controller.revalidate,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    _presentedLocation = null;
    _presentedSubject = null;
    return AdmissionPage(
      controller: controller,
      onRestore: _restore,
      onSignInAgain: _signInAgain,
      onContactSupport: _support,
      onTopupRefunds: controller.canUseTopupRefunds
          ? () => context.go('/topup-refunds')
          : null,
      onVerifyEmail: () => context.go('/email-verification'),
    );
  }
}
