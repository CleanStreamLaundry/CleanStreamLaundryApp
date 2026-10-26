import 'dart:io';
import 'package:clean_stream_laundry_app/features/maintenance_request/widgets/maintenance_form.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/controller.dart';
import 'package:flutter/material.dart';
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

    when(
      () => controller.categories,
    ).thenReturn(['Electrical', 'Washer', 'Dryer']);
    when(() => controller.selectedCategory).thenReturn(null);
    when(
      () => controller.descriptionController,
    ).thenReturn(TextEditingController());
    when(() => controller.selectedImage).thenReturn(null);
    when(() => controller.attemptedSubmit).thenReturn(false);
    when(() => controller.isFormValid).thenReturn(true);
    when(() => controller.locations).thenReturn([
      (id: '1', address: '123 Main St'),
      (id: '2', address: '456 Oak Ave'),
    ]);
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

  testWidgets('unframed form reflows validation and photo prompt at 2x', (
    tester,
  ) async {
    when(() => controller.attemptedSubmit).thenReturn(true);
    when(() => controller.isFormValid).thenReturn(false);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            boldText: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 280,
                child: MaintenanceForm(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Card), findsNothing);
    expect(find.text('Please fill in all fields'), findsOneWidget);
    expect(find.text('Tap to take or upload a photo'), findsOneWidget);
  });

  testWidgets('Dropdown shows categories and triggers selection', (
    tester,
  ) async {
    await tester.pumpWidget(buildForm());

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('Electrical'), findsOneWidget);
    await tester.tap(find.text('Washer').last);
    await tester.pumpAndSettle();

    verify(() => controller.selectCategory('Washer')).called(1);
  });

  testWidgets('LocationSelector opens bottom sheet and shows options', (
    tester,
  ) async {
    await tester.pumpWidget(buildForm());

    await tester.tap(find.text('Select Location'));
    await tester.pumpAndSettle();

    expect(find.text('No Applicable Location'), findsOneWidget);
    expect(find.text('123 Main St'), findsOneWidget);
    verifyNever(() => controller.selectLocation(any()));
  });

  testWidgets('Selecting a location calls controller.selectLocation', (
    tester,
  ) async {
    await tester.pumpWidget(buildForm());

    await tester.tap(find.text('Select Location'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('123 Main St'));
    await tester.pumpAndSettle();

    verify(
      () => controller.selectLocation((id: '1', address: '123 Main St')),
    ).called(1);
  });

  testWidgets('Typing in description updates controller', (tester) async {
    final textController = TextEditingController();
    when(() => controller.descriptionController).thenReturn(textController);

    await tester.pumpWidget(buildForm());
    await tester.enterText(find.byType(TextField), 'Test description');
    expect(textController.text, 'Test description');
  });

  testWidgets('Shows image preview when selectedImage is present', (
    tester,
  ) async {
    final fakeFile = File('fake_path.jpg');
    when(() => controller.selectedImage).thenReturn(fakeFile);

    await tester.pumpWidget(buildForm());
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('Shows error message when form invalid and attemptedSubmit', (
    tester,
  ) async {
    when(() => controller.attemptedSubmit).thenReturn(true);
    when(() => controller.isFormValid).thenReturn(false);

    await tester.pumpWidget(buildForm());

    expect(find.text('Please fill in all fields'), findsOneWidget);
  });

  testWidgets('Tapping image picker calls controller.pickImage', (
    tester,
  ) async {
    await tester.pumpWidget(buildForm());
    await tester.tap(find.text('Tap to take or upload a photo'));
    await tester.pump();

    verify(() => controller.pickImage(any())).called(1);
  });
}
