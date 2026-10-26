import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_action_context.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileController extends ChangeNotifier {
  final authService = GetIt.instance<AuthService>();
  final profileService = GetIt.instance<ProfileService>();
  late final StreamSubscription<AuthState> _deletionAuthSub;
  int _deletionGeneration = 0;
  bool _disposed = false;
  bool _deletionAuthAvailable = true;
  bool isDeleting = false;
  bool _deletionInProgress = false;
  bool needsDeletionStatusCheck = false;
  String? deletionMessage;
  LoyaltyActionContext? deletionContext;

  EditProfileController() {
    _deletionAuthSub = authService.authStateChanges.listen(
      (_) => _deletionGeneration++,
      onError: (Object _) {
        _deletionAuthAvailable = false;
        _deletionGeneration++;
      },
      onDone: () {
        _deletionAuthAvailable = false;
        _deletionGeneration++;
      },
    );
  }

  final nameController = TextEditingController();
  final emailController = TextEditingController();

  StreamSubscription? authSub;

  String currentName = '';
  String currentEmail = '';

  bool isLoading = true;
  bool isSaving = false;

  bool get hasChanges =>
      nameController.text.trim() != currentName ||
      emailController.text.trim() != currentEmail;

  Future<void> init() async {
    await loadUserData();

    authSub = authService.onAuthChange.listen((_) {
      loadUserData();
    });
  }

  Future<void> disposeController() async {
    _disposed = true;
    _deletionGeneration++;
    await _deletionAuthSub.cancel();
    nameController.dispose();
    emailController.dispose();
    await authSub?.cancel();
  }

  Future<void> loadUserData() async {
    try {
      final userId = await authService.getCurrentUserId;

      if (userId == null) {
        throw Exception("User not found");
      }

      final username = await profileService.getUserNameById(userId);
      final email = await authService.getCurrentUserEmail();

      currentName = username ?? '';
      currentEmail = email ?? '';

      nameController.text = currentName;
      emailController.text = currentEmail;
    } catch (e) {
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveChanges() async {
    if (isSaving) return false;

    if (!hasChanges) {
      throw Exception("No changes made");
    }

    final newName = nameController.text.trim();
    final newEmail = emailController.text.trim();

    final nameChanged = newName != currentName;
    final emailChanged = newEmail != currentEmail;

    isSaving = true;
    notifyListeners();

    try {
      await authService.updateUserAttributes(
        email: emailChanged ? newEmail : null,
        data: nameChanged ? {'full_name': newName} : null,
      );

      currentName = newName;
      currentEmail = newEmail;

      return emailChanged;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<AdmissionStatus?> deleteAccount({
    required Future<bool> Function() confirm,
    required bool Function() isPageCurrent,
  }) async {
    if (_disposed || _deletionInProgress || isSaving) return null;
    final session = authService.currentSession;
    final generation = _deletionGeneration;
    bool isCurrent() =>
        !_disposed &&
        _deletionAuthAvailable &&
        generation == _deletionGeneration &&
        session != null &&
        session.expiresAt != null &&
        session.accessToken.isNotEmpty &&
        !session.isExpired &&
        session.user.id == authService.getCurrentUserId &&
        session.user.id == authService.currentSession?.user.id &&
        session.accessToken == authService.currentSession?.accessToken &&
        isPageCurrent();
    if (!isCurrent()) return null;
    _deletionInProgress = true;
    isDeleting = true;
    deletionMessage = null;
    final checkOnly = needsDeletionStatusCheck;
    notifyListeners();
    try {
      if (!checkOnly) {
        try {
          final details = await profileService.getLoyaltyActionContext('account_deletion');
          if (!isCurrent()) return null;
          if (details.subjectId != session!.user.id) throw StateError('Account changed');
          if (details.action != 'account_deletion') throw StateError('Unexpected consent');
          deletionContext = details;
          isDeleting = false;
          notifyListeners();
        } catch (_) {
          if (isCurrent()) {
            deletionMessage = 'Unable to load deletion terms and balances. Please try again.';
          }
          return null;
        }
      }
      if (!checkOnly && !await confirm()) return null;
      await Future<void>.delayed(Duration.zero);
      if (!isCurrent()) return null;
      isDeleting = true;
      notifyListeners();
      if (!isCurrent()) return null;

      // Read before every new intent, including after leaving/reopening the page.
      final status = await profileService.getAdmissionStatus();
      await Future<void>.delayed(Duration.zero);
      if (!isCurrent()) return null;
      if (status.subjectId != session!.user.id) {
        throw StateError('Admission subject mismatch');
      }
      if (status.accountState == 'pending_deletion') return status;
      if (status.accountAccess != 'eligible') {
        deletionMessage =
            'Account access must be verified before requesting deletion.';
        return null;
      }
      needsDeletionStatusCheck = false;
      if (checkOnly) {
        deletionMessage =
            'No pending deletion was found. You can make a new request after confirming again.';
        return null;
      }
      if (!isCurrent()) return null;
      needsDeletionStatusCheck = true;
      final result = await profileService.requestAccountDeletion(
        consent: deletionContext!.acknowledge(),
      );
      await Future<void>.delayed(Duration.zero);
      if (!isCurrent()) return null;
      if (result.subjectId != session.user.id ||
          result.accountState != 'pending_deletion' ||
          result.accountAccess != 'restricted' ||
          result.restoreUntil == null) {
        throw StateError('Deletion was not acknowledged');
      }
      return result;
    } catch (_) {
      await Future<void>.delayed(Duration.zero);
      if (isCurrent()) {
        needsDeletionStatusCheck = true;
        deletionMessage =
            'The outcome could not be confirmed. Check account status before making another request.';
      }
      return null;
    } finally {
      deletionContext = null;
      _deletionInProgress = false;
      isDeleting = false;
      if (!_disposed) notifyListeners();
    }
  }
}
