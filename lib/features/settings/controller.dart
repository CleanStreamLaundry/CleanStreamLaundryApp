import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';

class SettingsController extends ChangeNotifier {
  static const int maxNotificationLeadTime = 30;

  final AuthService authService;
  final ProfileService profileService;
  final TransactionService transactionService;

  SettingsController({
    AuthService? authService,
    ProfileService? profileService,
    TransactionService? transactionService,
  }) : authService = authService ?? GetIt.instance<AuthService>(),
       profileService = profileService ?? GetIt.instance<ProfileService>(),
       transactionService =
           transactionService ?? GetIt.instance<TransactionService>();

  int notificationLeadTime = 5;
  bool isLoadingDelay = true;
  bool canUseAdminWallets = false;
  bool _disposed = false;

  Future<void> loadNotificationLeadTime() async {
    final userId = authService.getCurrentUserId;
    var value = notificationLeadTime;
    String? role;

    try {
      value = await profileService.getNotificationLeadTime();
    } catch (_) {
      value = 5;
    }

    if (_disposed || userId != authService.getCurrentUserId) return;
    notificationLeadTime = value.clamp(0, maxNotificationLeadTime).toInt();
    isLoadingDelay = false;
    notifyListeners();

    try {
      role = await profileService.getCurrentUserRole();
    } catch (_) {
      role = null;
    }

    if (_disposed || userId != authService.getCurrentUserId) return;
    canUseAdminWallets = role == 'Admin' || role == 'Owner';
    notifyListeners();
  }

  Future<void> updateLeadTime(int newValue) async {
    notificationLeadTime = newValue;
    notifyListeners();
    await profileService.setNotificationLeadTime(newValue);
  }

  Future<void> increment() async {
    if (notificationLeadTime < maxNotificationLeadTime) {
      await updateLeadTime(notificationLeadTime + 1);
    }
  }

  Future<void> decrement() async {
    if (notificationLeadTime > 0) {
      await updateLeadTime(notificationLeadTime - 1);
    }
  }

  Future<List<Map<String, dynamic>>> getTransactions() async {
    return transactionService.getTransactionsForUser();
  }

  Future<void> signOut() async {
    if (GetIt.instance.isRegistered<FirebaseService>()) {
      await GetIt.instance<FirebaseService>().disablePush();
    }
    await authService.logout();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
