import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:io';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef MaintenanceLocation = ({String? id, String address});

class MaintenanceController extends ChangeNotifier {
  final EdgeFunctionService edgeFunctionService;
  final ProfileService profileService;
  final AuthService authService;
  final StorageFileApi? imageStorage;
  final LocationService locationService = GetIt.instance<LocationService>();

  MaintenanceController({
    EdgeFunctionService? edgeFunctionService,
    ProfileService? profileService,
    AuthService? authService,
    this.imageStorage,
  })  : edgeFunctionService =
      edgeFunctionService ?? GetIt.instance<EdgeFunctionService>(),
        profileService = profileService ?? GetIt.instance<ProfileService>(),
        authService = authService ?? GetIt.instance<AuthService>() {
    _accountId = this.authService.getCurrentUserId;
    _authSubscription = this.authService.onAuthChange.listen(
      _onAuthChanged,
      onError: (Object _) => _onAuthChanged(this.authService.getCurrentUserId != null),
    );
  }

  final TextEditingController descriptionController = TextEditingController();

  final List<String> categories = const [
    'Washer/Dryer Maintenance',
    'App Maintenance',
    'Location Maintenance',
    'Other',
  ];

  String? selectedCategory;
  static const MaintenanceLocation noApplicableLocation =
      (id: null, address: 'No Applicable Location');
  List<MaintenanceLocation> locations = [];
  MaintenanceLocation? selectedLocation;
  File? selectedImage;

  bool attemptedSubmit = false;
  bool isLoading = false;
  static const unknownMessage =
      "We couldn't confirm submission. It may already have been received. "
      'Your draft is still here; contact support before submitting again.';
  String? submissionMessage;
  String? _accountId;
  Object _draftKey = Object();
  Object get draftKey => _draftKey;
  int _generation = 0;
  int get generation => _generation;
  bool _disposed = false;
  bool _submitting = false;
  Future<void>? _initialization;
  StreamSubscription<bool>? _authSubscription;
  ({File image, String path})? _uploadedPhoto;

  bool isCurrent(int generation) =>
      !_disposed &&
      generation == _generation &&
      authService.getCurrentUserId == _accountId;

  void _onAuthChanged(bool signedIn) {
    if (_disposed) return;
    _generation++;
    final accountId = signedIn ? authService.getCurrentUserId : null;
    if (accountId != _accountId) {
      _accountId = accountId;
      _draftKey = Object();
      selectedCategory = null;
      selectedLocation = null;
      selectedImage = null;
      _uploadedPhoto = null;
      descriptionController.clear();
      attemptedSubmit = false;
      submissionMessage = null;
    } else if (_submitting) {
      submissionMessage = unknownMessage;
    }
    isLoading = _initialization != null && _accountId != null && isCurrent(_generation);
    notifyListeners();
  }

  Future<void> init() {
    if (_accountId == null || !isCurrent(_generation)) return Future.value();
    return _initialization ??= _loadLocations().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _loadLocations() async {
    isLoading = true;
    try {
      // Auth events during a read coalesce into the next serialized attempt.
      while (_accountId != null && isCurrent(_generation)) {
        final generation = _generation;
        try {
          final List<dynamic> fetchedLocations = await locationService.getLocations();
          if (!isCurrent(generation)) continue;
          locations = [
            for (final loc in fetchedLocations)
              if (loc is Map)
                if (_locationId(loc['id']) case final String id)
                  (id: id, address: loc['Address'] is String &&
                      (loc['Address'] as String).trim().isNotEmpty
                      ? loc['Address'] as String : 'Location $id'),
          ];
          return;
        } catch (e) {
          if (!isCurrent(generation)) continue;
          locations = [];
          return;
        }
      }
    } finally {
      if (_accountId != null && isCurrent(_generation)) {
        isLoading = _submitting;
        notifyListeners();
      }
    }
  }

  Future<bool> _ensureCameraPermission() async {
    final camera = await Permission.camera.request();
    return camera.isGranted;
  }

  Future<void> pickImage(BuildContext context) async {
    if (_disposed) return;
    final generation = _generation;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Library'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (!isCurrent(generation) || !context.mounted || source == null) return;
    try {
      if (source == ImageSource.camera) {
        final allowed = await _ensureCameraPermission();
        if (!isCurrent(generation) || !context.mounted || !allowed) return;
      }
      final picked = await ImagePicker().pickImage(source: source);
      if (!isCurrent(generation) || !context.mounted) return;
      if (picked != null) {
        selectedImage = File(picked.path);
        notifyListeners();
      }
    } catch (_) {
      if (isCurrent(generation) && context.mounted) {
        submissionMessage =
            'Photo selection is unavailable. Your draft is still here.';
        notifyListeners();
      }
    }
  }

  void selectCategory(String category) {
    if (_disposed) return;
    selectedCategory = category;
    notifyListeners();
  }

  bool get isFormValid =>
      selectedCategory != null &&
          selectedLocation != null &&
          (selectedLocation == noApplicableLocation ||
              _locationId(selectedLocation!.id) != null) &&
          descriptionController.text.trim().isNotEmpty;

  void selectLocation(MaintenanceLocation location) {
    if (_disposed) return;
    selectedLocation = location;
    notifyListeners();
  }

  void markAttemptedSubmit() {
    if (_disposed) return;
    attemptedSubmit = true;
    notifyListeners();
  }

  static String? _locationId(Object? value) {
    // Numeric IDs must be exact on both VM and web; full bigint text stays text.
    final text = value is int && value > 0 && value <= 9007199254740991
        ? value.toString() : value is String ? value : null;
    if (text == null || !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(text) ||
        (text.length == 19 && text.compareTo('9223372036854775807') > 0)) {
      return null;
    }
    return text;
  }

  static bool _matchesAttachment(Object? reference, String? path) {
    if (path == null) return reference == null;
    return reference is Map && reference['bucket'] == 'maintenance-images' &&
        reference['id'] is String &&
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            caseSensitive: false).hasMatch(reference['id'] as String) &&
        reference['name'] == path && reference.containsKey('version') &&
        (reference['version'] == null || reference['version'] is String);
  }

  Future<bool> submitMaintenance() async {
    final generation = _generation;
    if (!isCurrent(generation)) return false;
    if (_submitting) {
      submissionMessage = unknownMessage;
      notifyListeners();
      return false;
    }
    final userId = _accountId;
    if (userId == null || !isFormValid) {
      submissionMessage = userId == null
          ? 'Sign in to submit a maintenance request.'
          : 'Please fill in all fields.';
      notifyListeners();
      return false;
    }
    final category = selectedCategory;
    final location = selectedLocation!;
    final description = descriptionController.text;
    final image = selectedImage;

    _submitting = true;
    isLoading = true;
    submissionMessage = null;
    notifyListeners();
    var postDispatched = false;
    try {
      if (!isCurrent(generation)) return false;
      String? imageUrl;
      String? imagePath;
      if (image != null) {
        final storage = imageStorage ??
            Supabase.instance.client.storage.from('maintenance-images');
        if (!identical(_uploadedPhoto?.image, image)) {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${userId.hashCode}.jpg';
          final path = 'requests/$fileName';
          await storage.upload(path, image, retryAttempts: 0);
          if (!isCurrent(generation)) return false;
          _uploadedPhoto = (image: image, path: path);
        }
        imagePath = _uploadedPhoto!.path;
        imageUrl = storage.getPublicUrl(imagePath);
      }
      if (!isCurrent(generation)) return false;
      final post = edgeFunctionService.runEdgeFunction(
        name: 'maintenance-request',
        body: {
          'user_id': userId,
          'category': category,
          'location': location.address,
          'location_id': location.id,
          'description': description,
          'image': imageUrl,
        },
      );
      postDispatched = true;
      // Timeout ends the UI wait, not transport; prevent overlapping POSTs.
      final response = await post.whenComplete(() {
        _submitting = false;
      }).timeout(const Duration(seconds: 20));
      if (!isCurrent(generation)) return false;
      final data = response?.data;
      final records = data is Map ? data['record'] : null;
      final record =
          records is List && records.length == 1 ? records.single : null;
      final success = response?.status == 200 &&
          data is Map && data['success'] == true && record is Map &&
          record['maint_id'] != null && record['user_id'] == userId &&
          record['category'] == category && record['location'] == location.address &&
          record.containsKey('location_id') &&
          (location.id == null ? record['location_id'] == null :
              record['location_id'] is int &&
              record['location_id'] <= 9007199254740991 &&
              _locationId(record['location_id']) == location.id) &&
          record['description'] == description &&
          record.containsKey('image_data') && record['image_data'] == null &&
          record.containsKey('attachment_ref') &&
          _matchesAttachment(record['attachment_ref'], imagePath);
      if (!success) submissionMessage = unknownMessage;
      return success;
    } catch (e) {
      if (isCurrent(generation)) submissionMessage = unknownMessage;
      return false;
    } finally {
      if (!postDispatched) _submitting = false;
      if (isCurrent(generation)) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void disposeController() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _authSubscription?.cancel();
    _uploadedPhoto = null;
    descriptionController.dispose();
  }

  @override
  void dispose() {
    disposeController();
    super.dispose();
  }
}
