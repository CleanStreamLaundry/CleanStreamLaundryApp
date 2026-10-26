import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/features/admission/terms_page.dart';
import 'package:clean_stream_laundry_app/features/loading/widgets/logo.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdmissionPage extends StatefulWidget {
  final AdmissionController controller;
  // The caller owns the mutation, session binding and admission revalidation.
  final Future<void> Function()? onRestore;
  final VoidCallback? onSignInAgain;
  final VoidCallback? onContactSupport;
  final VoidCallback? onTopupRefunds;
  final VoidCallback? onVerifyEmail;

  const AdmissionPage({
    super.key,
    required this.controller,
    this.onRestore,
    this.onSignInAgain,
    this.onContactSupport,
    this.onTopupRefunds,
    this.onVerifyEmail,
  });

  @override
  State<AdmissionPage> createState() => _AdmissionPageState();
}

class _AdmissionPageState extends State<AdmissionPage> {
  bool _hasPresentedContent = false;
  bool _restoring = false;
  bool _needsStatusCheck = false;
  String? _restoreMessage;
  int? _messageGeneration;
  int? _policyLoadGeneration;

  bool get _canRestore =>
      widget.onRestore != null &&
      !_restoring &&
      !_needsStatusCheck &&
      !widget.controller.isChecking &&
      !widget.controller.isLoadingPolicy &&
      widget.controller.status?.accountState == 'pending_deletion' &&
      widget.controller.status?.reason == 'explicit_restore_required';

  Future<void> _restore() async {
    if (!_canRestore) return;
    final controller = widget.controller;
    final generation = controller.generation;
    final status = controller.status;
    final callback = widget.onRestore!;
    bool isCurrent() =>
        mounted &&
        identical(controller, widget.controller) &&
        generation == controller.generation &&
        identical(status, controller.status) &&
        callback == widget.onRestore;
    setState(() {
      _restoring = true;
      _needsStatusCheck = true;
      _restoreMessage = null;
    });
    try {
      await callback();
      if (!isCurrent()) return;
      _restoreMessage =
          'Check account access to confirm the current restoration status.';
    } catch (error) {
      if (!isCurrent()) return;
      _restoreMessage =
          error is PostgrestException &&
              error.code == 'PT403' &&
              error.message == 'fresh_session_required'
          ? 'Sign in again with a fresh session before restoring your account. Then check account access.'
          : 'The restoration outcome is unknown. Check account access before trying again.';
    } finally {
      if (mounted) {
        setState(() {
          _restoring = false;
          if (isCurrent()) _messageGeneration = generation;
        });
      }
    }
  }

  Future<void> _checkAccess() async {
    final controller = widget.controller;
    await controller.revalidate();
    if (!mounted || !identical(controller, widget.controller)) return;
    if (controller.status != null && !controller.isChecking) {
      setState(() {
        _needsStatusCheck = false;
        _restoreMessage = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void didUpdateWidget(AdmissionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _hasPresentedContent = false;
      _policyLoadGeneration = null;
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.dismissPolicy();
      _restoreMessage = null;
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.dismissPolicy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!_hasPresentedContent &&
        controller.status == null &&
        controller.isChecking &&
        controller.error == null) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: const Center(child: Logo()),
      );
    }
    _hasPresentedContent = true;
    final step = controller.status?.nextStep;
    final descriptor = controller.policyDescriptor;
    if (step == 'review_terms' &&
        controller.error == null &&
        controller.canReviewPolicy &&
        _policyLoadGeneration != controller.generation) {
      final generation = controller.generation;
      _policyLoadGeneration = generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !identical(controller, widget.controller) ||
            generation != controller.generation ||
            controller.error != null ||
            !controller.canReviewPolicy) {
          return;
        }
        controller.loadPolicy();
      });
    }
    if (step == 'review_terms' || (step == null && descriptor != null)) {
      return LoyaltyTermsPage(
        controller: controller,
        onBackToLogin: widget.onSignInAgain,
        onCheckAccess: _checkAccess,
      );
    }
    final pending = controller.status?.accountState == 'pending_deletion';
    final deadline = controller.status?.restoreUntil;
    final expired = pending && controller.status?.reason == 'restore_expired';
    final localDeadline = deadline?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final message = switch (step) {
      'home' => 'Your account is ready.',
      'review_terms' => 'Review the loyalty card terms.',
      'verify_email' => 'Email verification is required.',
      'enroll_totp' => 'Authenticator setup is required.',
      'challenge_totp' => 'An authenticator code is required.',
      'blocked' => 'Account access is unavailable.',
      _ =>
        controller.isChecking
            ? 'Checking account access.'
            : 'Account access has not been confirmed.',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account access'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(message, style: Theme.of(context).textTheme.titleMedium),
                  if (step == 'verify_email' && widget.onVerifyEmail != null)
                    TextButton.icon(
                      onPressed: widget.onVerifyEmail,
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: const Text('Verify email'),
                    ),
                  if (!pending && widget.onSignInAgain != null)
                    TextButton.icon(
                      onPressed: widget.onSignInAgain,
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in again'),
                    ),
                  if (!pending && widget.onContactSupport != null)
                    TextButton.icon(
                      onPressed: widget.onContactSupport,
                      icon: const Icon(Icons.support_agent),
                      label: const Text('Contact support'),
                    ),
                  if (pending) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Your account is pending deletion. Account access remains restricted.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recovery deadline: ${localizations.formatFullDate(localDeadline!)} '
                      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localDeadline), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))} (local time).',
                    ),
                    Text(
                      'Exact deadline (UTC): ${deadline!.toUtc().toIso8601String()}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      expired
                          ? 'The recovery window has ended. This does not confirm that the account has been deleted. Check account access or contact support.'
                          : 'Restoration must be requested before this deadline. Signing in does not automatically restore your account.',
                    ),
                    if (controller.status?.reason ==
                            'explicit_restore_required' &&
                        !expired) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _canRestore ? _restore : null,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore account'),
                      ),
                      if (widget.onRestore == null)
                        const Text(
                          'Restoration is not available on this screen.',
                        ),
                    ],
                    if (widget.onSignInAgain != null)
                      TextButton.icon(
                        onPressed: _restoring ? null : widget.onSignInAgain,
                        icon: const Icon(Icons.login),
                        label: const Text('Sign in again'),
                      ),
                    if (widget.onTopupRefunds != null)
                      TextButton.icon(
                        onPressed: _restoring ? null : widget.onTopupRefunds,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Top-up refunds'),
                      ),
                    if (widget.onContactSupport != null)
                      TextButton.icon(
                        onPressed: _restoring ? null : widget.onContactSupport,
                        icon: const Icon(Icons.support_agent),
                        label: const Text('Contact support'),
                      ),
                  ],
                  if (_restoreMessage != null &&
                      _messageGeneration == controller.generation) ...[
                    const SizedBox(height: 16),
                    Text(_restoreMessage!),
                  ],
                  if (_restoring) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(
                      semanticsLabel: 'Waiting for restoration status',
                    ),
                  ],
                  if (controller.isChecking || controller.isLoadingPolicy) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      semanticsLabel: controller.isAcceptingPolicy
                          ? 'Waiting for acceptance'
                          : 'Loading account information',
                    ),
                  ],
                  if (controller.error != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Unable to confirm account access. Please try again.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Check account access',
                      onPressed:
                          controller.isChecking ||
                              controller.isLoadingPolicy ||
                              _restoring
                          ? null
                          : _checkAccess,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
