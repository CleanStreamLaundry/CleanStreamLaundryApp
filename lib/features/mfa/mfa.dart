import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/mfa/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MfaPage extends StatefulWidget {
  final MfaController controller;

  /// Revalidate authoritative admission; a valid code alone never grants access.
  final Future<void> Function() onVerified;

  /// Open an existing legitimate support action; this is not MFA recovery.
  final VoidCallback onSupport;
  final bool requiredForAccess;
  final VoidCallback? onNotNow;
  final VoidCallback? onSignInAgain;
  final String? accountEmail;

  const MfaPage({
    super.key,
    required this.controller,
    required this.onVerified,
    required this.onSupport,
    this.requiredForAccess = true,
    this.onNotNow,
    this.onSignInAgain,
    this.accountEmail,
  });

  @override
  State<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends State<MfaPage> {
  final _code = TextEditingController();
  bool _showSetup = false;
  String? _factorId;
  int? _generation;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    // Listing refreshes Auth; enrollment still requires the explicit button.
    widget.controller.load();
  }

  void _changed() {
    final controller = widget.controller;
    if (_factorId != controller.factorId ||
        _generation != controller.generation ||
        !controller.canVerify) {
      _code.clear();
    }
    if (controller.setup == null) _showSetup = false;
    _factorId = controller.factorId;
    _generation = controller.generation;
    setState(() {});
  }

  @override
  void didUpdateWidget(MfaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.dismiss();
      _code.clear();
      _showSetup = false;
      widget.controller.addListener(_changed);
      widget.controller.load();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.dismiss();
    _code.dispose();
    super.dispose();
  }

  void _verify() {
    final code = _code.text;
    _code.clear();
    widget.controller.verify(code, onVerified: widget.onVerified);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final colors = Theme.of(context).colorScheme;
    final setup = controller.setup;
    final stage = controller.stage;
    final hasCode = stage == MfaStage.setup || stage == MfaStage.challenge;
    final message = switch (stage) {
      MfaStage.idle => 'Loading authenticators.',
      MfaStage.readyToEnroll =>
        widget.requiredForAccess
            ? 'Authenticator setup is required for account access.'
            : 'Add an authenticator to protect your account.',
      MfaStage.setup => 'Finish authenticator setup.',
      MfaStage.challenge => 'Enter a code from your authenticator.',
      MfaStage.verified =>
        'Code verified. Account access requires a separate check.',
      MfaStage.blocked => 'Authenticator setup or verification is unavailable.',
      MfaStage.expired =>
        'Your session changed or expired. Reopen authentication.',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Authenticator'),
        automaticallyImplyLeading: false,
        leading: widget.onSignInAgain == null
            ? null
            : IconButton(
                tooltip: 'Back to login',
                onPressed: widget.onSignInAgain,
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.accountEmail?.isNotEmpty == true) ...[
                    Text('Signed in as ${widget.accountEmail}'),
                    const SizedBox(height: 16),
                  ],
                  Text(message, style: Theme.of(context).textTheme.titleMedium),
                  if (controller.isBusy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(
                      semanticsLabel: 'Waiting for authentication',
                    ),
                  ],
                  if (controller.isWaiting) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Still waiting for confirmation. Leaving this page will not cancel a request already sent.',
                    ),
                  ],
                  if (controller.message != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(controller.message!),
                    ),
                  ],
                  if (stage == MfaStage.readyToEnroll) ...[
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: controller.canEnroll
                          ? controller.enroll
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Set up authenticator'),
                    ),
                  ],
                  if (setup != null) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: _showSetup
                            ? 'Hide setup details'
                            : 'Show setup details',
                        onPressed: () =>
                            setState(() => _showSetup = !_showSetup),
                        icon: Icon(
                          _showSetup ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    if (_showSetup) ...[
                      const Text('Setup key'),
                      SelectableText(setup.secret),
                      const SizedBox(height: 16),
                      const Text('Authenticator URI'),
                      SelectableText(setup.uri),
                    ],
                  ],
                  if (stage == MfaStage.challenge &&
                      controller.factors.length > 1) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: controller.factorId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Authenticator',
                      ),
                      items: [
                        for (var i = 0; i < controller.factors.length; i++)
                          DropdownMenuItem(
                            value: controller.factors[i].id,
                            child: Text('Authenticator ${i + 1}'),
                          ),
                      ],
                      onChanged: controller.canVerify
                          ? (id) {
                              if (id != null) controller.selectFactor(id);
                            }
                          : null,
                    ),
                  ],
                  if (hasCode) ...[
                    const SizedBox(height: 24),
                    TextField(
                      controller: _code,
                      enabled: controller.canVerify,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: TextStyle(color: colors.fontInverted),
                      decoration: InputDecoration(
                        labelText: 'Six-digit code',
                        labelStyle: TextStyle(color: colors.fontSecondary),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (controller.canVerify) _verify();
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: controller.canVerify ? _verify : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Verify code'),
                    ),
                  ],
                  if (controller.canLoad || stage == MfaStage.verified) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: stage == MfaStage.verified
                            ? 'Check account access'
                            : 'Reload authenticators',
                        onPressed: controller.canRevalidate
                            ? () => controller.revalidate(
                                onVerified: widget.onVerified,
                              )
                            : controller.canLoad
                            ? controller.load
                            : null,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Lost access to your authenticator? Contact support. Account recovery requires verification.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.fontInverted,
                    ),
                    onPressed: widget.onSupport,
                    icon: const Icon(Icons.support_agent),
                    label: const Text('Contact support'),
                  ),
                  if (!widget.requiredForAccess &&
                      widget.onNotNow != null &&
                      !controller.isBusy &&
                      const [
                        MfaStage.idle,
                        MfaStage.readyToEnroll,
                      ].contains(stage))
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.fontInverted,
                      ),
                      onPressed: widget.onNotNow,
                      child: const Text('Not now'),
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
