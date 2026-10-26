import 'package:clean_stream_laundry_app/features/home/widgets/map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets(
    'remount with retained controller centers the selected location',
    (tester) async {
      final controller = MapController();
      final events = <MapEvent>[];
      final subscription = controller.mapEventStream.listen(events.add);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationMap(
              key: const ValueKey('loading-layout'),
              locations: const [],
              mapController: controller,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationMap(
              key: const ValueKey('selected-layout'),
              height: 118,
              locations: const [],
              mapController: controller,
              selectedLocation: const LatLng(40.06415, -85.66733),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controller.camera.center, const LatLng(40.06415, -85.66733));
      expect(controller.camera.zoom, 15);
      expect(events.last.camera.center, controller.camera.center);
      expect(events.last.camera.zoom, controller.camera.zoom);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await subscription.cancel();
        controller.dispose();
      });
    },
  );

  testWidgets('camera follows asynchronous selection changes on the same map', (
    tester,
  ) async {
    final controller = MapController();
    Future<void> show(LatLng? selected) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationMap(
              locations: const [],
              mapController: controller,
              selectedLocation: selected,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await show(null);
    await show(const LatLng(40, -86));
    expect(controller.camera.center, const LatLng(40, -86));
    await show(const LatLng(41, -87));
    expect(controller.camera.center, const LatLng(41, -87));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
