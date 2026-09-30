import 'dart:async';
import 'dart:io';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_edge_function_service.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/widgets/maintenance_form.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMaintenanceController extends Mock implements MaintenanceController {}
class FakeBuildContext extends Fake implements BuildContext {}

void main() {
  late MockMaintenanceController controller;

  Widget buildForm() {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MaintenanceForm(controller: controller),
        ),
      ),
    );
  }

  setUp(() {
    controller = MockMaintenanceController();

    when(() => controller.categories).thenReturn(['Electrical', 'Washer', 'Dryer']);
    when(() => controller.selectedCategory).thenReturn(null);
    when(() => controller.descriptionController).thenReturn(TextEditingController());
    when(() => controller.selectedImage).thenReturn(null);
    when(() => controller.attemptedSubmit).thenReturn(false);
    when(() => controller.isFormValid).thenReturn(true);
    when(() => controller.locations).thenReturn([(id: '1', address: '123 Main St'), (id: '2', address: '456 Oak Ave')]);
    when(() => controller.selectedLocation).thenReturn(null);
    when(() => controller.generation).thenReturn(0);
    when(() => controller.isCurrent(any())).thenReturn(true);

    when(() => controller.selectCategory(any())).thenReturn(null);
    when(() => controller.selectLocation(any())).thenReturn(null);
    when(() => controller.pickImage(any())).thenAnswer((_) async {});
  });

  setUpAll(() {
    registerFallbackValue(FakeBuildContext());
    registerFallbackValue(MaintenanceController.noApplicableLocation);
  });

  testWidgets('MaintenanceForm renders all fields', (tester) async {
    await tester.pumpWidget(buildForm());

    expect(find.text('Select a Category'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Reason for Maintenance'), findsOneWidget);
    expect(find.text('Attach a Photo (Optional)'), findsOneWidget);
  });

  testWidgets('Dropdown shows categories and triggers selection', (tester) async {
    await tester.pumpWidget(buildForm());

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('Electrical'), findsOneWidget);
    await tester.tap(find.text('Washer').last);
    await tester.pumpAndSettle();

    verify(() => controller.selectCategory('Washer')).called(1);
  });

  testWidgets('LocationSelector opens bottom sheet and shows options', (tester) async {
    await tester.pumpWidget(buildForm());

    await tester.tap(find.text('Select Location'));
    await tester.pumpAndSettle();

    expect(find.text('No Applicable Location'), findsOneWidget);
    expect(find.text('123 Main St'), findsOneWidget);
    verifyNever(() => controller.selectLocation(any()));
  });

  testWidgets('Selecting a location calls controller.selectLocation', (tester) async {
    await tester.pumpWidget(buildForm());

    await tester.tap(find.text('Select Location'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('123 Main St'));
    await tester.pumpAndSettle();

    verify(() => controller.selectLocation((id: '1', address: '123 Main St'))).called(1);
  });

  testWidgets('Typing in description updates controller', (tester) async {
    final textController = TextEditingController();
    when(() => controller.descriptionController).thenReturn(textController);

    await tester.pumpWidget(buildForm());
    await tester.enterText(find.byType(TextField), 'Test description');
    expect(textController.text, 'Test description');
  });

  testWidgets('Shows image preview when selectedImage is present', (tester) async {
    final fakeFile = File('fake_path.jpg');
    when(() => controller.selectedImage).thenReturn(fakeFile);

    await tester.pumpWidget(buildForm());
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('Shows error message when form invalid and attemptedSubmit', (tester) async {
    when(() => controller.attemptedSubmit).thenReturn(true);
    when(() => controller.isFormValid).thenReturn(false);

    await tester.pumpWidget(buildForm());

    expect(find.text('Please fill in all fields'), findsOneWidget);
  });

  testWidgets('Tapping image picker calls controller.pickImage', (tester) async {
    await tester.pumpWidget(buildForm());
    await tester.tap(find.text('Tap to take or upload a photo'));
    await tester.pump();

    verify(() => controller.pickImage(any())).called(1);
  });

  controllerContractTests();
}

class _Auth extends Mock implements AuthService {}
class _Edge extends Mock implements EdgeFunctionService {}
class _Profile extends Mock implements ProfileService {}
class _Locations extends Mock implements LocationService {}
class _Storage extends Mock implements StorageFileApi {}
class _Photo extends Fake implements File {}
class _Client extends Mock implements SupabaseClient {}
class _Functions extends Mock implements FunctionsClient {}

void controllerContractTests() {
  group('MaintenanceController contract', () {
    const userA = '11111111-1111-4111-8111-111111111111';
    const userB = '22222222-2222-4222-8222-222222222222';
    late _Auth auth;
    late _Edge edge;
    late _Locations locations;
    late StreamController<bool> authEvents;
    late MaintenanceController subject;
    late _Storage storage;
    String? currentUser;

    Map<String, dynamic> row() => {
      'maint_id': '9007199254740993',
      'user_id': userA,
      'category': 'Other',
      'location': 'No Applicable Location',
      'description': 'Original description',
      'image_data': null,
      'location_id': null,
      'attachment_ref': null,
    };
    FunctionResponse response({int status = 200, dynamic data}) =>
        FunctionResponse(status: status, data: data ?? {
          'success': true,
          'record': [row()],
        });

    setUp(() {
      auth = _Auth();
      edge = _Edge();
      locations = _Locations();
      authEvents = StreamController<bool>.broadcast(sync: true);
      currentUser = userA;
      when(() => auth.getCurrentUserId).thenAnswer((_) => currentUser);
      when(() => auth.onAuthChange).thenAnswer((_) => authEvents.stream);
      when(() => locations.getLocations()).thenAnswer((_) async => []);
      GetIt.instance.registerSingleton<LocationService>(locations);
      storage = _Storage();
      subject = MaintenanceController(
        authService: auth,
        edgeFunctionService: edge,
        profileService: _Profile(),
        imageStorage: storage,
      );
      subject.selectedCategory = 'Other';
      subject.selectedLocation = MaintenanceController.noApplicableLocation;
      subject.descriptionController.text = 'Original description';
    });

    setUpAll(() { registerFallbackValue(_Photo()); });

    tearDown(() async {
      subject.disposeController();
      subject.dispose();
      await authEvents.close();
      await GetIt.instance.reset();
    });

    test('accepts only a matching acknowledged row without coercing its ID', () async {
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((_) async => response());
      expect(await subject.submitMaintenance(), isTrue);
      verify(() => edge.runEdgeFunction(name: 'maintenance-request', body: {
        'user_id': userA,
        'category': 'Other',
        'location': 'No Applicable Location',
        'location_id': null,
        'description': 'Original description',
        'image': null,
      })).called(1);
    });

    for (final status in [201, 204, 400, 401, 403, 503]) {
      test('does not acknowledge HTTP $status', () async {
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((_) async => response(status: status));
        expect(await subject.submitMaintenance(), isFalse);
      });
    }

    test('null wrapper response remains unknown and preserves the draft', () async {
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((_) async => null);
      expect(await subject.submitMaintenance(), isFalse);
      expect(subject.selectedCategory, 'Other');
      expect(subject.selectedLocation, MaintenanceController.noApplicableLocation);
      expect(subject.descriptionController.text, 'Original description');
      expect(subject.isLoading, isFalse);
      verify(() => edge.runEdgeFunction(name: 'maintenance-request', body: any(named: 'body'))).called(1);
    });

    for (final field in ['user_id', 'category', 'location', 'description', 'image_data', 'maint_id']) {
      test('rejects mismatched or absent $field', () async {
        final record = row()..[field] = field == 'maint_id' ? null : 'wrong';
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((_) async => response(data: {'success': true, 'record': [record]}));
        expect(await subject.submitMaintenance(), isFalse);
      });
    }

    for (final malformed in ['null data', 'string', 'false', 'missing success', 'empty', 'two rows', 'not list', 'null row']) {
      test('rejects malformed acknowledgement: $malformed', () async {
        final data = switch (malformed) {
          'null data' => null,
          'string' => '{"success":true}',
          'false' => {'success': false, 'record': [row()]},
          'missing success' => {'record': [row()]},
          'empty' => {'success': true, 'record': []},
          'two rows' => {'success': true, 'record': [row(), row()]},
          'not list' => {'success': true, 'record': row()},
          _ => {'success': true, 'record': [null]},
        };
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((_) async => FunctionResponse(status: 200, data: data));
        expect(await subject.submitMaintenance(), isFalse);
        expect(subject.submissionMessage, MaintenanceController.unknownMessage);
      });
    }

    test('rejects omitted image_data even when no attachment was submitted', () async {
      final record = row()..remove('image_data');
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((_) async => response(data: {'success': true, 'record': [record]}));
      expect(await subject.submitMaintenance(), isFalse);
    });

    test('duplicate addresses retain distinct IDs and POST the selected ID', () async {
      when(() => locations.getLocations()).thenAnswer((_) async => [
        {'id': 1, 'Address': 'Shared address'},
        {'id': '2', 'Address': 'Shared address'},
      ]);
      await subject.init();
      expect(subject.locations, [
        (id: '1', address: 'Shared address'),
        (id: '2', address: 'Shared address'),
      ]);
      subject.selectLocation(subject.locations.last);
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((call) async {
            final body = call.namedArguments[#body] as Map;
            expect(body['location_id'], '2');
            expect(body['location'], 'Shared address');
            return response(data: {'success': true, 'record': [
              row()..['location'] = 'Shared address'..['location_id'] = 2,
            ]});
          });
      expect(await subject.submitMaintenance(), isTrue);
      verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
    });

    for (final id in <Object?>[
      null, '', '0', 0, -1, '-1', '01', '+1', ' 1', '1 ', '1.0',
      '1e2', 1.5, true, <String, dynamic>{}, <int>[],
      '9223372036854775808', '10000000000000000000', 9007199254740992,
    ]) {
      test('invalid location ID ${id.runtimeType}: $id is never address-mapped', () async {
        when(() => locations.getLocations()).thenAnswer((_) async => [
          {'id': id, 'Address': 'Shared address'},
          {'id': 2, 'Address': 'Shared address'},
        ]);
        await subject.init();
        expect(subject.locations, [(id: '2', address: 'Shared address')]);
        if (id is String) {
          subject.selectedLocation = (id: id, address: 'Shared address');
          expect(subject.isFormValid, isFalse);
          expect(await subject.submitMaintenance(), isFalse);
        }
        verifyNoMoreInteractions(edge);
        verifyNoMoreInteractions(storage);
      });
    }

    test('nullable addresses remain selectable by ID, never inferred from text', () async {
      when(() => locations.getLocations()).thenAnswer((_) async => [
        {'id': 3, 'Address': null},
        {'id': 4, 'Address': ''},
        {'id': 5, 'Address': 'No Applicable Location'},
      ]);
      await subject.init();
      expect(subject.locations, [
        (id: '3', address: 'Location 3'),
        (id: '4', address: 'Location 4'),
        (id: '5', address: 'No Applicable Location'),
      ]);
      subject.selectLocation(subject.locations.last);
      expect(subject.selectedLocation!.id, '5');
      subject.selectLocation(MaintenanceController.noApplicableLocation);
      expect(subject.selectedLocation!.id, isNull);
      expect(subject.isFormValid, isTrue);
      subject.selectedLocation = (id: null, address: 'Some address');
      expect(subject.isFormValid, isFalse);
      expect(await subject.submitMaintenance(), isFalse);
      verifyNoMoreInteractions(edge);
    });

    for (final id in ['9007199254740991', '9007199254740993', '9223372036854775807']) {
      test('bigint string $id survives selection and POST without numeric coercion', () async {
        when(() => locations.getLocations()).thenAnswer((_) async => [
          {'id': id, 'Address': 'Large ID'},
        ]);
        await subject.init();
        subject.selectLocation(subject.locations.single);
        expect(subject.selectedLocation!.id, id);
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((call) async {
              expect((call.namedArguments[#body] as Map)['location_id'], id);
              // Frozen Edge rejects unsafe numeric acknowledgements, even after commit.
              return id == '9007199254740991'
                  ? response(data: {'success': true, 'record': [
                      row()..['location'] = 'Large ID'..['location_id'] = 9007199254740991,
                    ]})
                  : response(status: 503);
            });
        expect(await subject.submitMaintenance(), id == '9007199254740991');
        expect(subject.selectedLocation!.id, id);
        verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
      });
    }

    for (final id in <Object?>[null, '7', 8, 7.5, true, 9007199254740992]) {
      test('rejects noncanonical or mismatched server location_id: $id', () async {
        subject.selectedLocation = (id: '7', address: 'Captured address');
        final record = row()..['location'] = 'Captured address'..['location_id'] = id;
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((_) async => response(data: {'success': true, 'record': [record]}));
        expect(await subject.submitMaintenance(), isFalse);
        expect(subject.submissionMessage, MaintenanceController.unknownMessage);
        verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
      });
    }

    for (final field in ['location_id', 'attachment_ref']) {
      for (final absent in [false, true]) {
        test('no-photo null contract rejects ${absent ? 'absent' : 'nonnull'} $field', () async {
          final record = row();
          if (absent) { record.remove(field); }
          else { record[field] = field == 'location_id' ? 1 : <String, dynamic>{}; }
          when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
              .thenAnswer((_) async => response(data: {'success': true, 'record': [record]}));
          expect(await subject.submitMaintenance(), isFalse);
          expect(subject.selectedLocation, MaintenanceController.noApplicableLocation);
          verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
        });
      }
    }

    for (final changeAccount in [false, true]) {
      test('captured ID and photo survive edits but reject account switch: $changeAccount', () async {
        final upload = Completer<String>();
        final post = Completer<FunctionResponse?>();
        String? path;
        final photo = _Photo();
        subject.selectedImage = photo;
        subject.selectedLocation = (id: '7', address: 'Same address');
        when(() => storage.upload(any(), any(), retryAttempts: 0)).thenAnswer((call) {
          path = call.positionalArguments.first as String;
          return upload.future;
        });
        when(() => storage.getPublicUrl(any())).thenAnswer((call) =>
            'https://fixture.invalid/${call.positionalArguments.first}');
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((call) {
              expect((call.namedArguments[#body] as Map)['location_id'], '7');
              return post.future;
            });
        final operation = subject.submitMaintenance();
        subject.selectLocation((id: '8', address: 'Same address'));
        subject.selectedImage = _Photo();
        upload.complete('acknowledged');
        await Future<void>.value();
        if (changeAccount) {
          currentUser = userB;
          authEvents.add(true);
          currentUser = userA;
          authEvents.add(true);
        }
        post.complete(response(data: {'success': true, 'record': [
          row()..['location'] = 'Same address'..['location_id'] = 7
            ..['attachment_ref'] = {
              'bucket': 'maintenance-images', 'id': userA, 'name': path, 'version': null,
            },
        ]}));
        expect(await operation, !changeAccount);
        expect(subject.selectedLocation, changeAccount ? null : (id: '8', address: 'Same address'));
        if (changeAccount) expect(subject.selectedImage, isNull);
        verify(() => storage.upload(any(), photo, retryAttempts: 0)).called(1);
        verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
      });
    }

    for (final malformed in [
      'missing reference', 'null reference', 'list reference', 'empty reference',
      'missing bucket', 'null bucket', 'wrong bucket',
      'missing id', 'null id', 'empty id', 'wrong id', 'numeric id',
      'missing name', 'null name', 'empty name', 'wrong name', 'encoded name',
      'missing version', 'boolean version', 'numeric version', 'object version', 'list version',
      'legacy image',
    ]) {
      test('malformed attachment acknowledgement stays unknown: $malformed', () async {
        final photo = _Photo();
        subject.selectedImage = photo;
        String? path;
        when(() => storage.upload(any(), any(), retryAttempts: 0)).thenAnswer((call) async {
          path = call.positionalArguments.first as String;
          return 'acknowledged';
        });
        when(() => storage.getPublicUrl(any())).thenReturn('https://fixture.invalid/photo');
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((_) async {
              final ref = <String, dynamic>{
                'bucket': 'maintenance-images', 'id': userA, 'name': path, 'version': null,
              };
              final record = row()..['attachment_ref'] = ref;
              switch (malformed) {
                case 'missing reference': record.remove('attachment_ref');
                case 'null reference': record['attachment_ref'] = null;
                case 'list reference': record['attachment_ref'] = [ref];
                case 'empty reference': ref.clear();
                case 'missing bucket': ref.remove('bucket');
                case 'null bucket': ref['bucket'] = null;
                case 'wrong bucket': ref['bucket'] = 'other-bucket';
                case 'missing id': ref.remove('id');
                case 'null id': ref['id'] = null;
                case 'empty id': ref['id'] = '';
                case 'wrong id': ref['id'] = 'not-a-uuid';
                case 'numeric id': ref['id'] = 1;
                case 'missing name': ref.remove('name');
                case 'null name': ref['name'] = null;
                case 'empty name': ref['name'] = '';
                case 'wrong name': ref['name'] = 'requests/other.jpg';
                case 'encoded name': ref['name'] = Uri.encodeComponent(path!);
                case 'missing version': ref.remove('version');
                case 'boolean version': ref['version'] = false;
                case 'numeric version': ref['version'] = 1;
                case 'object version': ref['version'] = <String, dynamic>{};
                case 'list version': ref['version'] = <String>[];
                case 'legacy image': record['image_data'] = 'https://fixture.invalid/photo';
              }
              return response(data: {'success': true, 'record': [record]});
            });
        expect(await subject.submitMaintenance(), isFalse);
        expect(subject.submissionMessage, MaintenanceController.unknownMessage);
        expect(subject.descriptionController.text, 'Original description');
        expect(subject.selectedImage, same(photo));
        verify(() => storage.upload(any(), photo, retryAttempts: 0)).called(1);
        verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
      });
    }

    for (final version in <String?>[null, '', 'opaque version/!?', '   ']) {
      test('accepts explicit opaque attachment version: "$version"', () async {
        subject.selectedImage = _Photo();
        String? path;
        when(() => storage.upload(any(), any(), retryAttempts: 0)).thenAnswer((call) async {
          path = call.positionalArguments.first as String;
          return 'acknowledged';
        });
        when(() => storage.getPublicUrl(any())).thenReturn('https://fixture.invalid/photo');
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((_) async => response(data: {'success': true, 'record': [
              row()..['attachment_ref'] = {
                'bucket': 'maintenance-images', 'id': userA.toUpperCase(),
                'name': path, 'version': version,
              },
            ]}));
        expect(await subject.submitMaintenance(), isTrue);
      });
    }

    test('sanitizes thrown errors without retrying or clearing text', () async {
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenThrow(StateError('synthetic internal detail'));
      expect(await subject.submitMaintenance(), isFalse);
      expect(subject.submissionMessage, MaintenanceController.unknownMessage);
      expect(subject.submissionMessage, isNot(contains('internal detail')));
      expect(subject.descriptionController.text, 'Original description');
      verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
    });

    test('duplicates are blocked while the submitted snapshot remains immutable', () async {
      final pending = Completer<FunctionResponse?>();
      Map<String, dynamic>? body;
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((call) { body = call.namedArguments[#body]; return pending.future; });
      final first = subject.submitMaintenance();
      subject.descriptionController.text = 'Edited after dispatch';
      expect(await subject.submitMaintenance(), isFalse);
      expect(body?['description'], 'Original description');
      pending.complete(response());
      expect(await first, isTrue);
      expect(subject.descriptionController.text, 'Edited after dispatch');
      verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
    });

    test('initial replay preserves the draft but advances pending-work generation', () {
      final before = subject.generation;
      final draft = subject.draftKey;
      authEvents.add(true);
      expect(subject.generation, greaterThan(before));
      expect(subject.draftKey, same(draft));
      expect(subject.selectedCategory, 'Other');
      expect(subject.selectedLocation, MaintenanceController.noApplicableLocation);
      expect(subject.descriptionController.text, 'Original description');
    });

    test('initial signed-out replay does not wipe an anonymous draft', () async {
      subject.dispose();
      currentUser = null;
      subject = MaintenanceController(authService: auth,
        edgeFunctionService: edge, profileService: _Profile(), imageStorage: storage);
      subject.descriptionController.text = 'Not yet submitted';
      final draft = subject.draftKey;
      authEvents.add(false);
      expect(subject.descriptionController.text, 'Not yet submitted');
      expect(subject.draftKey, same(draft));
      expect(await subject.submitMaintenance(), isFalse);
      expect(subject.submissionMessage, 'Sign in to submit a maintenance request.');
      verifyNever(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')));
    });

    test('Auth stream errors invalidate pending work without exposing the error or wiping a draft', () async {
      final post = Completer<FunctionResponse?>();
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((_) => post.future);
      final operation = subject.submitMaintenance();
      authEvents.addError(StateError('synthetic Auth error'));
      post.complete(response());
      expect(await operation, isFalse);
      expect(subject.descriptionController.text, 'Original description');
      expect(subject.submissionMessage, MaintenanceController.unknownMessage);
    });

    for (final stage in ['upload', 'post']) {
      for (final invalidation in ['dispose', 'B', 'A-B-A', 'signout-login', 'same-account event']) {
        test('$stage late completion is isolated after $invalidation', () async {
          final upload = Completer<String>();
          final post = Completer<FunctionResponse?>();
          if (stage == 'upload') subject.selectedImage = _Photo();
          when(() => storage.upload(any(), any(), retryAttempts: 0)).thenAnswer((_) => upload.future);
          when(() => storage.getPublicUrl(any())).thenReturn('https://fixture.invalid/photo');
          when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
              .thenAnswer((_) => post.future);
          var notifications = 0;
          subject.addListener(() { notifications++; });
          final operation = subject.submitMaintenance();
          if (invalidation == 'dispose') {
            subject.disposeController();
            expect(authEvents.hasListener, isFalse);
          } else if (invalidation == 'same-account event') {
            authEvents.add(true);
          } else if (invalidation == 'signout-login') {
            currentUser = null;
            authEvents.add(false);
            currentUser = userA;
            authEvents.add(true);
          } else {
            currentUser = userB;
            authEvents.add(true);
            if (invalidation == 'A-B-A') {
              currentUser = userA;
              authEvents.add(true);
            }
          }
          final afterInvalidation = notifications;
          if (stage == 'upload') { upload.complete('acknowledged'); }
          else { post.complete(response()); }
          expect(await operation, isFalse);
          expect(notifications, afterInvalidation);
          if (stage == 'upload') {
            verifyNever(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')));
          } else {
            verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
          }
          if (invalidation != 'dispose' && invalidation != 'same-account event') {
            expect(subject.descriptionController.text, isEmpty);
            expect(subject.selectedImage, isNull);
            expect(subject.submissionMessage, isNull);
          }
        });
      }
    }

    test('queued A-B-A auth events invalidate even when the getter already reads A', () async {
      final post = Completer<FunctionResponse?>();
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((_) => post.future);
      final operation = subject.submitMaintenance();
      authEvents.add(true);
      authEvents.add(true);
      post.complete(response());
      expect(await operation, isFalse);
      expect(subject.descriptionController.text, 'Original description');
    });

    test('reuses acknowledged upload on manual resubmission, but not a new photo', () async {
      final photo = _Photo();
      subject.selectedImage = photo;
      final paths = <String>[];
      when(() => storage.upload(any(), any(), retryAttempts: 0)).thenAnswer((call) async {
        paths.add(call.positionalArguments.first as String);
        return 'acknowledged';
      });
      when(() => storage.getPublicUrl(any())).thenAnswer((call) => 'https://fixture.invalid/${call.positionalArguments.first}');
      final bodies = <Map<String, dynamic>>[];
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((call) async { bodies.add(Map.from(call.namedArguments[#body])); return null; });
      expect(await subject.submitMaintenance(), isFalse);
      expect(subject.selectedImage, same(photo));
      expect(subject.descriptionController.text, 'Original description');
      expect(await subject.submitMaintenance(), isFalse);
      expect(paths.length, 1);
      expect(bodies[0]['image'], bodies[1]['image']);
      subject.selectedImage = _Photo();
      expect(await subject.submitMaintenance(), isFalse);
      expect(paths.length, 2);
      expect(bodies.length, 3);
    });

    test('failed upload never posts or treats a URL as an acknowledgement', () async {
      final photo = _Photo();
      subject.selectedImage = photo;
      when(() => storage.upload(any(), any(), retryAttempts: 0)).thenThrow(StateError('synthetic upload error'));
      expect(await subject.submitMaintenance(), isFalse);
      expect(subject.selectedImage, same(photo));
      expect(subject.submissionMessage, MaintenanceController.unknownMessage);
      verifyNever(() => storage.getPublicUrl(any()));
      verifyNever(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')));
    });

    for (final lateError in [false, true]) {
      testWidgets('20s timeout keeps POST lock until late ${lateError ? 'error' : 'success'} settles', (tester) async {
        final post = Completer<FunctionResponse?>();
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((_) => post.future);
        final operation = subject.submitMaintenance();
        await tester.pump(const Duration(seconds: 20));
        expect(await operation, isFalse);
        expect(subject.isLoading, isFalse);
        expect(subject.submissionMessage, MaintenanceController.unknownMessage);
        expect(subject.descriptionController.text, 'Original description');
        expect(await subject.submitMaintenance(), isFalse);
        await tester.pump(const Duration(minutes: 1));
        verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
        if (lateError) { post.completeError(StateError('late synthetic error')); }
        else { post.complete(response()); }
        await tester.pump();
        expect(subject.submissionMessage, MaintenanceController.unknownMessage);
        expect(tester.takeException(), isNull);
        verifyNoMoreInteractions(edge);
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((_) async => response());
        expect(await subject.submitMaintenance(), isTrue);
      });
    }

    test('late location initialization neither publishes after disposal nor unlocks a POST', () async {
      final loaded = Completer<List<Map<String, dynamic>>>();
      final post = Completer<FunctionResponse?>();
      when(() => locations.getLocations()).thenAnswer((_) => loaded.future);
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((_) => post.future);
      final initialization = subject.init();
      final operation = subject.submitMaintenance();
      loaded.complete([{'id': 1, 'Address': 'Fixture address'}]);
      await initialization;
      expect(subject.locations, [(id: '1', address: 'Fixture address')]);
      expect(subject.isLoading, isTrue);
      subject.disposeController();
      post.completeError(StateError('late synthetic error'));
      expect(await operation, isFalse);
    });

    test('actual wrapper preserves body subject when modeled shared SDK Auth changes', () async {
      var inserts = 0;
      var requests = 0;
      var sdkSubject = userA;
      final client = _Client();
      final functions = _Functions();
      when(() => client.functions).thenReturn(functions);
      when(() => functions.invoke(any(), body: any(named: 'body')))
        .thenAnswer((call) async {
          requests++;
          final body = call.namedArguments[#body] as Map;
          expect(call.namedArguments[#headers], isNull);
          expect(body['user_id'], userA);
          // Model the reviewed backend check, not a bearer bound by this client.
          if (body['user_id'] != sdkSubject) {
            throw const FunctionException(status: 403, details: {'code': 'user_mismatch'});
          }
          inserts++;
          return response();
        });
      subject.dispose();
      subject = MaintenanceController(authService: auth,
        edgeFunctionService: SupabaseEdgeFunctionService(client: client),
        profileService: _Profile(), imageStorage: storage);
      subject.selectedCategory = 'Other';
      subject.selectedLocation = MaintenanceController.noApplicableLocation;
      subject.descriptionController.text = 'Original description';
      sdkSubject = userB;
      expect(await subject.submitMaintenance(), isFalse);
      expect(requests, 1);
      expect(inserts, 0);
      expect(subject.submissionMessage, MaintenanceController.unknownMessage);
    });

    for (final invalidation in ['dispose', 'account event']) {
      test('late init after $invalidation rejects stale data', () async {
        final loaded = Completer<List<Map<String, dynamic>>>();
        var reads = 0;
        when(() => locations.getLocations()).thenAnswer((_) {
          reads++;
          return reads == 1 ? loaded.future : Future.value([{'id': 1, 'Address': 'Fresh location'}]);
        });
        var notifications = 0;
        subject.addListener(() { notifications++; });
        final initialization = subject.init();
        if (invalidation == 'dispose') { subject.disposeController(); }
        else { authEvents.add(true); }
        final before = notifications;
        loaded.complete([{'id': 1, 'Address': 'Stale location'}]);
        await initialization;
        if (invalidation == 'dispose') {
          expect(subject.locations, isEmpty);
          expect(notifications, before);
          expect(reads, 1);
        } else {
          expect(subject.locations, [(id: '1', address: 'Fresh location')]);
          expect(notifications, before + 1);
          expect(reads, 2);
        }
      });
    }

    group('initialization generations', () {
      tearDown(() {
        verifyNoMoreInteractions(edge);
        verifyNoMoreInteractions(storage);
      });

      for (final event in ['initial replay', 'token event', 'event burst']) {
        test('$event replaces a deferred read once without manual init', () async {
          final first = Completer<List<Map<String, dynamic>>>();
          final replacement = Completer<List<Map<String, dynamic>>>();
          var reads = 0;
          when(() => locations.getLocations()).thenAnswer((_) =>
              ++reads == 1 ? first.future : replacement.future);
          final draft = subject.draftKey;
          final initialization = subject.init();
          final generation = subject.generation;
          for (var i = 0; i < (event == 'event burst' ? 3 : 1); i++) {
            authEvents.add(true);
          }
          final loadingAfterEvent = subject.isLoading;
          expect(subject.isCurrent(generation), isFalse);
          expect(reads, 1);
          first.complete([{'id': 1, 'Address': 'Stale location'}]);
          await Future<void>.value();
          expect(subject.locations, isEmpty);
          final readsAfterStale = reads;
          final loadingAfterStale = subject.isLoading;
          replacement.complete([{'id': 1, 'Address': 'Fresh fixture location'}]);
          await initialization;
          expect(loadingAfterEvent, isTrue);
          expect(loadingAfterStale, isTrue);
          expect(readsAfterStale, 2);
          expect(reads, 2);
          expect(subject.locations, [(id: '1', address: 'Fresh fixture location')]);
          expect(subject.isLoading, isFalse);
          expect(subject.draftKey, same(draft));
          expect(subject.descriptionController.text, 'Original description');
        });
      }

      test('concurrent init callers share the read and its replacement', () async {
        final first = Completer<List<Map<String, dynamic>>>();
        final replacement = Completer<List<Map<String, dynamic>>>();
        var reads = 0;
        when(() => locations.getLocations()).thenAnswer((_) =>
            ++reads == 1 ? first.future : replacement.future);
        final initialization = subject.init();
        final joined = subject.init();
        final readsBeforeEvent = reads;
        authEvents.add(true);
        first.complete([{'id': 1, 'Address': 'Stale location'}]);
        await Future<void>.value();
        final joinedReplacement = subject.init();
        replacement.complete([{'id': 1, 'Address': 'Current location'}]);
        await Future.wait([initialization, joined, joinedReplacement]);
        expect(joined, same(initialization));
        expect(joinedReplacement, same(initialization));
        expect(readsBeforeEvent, 1);
        expect(reads, 2);
        expect(subject.locations, [(id: '1', address: 'Current location')]);
      });

      test('events during a replacement coalesce until that read settles', () async {
        final first = Completer<List<Map<String, dynamic>>>();
        final second = Completer<List<Map<String, dynamic>>>();
        final third = Completer<List<Map<String, dynamic>>>();
        final pending = [first, second, third];
        var reads = 0;
        when(() => locations.getLocations()).thenAnswer((_) => pending[reads++].future);
        final initialization = subject.init();
        authEvents.add(true);
        first.complete([{'id': 1, 'Address': 'First stale location'}]);
        await Future<void>.value();
        final beforeEvents = reads;
        authEvents.add(true);
        authEvents.add(true);
        final afterEvents = reads;
        second.complete([{'id': 1, 'Address': 'Second stale location'}]);
        await Future<void>.value();
        final beforeCurrent = reads;
        expect(subject.locations, isEmpty);
        third.complete([{'id': 1, 'Address': 'Current location'}]);
        await initialization;
        expect(beforeEvents, 2);
        expect(afterEvents, 2);
        expect(beforeCurrent, 3);
        expect(reads, 3);
        expect(subject.locations, [(id: '1', address: 'Current location')]);
        expect(subject.isLoading, isFalse);
      });

      for (final synchronous in [false, true]) {
        test('current ${synchronous ? 'synchronous' : 'async'} error does not retry', () async {
          if (synchronous) {
            when(() => locations.getLocations()).thenThrow(StateError('synthetic read failure'));
          } else {
            when(() => locations.getLocations()).thenAnswer((_) async => throw StateError('synthetic read failure'));
          }
          await subject.init();
          expect(subject.locations, isEmpty);
          expect(subject.isLoading, isFalse);
          authEvents.add(true);
          await Future<void>.value();
          verify(() => locations.getLocations()).called(1);
          when(() => locations.getLocations()).thenAnswer((_) async => [{'id': 1, 'Address': 'Explicit init'}]);
          await subject.init();
          expect(subject.locations, [(id: '1', address: 'Explicit init')]);
          verify(() => locations.getLocations()).called(1);
        });
      }

      test('an obsolete error is replaced but a current replacement error stops', () async {
        final first = Completer<List<Map<String, dynamic>>>();
        var reads = 0;
        when(() => locations.getLocations()).thenAnswer((_) => ++reads == 1
            ? first.future : Future.error(StateError('current read failure')));
        final initialization = subject.init();
        authEvents.addError(StateError('synthetic Auth stream failure'));
        first.completeError(StateError('obsolete read failure'));
        await initialization;
        expect(reads, 2);
        expect(subject.locations, isEmpty);
        expect(subject.isLoading, isFalse);
        expect(subject.descriptionController.text, 'Original description');
      });

      for (final transition in ['B', 'A-B-A', 'signout-login', 'queued bool A-B-A']) {
        test('$transition accepts only a fresh generation read', () async {
          final first = Completer<List<Map<String, dynamic>>>();
          final subjects = <String?>[];
          when(() => locations.getLocations()).thenAnswer((_) {
            subjects.add(currentUser);
            return subjects.length == 1 ? first.future : Future.value([{'id': 1, 'Address': 'Fresh location'}]);
          });
          final draft = subject.draftKey;
          final initialization = subject.init();
          final generation = subject.generation;
          if (transition == 'queued bool A-B-A') {
            // The bool events cannot reveal an identity already replaced in the getter.
            authEvents.add(true);
            authEvents.add(true);
          } else {
            currentUser = transition == 'signout-login' ? null : userB;
            authEvents.add(currentUser != null);
            if (transition != 'B') {
              currentUser = userA;
              authEvents.add(true);
            }
          }
          expect(subject.isCurrent(generation), isFalse);
          expect(subjects, [userA]);
          first.complete([{'id': 1, 'Address': 'Stale location'}]);
          await initialization;
          expect(subjects, [userA, transition == 'B' ? userB : userA]);
          expect(subject.locations, [(id: '1', address: 'Fresh location')]);
          expect(subject.isLoading, isFalse);
          if (transition == 'queued bool A-B-A') {
            expect(subject.draftKey, same(draft));
            expect(subject.descriptionController.text, 'Original description');
          } else {
            expect(subject.draftKey, isNot(same(draft)));
            expect(subject.descriptionController.text, isEmpty);
          }
        });
      }

      for (final stop in ['signout', 'false event before getter', 'unobserved B', 'dispose before continuation']) {
        test('$stop prevents a protected replacement read', () async {
          final first = Completer<List<Map<String, dynamic>>>();
          var reads = 0;
          when(() => locations.getLocations()).thenAnswer((_) { reads++; return first.future; });
          var notifications = 0;
          subject.addListener(() { notifications++; });
          final initialization = subject.init();
          authEvents.add(true);
          first.complete([{'id': 1, 'Address': 'Stale location'}]);
          if (stop == 'dispose before continuation') {
            subject.disposeController();
          } else if (stop == 'unobserved B') {
            currentUser = userB;
          } else {
            if (stop == 'signout') currentUser = null;
            authEvents.add(false);
          }
          final before = notifications;
          await initialization;
          await subject.init();
          expect(reads, 1);
          expect(subject.locations, isEmpty);
          expect(notifications, before);
          if (stop == 'signout' || stop == 'false event before getter') {
            expect(subject.isLoading, isFalse);
          }
        });
      }

      test('signed-out init and idle login events do not dispatch protected reads', () async {
        currentUser = null;
        authEvents.add(false);
        await subject.init();
        authEvents.add(false);
        currentUser = userA;
        authEvents.add(true);
        await Future<void>.value();
        verifyNever(() => locations.getLocations());
        when(() => locations.getLocations()).thenAnswer((_) async => [{'id': 1, 'Address': 'Explicit signed-in read'}]);
        await subject.init();
        expect(subject.locations, [(id: '1', address: 'Explicit signed-in read')]);
        authEvents.add(true);
        await Future<void>.value();
        verify(() => locations.getLocations()).called(1);
      });

      for (final stop in ['dispose', 'signout']) {
        test('$stop during replacement rejects its late result', () async {
          final first = Completer<List<Map<String, dynamic>>>();
          final replacement = Completer<List<Map<String, dynamic>>>();
          var reads = 0;
          when(() => locations.getLocations()).thenAnswer((_) =>
              ++reads == 1 ? first.future : replacement.future);
          var notifications = 0;
          subject.addListener(() { notifications++; });
          final initialization = subject.init();
          authEvents.add(true);
          first.complete([{'id': 1, 'Address': 'First stale location'}]);
          await Future<void>.value();
          final readsBeforeStop = reads;
          if (stop == 'dispose') { subject.disposeController(); }
          else { currentUser = null; authEvents.add(false); }
          final before = notifications;
          replacement.complete([{'id': 1, 'Address': 'Second stale location'}]);
          await initialization;
          expect(readsBeforeStop, 2);
          expect(reads, 2);
          expect(subject.locations, isEmpty);
          expect(notifications, before);
        });
      }
    });

    for (final omitImage in [false, true]) {
      test('photo acknowledgement ${omitImage ? 'cannot omit image_data' : 'matches the uploaded reference'}', () async {
        subject.selectedImage = _Photo();
        when(() => storage.upload(any(), any(), retryAttempts: 0)).thenAnswer((_) async => 'acknowledged');
        String? path;
        when(() => storage.getPublicUrl(any())).thenAnswer((call) {
          path = call.positionalArguments.first as String;
          return 'https://fixture.invalid/photo';
        });
        final record = row();
        if (omitImage) { record.remove('image_data'); }
        when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
            .thenAnswer((_) async {
              record['attachment_ref'] = {
                'bucket': 'maintenance-images', 'id': userA,
                'name': path, 'version': null,
              };
              return response(data: {'success': true, 'record': [record]});
            });
        expect(await subject.submitMaintenance(), !omitImage);
      });
    }

    test('an acknowledged path survives URL failure without uploading again', () async {
      subject.selectedImage = _Photo();
      when(() => storage.upload(any(), any(), retryAttempts: 0)).thenAnswer((_) async => 'acknowledged');
      when(() => storage.getPublicUrl(any())).thenThrow(StateError('synthetic URL error'));
      expect(await subject.submitMaintenance(), isFalse);
      when(() => storage.getPublicUrl(any())).thenReturn('https://fixture.invalid/photo');
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((_) async => null);
      expect(await subject.submitMaintenance(), isFalse);
      verify(() => storage.upload(any(), any(), retryAttempts: 0)).called(1);
      verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
    });

    for (final stage in ['source', 'permission', 'picker']) {
      for (final invalidation in ['dispose', 'auth event']) {
        for (final lateError in stage == 'source' ? [false] : [false, true]) {
        testWidgets('image $stage await rejects ${lateError ? 'error' : 'completion'} after $invalidation', (tester) async {
          const permissionChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
          const pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
          final permission = Completer<Map<int, int>>();
          final picked = Completer<String?>();
          var permissions = 0;
          var picks = 0;
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(permissionChannel, (_) {
            permissions++;
            return permission.future;
          });
          messenger.setMockMethodCallHandler(pickerChannel, (_) {
            picks++;
            return picked.future;
          });
          addTearDown(() {
            messenger.setMockMethodCallHandler(permissionChannel, null);
            messenger.setMockMethodCallHandler(pickerChannel, null);
          });
          late BuildContext context;
          await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
            context = value;
            return const Scaffold();
          })));
          final operation = subject.pickImage(context);
          await tester.pumpAndSettle();
          if (stage != 'source') {
            await tester.tap(find.text(stage == 'permission' ? 'Take Photo' : 'Choose from Library'));
            await tester.pumpAndSettle();
            expect(stage == 'permission' ? permissions : picks, 1);
          }
          if (invalidation == 'dispose') { subject.disposeController(); }
          else { authEvents.add(true); }
          if (stage == 'source') {
            await tester.tap(find.text('Take Photo'));
          } else if (stage == 'permission') {
            if (lateError) { permission.completeError(StateError('late permission error')); }
            else { permission.complete({1: 1}); }
          } else {
            if (lateError) { picked.completeError(StateError('late picker error')); }
            else { picked.complete('synthetic.jpg'); }
          }
          await tester.pumpAndSettle();
          await operation;
          expect(subject.selectedImage, isNull);
          expect(subject.submissionMessage, isNull);
          if (stage != 'picker') expect(picks, 0);
          if (stage == 'source') expect(permissions, 0);
          expect(tester.takeException(), isNull);
        });
        }
      }
    }

    test('acknowledged photo survives same-account events, never account replacement', () async {
      final photo = _Photo();
      subject.selectedImage = photo;
      when(() => storage.upload(any(), any(), retryAttempts: 0)).thenAnswer((_) async => 'acknowledged');
      when(() => storage.getPublicUrl(any())).thenReturn('https://fixture.invalid/photo');
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((_) async => null);
      expect(await subject.submitMaintenance(), isFalse);
      authEvents.add(true);
      expect(await subject.submitMaintenance(), isFalse);
      verify(() => storage.upload(any(), any(), retryAttempts: 0)).called(1);
      currentUser = userB;
      authEvents.add(true);
      expect(subject.selectedImage, isNull);
      subject.selectedImage = photo;
      subject.selectedCategory = 'Other';
      subject.selectedLocation = MaintenanceController.noApplicableLocation;
      subject.descriptionController.text = 'B draft';
      expect(await subject.submitMaintenance(), isFalse);
      verify(() => storage.upload(any(), any(), retryAttempts: 0)).called(1);
    });

    testWidgets('POST deadline starts after upload; upload does not imply submission', (tester) async {
      subject.selectedImage = _Photo();
      final upload = Completer<String>();
      final post = Completer<FunctionResponse?>();
      when(() => storage.upload(any(), any(), retryAttempts: 0)).thenAnswer((_) => upload.future);
      String? path;
      when(() => storage.getPublicUrl(any())).thenAnswer((call) {
        path = call.positionalArguments.first as String;
        return 'https://fixture.invalid/photo';
      });
      when(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')))
          .thenAnswer((_) => post.future);
      final operation = subject.submitMaintenance();
      await tester.pump(const Duration(seconds: 21));
      expect(subject.isLoading, isTrue);
      verifyNever(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')));
      upload.complete('acknowledged');
      await tester.pump();
      await tester.pump(const Duration(seconds: 19));
      expect(subject.isLoading, isTrue);
      final record = row()..['attachment_ref'] = {
        'bucket': 'maintenance-images', 'id': userA,
        'name': path, 'version': null,
      };
      post.complete(response(data: {'success': true, 'record': [record]}));
      await tester.pump();
      expect(await operation, isTrue);
      verify(() => edge.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body'))).called(1);
    });
  });
}
