import 'controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'widgets/maintenance_form.dart';
import 'package:clean_stream_laundry_app/features/widgets/status_dialog_box.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MaintenancePage extends StatefulWidget {
  final MaintenanceController? controller;
  const MaintenancePage({super.key, this.controller});

  @override
  State<MaintenancePage> createState() => MaintenancePageState();
}

class MaintenancePageState extends State<MaintenancePage> {
  late final MaintenanceController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _handlingSubmission = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MaintenanceController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.init();
    });
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted)
      setState(() {
        _submitError = null;
      });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.disposeController();
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onSubmitPressed() async {
    if (_handlingSubmission || _controller.isLoading) return;
    _controller.markAttemptedSubmit();
    if (!_controller.isFormValid) return;
    await _handleMaintenance();
  }

  Future<void> _handleMaintenance() async {
    final generation = _controller.generation;
    setState(() {
      _handlingSubmission = true;
      _submitError = null;
    });
    try {
      final success = await _controller.submitMaintenance();
      if (!mounted || !_controller.isCurrent(generation)) return;
      if (success) {
        await _showMaintenanceDialog(generation);
      } else {
        setState(() {
          _submitError =
              _controller.submissionMessage ??
              MaintenanceController.unknownMessage;
        });
      }
    } catch (e) {
      if (!mounted || !_controller.isCurrent(generation)) return;
      setState(() {
        _submitError = MaintenanceController.unknownMessage;
      });
    } finally {
      if (mounted)
        setState(() {
          _handlingSubmission = false;
        });
    }
  }

  Future<void> _showMaintenanceDialog(int generation) async {
    await statusDialog(
      context,
      title: 'Success',
      message: 'Your maintenance request has been submitted',
      isSuccess: true,
    );
    if (mounted && _controller.isCurrent(generation)) context.go('/settings');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(20) * 2 + 16,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        title: const Text(
          'Request Maintenance',
          maxLines: 2,
          softWrap: true,
          style: TextStyle(
            letterSpacing: 0,
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: colorScheme.primaryGradient,
            border: Border(
              bottom: BorderSide(color: colorScheme.secondary, width: 3),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 40).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  KeyedSubtree(
                    key: ValueKey(_controller.draftKey),
                    child: MaintenanceForm(controller: _controller),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,

                        child: ElevatedButton(
                          onPressed:
                              _controller.isLoading || _handlingSubmission
                              ? null
                              : _onSubmitPressed,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(48, 52),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            backgroundColor: colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: _controller.isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Submit Maintenance Request',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    letterSpacing: 0,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      if ((_submitError ?? _controller.submissionMessage) !=
                          null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _submitError ?? _controller.submissionMessage!,
                            style: TextStyle(
                              letterSpacing: 0,
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                    ],
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
