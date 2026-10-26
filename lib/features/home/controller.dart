import 'dart:async';
import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';

import 'package:clean_stream_laundry_app/logic/parsing/location_parser.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/core/storage/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class HomePageController extends ChangeNotifier {
  static const _lastSelectedLocationKey = 'lastSelectedLocation';
  static const _lastSelectedLocationIdKey = 'lastSelectedLocationId';
  static const _locationSelectionModeKey = 'locationSelectionMode';
  static const _manualSelectionMode = 'manual';
  static const _nearestSelectionMode = 'nearest';
  static const refreshMaxAge = Duration(seconds: 30);
  static const requestTimeout = Duration(seconds: 20);

  final AuthService authService = GetIt.instance<AuthService>();
  final ProfileService profileService = GetIt.instance<ProfileService>();
  final LocationService locationService = GetIt.instance<LocationService>();
  final MachineService machineService = GetIt.instance<MachineService>();
  final LocationParser locationParser;

  HomePageController({LocationParser? locationParser, DateTime Function()? now})
    : locationParser = locationParser ?? LocationParser(),
      _now = now ?? DateTime.now;

  final DateTime Function() _now;
  late final WalletService _walletService = GetIt.instance<WalletService>();
  StreamSubscription<bool>? _authSubscription;
  Future<void>? _initFuture;
  Future<void>? _refreshFuture;
  String? _accountId;
  int _accountEpoch = 0;
  int _selectionEpoch = 0;
  bool _disposed = false;
  bool _active = true;
  bool _locationsPending = false;
  final _cancelReads = <void Function()>{};
  DateTime? _lastRefresh;
  bool isRefreshing = false;
  String? errorMessage;
  String? _username;
  Map<String, dynamic>? _balance;

  String? get accountId => authService.getCurrentUserId;
  int get accountEpoch => _accountEpoch;
  String? get username => _accountId == accountId ? _username : null;
  set username(String? value) => _username = value;
  Map<String, dynamic>? get balance =>
      _accountId == accountId ? _balance : null;
  set balance(Map<String, dynamic>? value) => _balance = value;

  Future<T> _bounded<T>(Future<T> request) {
    final result = Completer<T>();
    void cancel() {
      if (!result.isCompleted) result.completeError(StateError('Home closed'));
    }

    final timer = Timer(requestTimeout, () {
      result.completeError(TimeoutException('Home read timed out'));
    });
    _cancelReads.add(cancel);
    request.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future.whenComplete(() {
      timer.cancel();
      _cancelReads.remove(cancel);
    });
  }

  String? selectedName;
  final Map<String, int> locationID = {};
  final Map<String, LatLng> locationCoordinates = {};
  List<Map<String, dynamic>> locations = [];
  bool locationSelected = false;
  int? locationIDSelected;
  bool isLoading = true;
  StorageService storage = StorageService();
  String _selectionMode = _nearestSelectionMode;
  int? _storedLocationId;

  void Function(LatLng coords, double zoom)? onZoom;

  Map<String, dynamic>? get selectedLocation {
    if (locationIDSelected == null) return null;
    for (final location in locations) {
      if (location['id'] == locationIDSelected) return location;
    }
    return null;
  }

  LatLng? get selectedCoordinates {
    final location = selectedLocation;
    final lat = location?['Latitude'];
    final lng = location?['Longitude'];
    return lat is num && lng is num
        ? LatLng(lat.toDouble(), lng.toDouble())
        : null;
  }

  bool get isNearestSelection =>
      locationSelected && _selectionMode == _nearestSelectionMode;

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    if (active && _locationsPending) {
      _locationsPending = false;
      unawaited(
        Future<void>.microtask(() async {
          try {
            await _loadLocations();
          } catch (_) {
            if (!_disposed) errorMessage = 'Unable to refresh Home';
          } finally {
            if (!_disposed) notifyListeners();
          }
        }),
      );
    }
  }

  Future<void> init() {
    if (_disposed) return Future.value();
    _authSubscription ??= authService.onAuthChange.listen((signedIn) {
      if (_disposed) return;
      final next = signedIn ? accountId : null;
      final changed = _accountId != next;
      _syncAccount(next);
      if (signedIn && changed && _active) {
        unawaited(refresh());
      }
    });
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await Future.wait([
        refresh(),
        _initStorage().then((_) => _loadLocations()),
      ]);
    } catch (_) {
      if (!_disposed) errorMessage = 'Unable to refresh Home';
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _initStorage() async {
    final selection = _selectionEpoch;
    await storage.init();
    final storedMode = await storage.getValue(_locationSelectionModeKey);
    final lastVal = await storage.getValue(_lastSelectedLocationKey);
    final lastId = await storage.getValue(_lastSelectedLocationIdKey);
    if (_disposed || selection != _selectionEpoch) return;

    _selectionMode =
        storedMode ??
        (lastVal == null ? _nearestSelectionMode : _manualSelectionMode);
    selectedName = _selectionMode == _manualSelectionMode ? lastVal : null;
    _storedLocationId = int.tryParse(lastId ?? '');
  }

  void _syncAccount(String? userId) {
    if (userId != _accountId) {
      _accountId = userId;
      _accountEpoch++;
      _selectionEpoch++;
      _refreshFuture = null;
      _lastRefresh = null;
      _username = null;
      _balance = null;
      errorMessage = null;
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> refreshAfterWalletActivity() async {
    if (_disposed) return;
    final userId = accountId;
    _syncAccount(userId);
    if (userId == null) return;
    final epoch = _accountEpoch;
    // A pre-write read must not complete later and mark the old balance fresh.
    await _refreshFuture;
    if (_disposed || userId != accountId || epoch != _accountEpoch) return;
    _lastRefresh = null;
    await refresh();
  }

  Future<void> refresh({bool ifStale = false}) {
    if (_disposed) return Future.value();
    final userId = accountId;
    _syncAccount(userId);
    if (!_active || userId == null) return Future.value();
    if (_refreshFuture != null) return _refreshFuture!;
    if (ifStale &&
        _lastRefresh != null &&
        _now().difference(_lastRefresh!) < refreshMaxAge) {
      return Future.value();
    }
    final epoch = _accountEpoch;
    isRefreshing = true;
    late final Future<void> pending;
    pending = Future<void>.microtask(() => _loadUserData(userId, epoch))
        .whenComplete(() {
          if (identical(pending, _refreshFuture)) _refreshFuture = null;
        });
    _refreshFuture = pending;
    notifyListeners();
    return pending;
  }

  Future<void> _loadUserData(String userId, int epoch) async {
    bool current() =>
        !_disposed && epoch == _accountEpoch && userId == accountId;
    if (!current()) return;
    try {
      if (!_active) return;
      final values = await _bounded(
        Future.wait([
          profileService.getUserBalanceById(userId),
          _walletService.getBalance(),
        ]),
      );
      if (!current()) return;
      final profile = values[0] as Map<String, dynamic>?;
      if (profile == null) throw StateError('Profile unavailable');
      final wallet = values[1] as WalletBalance;
      _username = profile['full_name'] as String?;
      _balance = {...profile, 'balance': wallet.totalBalance};
      _lastRefresh = _now();
      errorMessage = null;
    } catch (_) {
      if (current()) errorMessage = 'Unable to refresh wallet balance';
    } finally {
      if (current()) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadLocations() async {
    if (_disposed) return;
    _locationsPending = !_active;
    if (!_active) return;
    final result = await _bounded(locationService.getLocations());
    if (_disposed) return;
    locations = result;
    locationID.clear();
    locationCoordinates.clear();

    for (final location in locations) {
      final address = location['Address'];
      final id = location['id'];
      final lat = location['Latitude'];
      final lng = location['Longitude'];

      if (address != null && id != null) locationID[address] = id;
      if (address != null && lat != null && lng != null) {
        locationCoordinates[address] = LatLng(
          (lat as num).toDouble(),
          (lng as num).toDouble(),
        );
      }
    }

    final storedManualLocation = selectedName;
    final storedMatches = locations
        .where(
          (location) => _storedLocationId != null
              ? location['id'] == _storedLocationId
              : location['Address'] == storedManualLocation,
        )
        .toList();
    if (_selectionMode == _manualSelectionMode && storedMatches.length == 1) {
      _selectLocationInMemory(
        storedMatches.single['Address'] as String,
        locationId: storedMatches.single['id'] as int,
        mode: _manualSelectionMode,
        shouldNotify: false,
        shouldZoom: false,
      );
      notifyListeners();
      return;
    }

    if (_selectionMode == _manualSelectionMode) {
      selectedName = null;
      locationSelected = false;
      locationIDSelected = null;
      _selectionMode = _nearestSelectionMode;
    }

    notifyListeners();
    if (locationCoordinates.isNotEmpty) {
      await _selectNearestLocation(shouldZoom: false);
    }
  }

  void selectLocation(String address, {int? locationId}) {
    if (_disposed || !locationID.containsKey(address)) return;
    _selectionEpoch++;
    final selected = _selectLocationInMemory(
      address,
      locationId: locationId,
      mode: _manualSelectionMode,
    );
    if (!selected) return;

    unawaited(
      _persistSelection(
        address,
        _manualSelectionMode,
        locationIDSelected!,
      ).catchError((e) => debugPrint('Unable to save selected location: $e')),
    );
  }

  Future<void> selectNearestLocation() async {
    await _selectNearestLocation();
  }

  Future<void> _selectNearestLocation({
    bool shouldNotify = true,
    bool shouldZoom = true,
  }) async {
    if (_disposed || locations.isEmpty || locationCoordinates.isEmpty) return;
    final selection = ++_selectionEpoch;

    Map<String, dynamic>? nearest;
    try {
      nearest = await _bounded(locationParser.getNearestLocation(locations));
    } catch (e) {
      debugPrint('Unable to select nearest location: $e');
      return;
    }

    if (!_disposed && selection == _selectionEpoch && nearest != null) {
      final address = nearest['Address'] as String?;
      if (address == null) return;

      final selected = _selectLocationInMemory(
        address,
        locationId: nearest['id'] as int?,
        mode: _nearestSelectionMode,
        shouldNotify: shouldNotify,
        shouldZoom: shouldZoom,
      );
      if (selected) {
        await _persistSelection(
          address,
          _nearestSelectionMode,
          locationIDSelected!,
        );
      }
    }
  }

  bool _selectLocationInMemory(
    String address, {
    int? locationId,
    required String mode,
    bool shouldNotify = true,
    bool shouldZoom = true,
  }) {
    final matches = locations
        .where(
          (location) =>
              location['Address'] == address &&
              (locationId == null || location['id'] == locationId),
        )
        .toList();
    if (matches.length != 1 || matches.single['id'] is! int) return false;
    final id = matches.single['id'] as int;

    selectedName = address;
    locationSelected = true;
    locationIDSelected = id;
    _selectionMode = mode;
    _storedLocationId = id;

    final coordinates = selectedCoordinates;
    if (shouldZoom && coordinates != null) {
      onZoom?.call(coordinates, 15.0);
    }

    if (shouldNotify) notifyListeners();
    return true;
  }

  Future<void> _persistSelection(String address, String mode, int id) async {
    await storage.setValue(_lastSelectedLocationIdKey, id.toString());
    await storage.setValue(_locationSelectionModeKey, mode);
    await storage.setValue(_lastSelectedLocationKey, address);
  }

  Future<MachineAvailability> getAvailability() {
    final id = locationIDSelected;
    if (id == null) throw StateError('Select a location first');
    return machineService.getAvailability(id);
  }

  Future<void> openDirectionsFromAddress(String? address) async {
    if (address == null) return;

    final encodedAddress = Uri.encodeComponent(address);
    Uri uri;

    if (kIsWeb) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$encodedAddress',
      );
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          uri = Uri.parse('google.navigation:q=$encodedAddress');
          break;
        case TargetPlatform.iOS:
          uri = Uri.parse(
            'http://maps.apple.com/?daddr=$encodedAddress&dirflg=d',
          );
          break;
        default:
          uri = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$encodedAddress',
          );
      }
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void disposeController() {
    if (_disposed) return;
    _disposed = true;
    for (final cancel in _cancelReads.toList()) {
      cancel();
    }
    _accountEpoch++;
    _selectionEpoch++;
    _authSubscription?.cancel();
    onZoom = null;
  }

  @override
  void dispose() {
    disposeController();
    super.dispose();
  }
}
