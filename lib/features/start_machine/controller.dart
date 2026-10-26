import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/services/kisi/door_unlocker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

const double minimumBalance = 20;

class StartPageController extends ChangeNotifier {
  final ProfileService profileService;
  final AuthService authService;
  final DoorUnlocker doorUnlocker;

  StartPageController({
    ProfileService? profileService,
    AuthService? authService,
    DoorUnlocker? doorUnlocker,
  }) : profileService = profileService ?? GetIt.instance<ProfileService>(),
       authService = authService ?? GetIt.instance<AuthService>(),
       doorUnlocker = doorUnlocker ?? DoorUnlocker();

  Map<String, dynamic>? balance;
  bool cancelSearch = false;
  int _readGeneration = 0;

  double? get balanceValue => balance?['balance'] as double?;

  bool get hasSufficientBalance {
    final bal = balanceValue;
    return bal != null && bal >= minimumBalance;
  }

  Future<void> loadUserData() async {
    final generation = ++_readGeneration;
    final userId = authService.getCurrentUserId;
    if (userId == null) return;

    final fetched = await profileService.getUserBalanceById(userId);
    if (generation != _readGeneration || userId != authService.getCurrentUserId) {
      return;
    }
    balance = fetched;
    notifyListeners();
  }

  Future<bool> unlockDoor() async {
    cancelSearch = false;
    return doorUnlocker.unlockNearestDoor();
  }

  void cancelUnlock() {
    cancelSearch = true;
    doorUnlocker.cancelUnlockingDoor();
  }

  @override
  void dispose() {
    _readGeneration++;
    super.dispose();
  }
}
