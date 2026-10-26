import 'package:clean_stream_laundry_app/features/maintenance_request/controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class LocationSelector extends StatelessWidget {
  final MaintenanceController controller;

  const LocationSelector({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.fontSecondary, width: 1.5),
        color: colorScheme.surface,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showLocationPicker(context),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  controller.selectedLocation?.address ?? 'Select Location',
                  style: TextStyle(
                    letterSpacing: 0,
                    fontSize: 16,
                    color: controller.selectedLocation == null
                        ? colorScheme.fontSecondary
                        : colorScheme.fontInverted,
                  ),
                ),
              ),
            ),
          ),
          const Icon(Icons.arrow_drop_down, color: Colors.grey),
        ],
      ),
    );
  }

  void _showLocationPicker(BuildContext context) {
    final generation = controller.generation;
    final locations = List<MaintenanceLocation>.of(controller.locations);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (_) => ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: locations.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          if (index == 0) {
            return ListTile(
              title: const Text(
                'No Applicable Location',
                style: TextStyle(
                  letterSpacing: 0,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
              onTap: () {
                if (controller.isCurrent(generation)) {
                  controller.selectLocation(
                    MaintenanceController.noApplicableLocation,
                  );
                }
                Navigator.pop(context);
              },
            );
          }
          final item = locations[index - 1];

          return ListTile(
            title: Text(item.address),
            subtitle: Text('Location ${item.id}'),
            onTap: () {
              if (controller.isCurrent(generation))
                controller.selectLocation(item);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}
