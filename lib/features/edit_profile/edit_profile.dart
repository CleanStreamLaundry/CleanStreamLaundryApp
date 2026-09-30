import 'package:clean_stream_laundry_app/features/edit_profile/controller.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/danger_zone.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/email_form.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/info_card.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/name_form.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/save_button.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/section_header.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/widgets/status_dialog_box.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EditProfilePage extends StatefulWidget {
  final VoidCallback? onDeletionPending;

  const EditProfilePage({super.key, this.onDeletionPending});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final EditProfileController _controller;

  @override
  void initState() {
    super.initState();
    _controller = EditProfileController();
    _controller.init().catchError((e) {
      if (mounted) _showErrorDialog('Failed to load profile data: $e');
    });
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

  void _onSavePressed() async {
    if (!_controller.hasChanges) {
      statusDialog(
        context,
        title: 'No Changes',
        message: "You haven't changed anything.",
        isSuccess: false,
      );
      return;
    }

    final confirmed = await _confirmSaveChanges();
    if (!confirmed) return;

    if (!_formKey.currentState!.validate()) return;

    try {
      final emailChanged = await _controller.saveChanges();

      if (!mounted) return;

      if (emailChanged) {
        context.go('/change-email-verification');
        return;
      }

      statusDialog(
        context,
        title: 'Profile Updated',
        message: 'Your information has been updated successfully.',
        isSuccess: true,
      );
    } catch (e) {
      if (!mounted) return;
      statusDialog(
        context,
        title: 'Update Failed',
        message: e.toString(),
        isSuccess: false,
      );
    }
  }

  void _onDeletePressed() async {
    final status = await _controller.deleteAccount(
      confirm: _confirmDeleteAccount,
      isPageCurrent: () => mounted && (ModalRoute.of(context)?.isCurrent ?? false),
    );
    if (!mounted) return;
    if (status?.accountState == 'pending_deletion') {
      widget.onDeletionPending?.call();
      context.go('/admission');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Error',
          style: TextStyle(
            color: Theme.of(context).colorScheme.fontSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.fontSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmSaveChanges() async {
    return await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Text(
              'Confirm Changes',
              style: TextStyle(
                color: Theme.of(context).colorScheme.fontSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Are you sure you want to save these changes to your profile?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.fontSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.fontSecondary,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _confirmDeleteAccount() async {
    return await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (context) {
            var acknowledged = false;

            return StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                scrollable: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                title: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Delete Account?',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.fontSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Requesting deletion restricts account access. You have 30 days to recover your account by signing in again and explicitly restoring it. The recovery screen will show your exact deadline. This request does not erase financial records or refund your Loyalty Card balance.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.fontSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: acknowledged,
                      onChanged: (value) {
                        setDialogState(() => acknowledged = value ?? false);
                      },
                      title: Text(
                        'I understand I have 30 days to recover my account.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.fontSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.fontSecondary,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: acknowledged
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Request Deletion'),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).colorScheme.primaryGradient,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/settings'),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _controller.isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(title: 'Full Name'),
                      const SizedBox(height: 12),
                      InfoCard(
                        label: 'Current:',
                        value: _controller.currentName.isNotEmpty
                            ? _controller.currentName
                            : 'Not set',
                      ),
                      const SizedBox(height: 16),
                      NameFormField(
                        controller: _controller.nameController,
                        enabled: !_controller.isSaving,
                      ),
                      const SizedBox(height: 10),

                      const SectionHeader(title: 'Email Address'),
                      const SizedBox(height: 12),
                      InfoCard(
                        label: 'Current:',
                        value: _controller.currentEmail.isNotEmpty
                            ? _controller.currentEmail
                            : 'Not set',
                      ),
                      const SizedBox(height: 16),
                      EmailFormField(
                        controller: _controller.emailController,
                        enabled: !_controller.isSaving,
                      ),
                      const SizedBox(height: 20),

                      SaveButton(
                        isSaving: _controller.isSaving,
                        onPressed: _onSavePressed,
                      ),
                      const SizedBox(height: 30),

                      DangerZoneSection(
                        isSaving: _controller.isSaving || _controller.isDeleting,
                        needsStatusCheck: _controller.needsDeletionStatusCheck,
                        message: _controller.deletionMessage,
                        onDeletePressed: _onDeletePressed,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
