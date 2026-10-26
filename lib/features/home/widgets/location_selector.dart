import 'package:clean_stream_laundry_app/features/home/controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class LocationSelector extends StatelessWidget {
  final HomePageController controller;
  final VoidCallback onGetDirections;
  final VoidCallback? onNearestLocationTap;

  const LocationSelector({
    super.key,
    required this.controller,
    required this.onGetDirections,
    this.onNearestLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedLocation = _selectedLocation;
    final locationHours = _LocationHours.fromLocation(selectedLocation);
    final locationDisplay = _LocationDisplay.fromLocation(
      selectedLocation,
      selectedAddress: controller.locationSelected
          ? controller.selectedName
          : null,
    );

    return Card(
      elevation: 5,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      color: colorScheme.homeCard,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.homeAccent.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colorScheme.homeAccent.withValues(
                    alpha: 0.10,
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: colorScheme.homeAccent,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: InkWell(
                    onTap: () => _showLocationSheet(context),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.isNearestSelection
                                ? 'Nearest location'
                                : 'Selected location',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.homeAccent,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            locationDisplay.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: controller.selectedName == null
                                  ? (colorScheme.brightness == Brightness.dark
                                        ? colorScheme.fontSecondary
                                        : Colors.grey.shade600)
                                  : colorScheme.fontInverted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Visibility(
                            visible: locationDisplay.subtitle != null,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 15,
                                  color: colorScheme.fontSecondary,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    locationDisplay.subtitle ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: colorScheme.fontSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                _DirectionsAction(onPressed: onGetDirections),
              ],
            ),
            Divider(
              height: 16,
              thickness: 1,
              color: Colors.grey.withValues(alpha: 0.24),
            ),
            InkWell(
              key: const ValueKey('home-location-details-button'),
              onTap: () => _showLocationSheet(context),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 17,
                      color: colorScheme.fontSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      locationHours.statusLabel,
                      style: TextStyle(
                        color: locationHours.isOpen
                            ? (colorScheme.brightness == Brightness.dark
                                  ? Colors.green.shade300
                                  : Colors.green.shade700)
                            : (colorScheme.brightness == Brightness.dark
                                  ? Colors.red.shade300
                                  : Colors.red.shade700),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      color: Colors.grey.withValues(alpha: 0.24),
                    ),
                    Expanded(
                      child: Text(
                        locationHours.hoursLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.fontSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: colorScheme.fontSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final selectedLocation = _selectedLocation;
        final selectedDisplay = _LocationDisplay.fromLocation(
          selectedLocation,
          selectedAddress: controller.locationSelected
              ? controller.selectedName
              : null,
        );
        final selectedHours = _LocationHours.fromLocation(selectedLocation);
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.78;

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              children: [
                Text(
                  selectedLocation == null
                      ? 'Select Location'
                      : 'Location details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(sheetContext).colorScheme.fontInverted,
                  ),
                ),
                const SizedBox(height: 12),
                if (selectedLocation != null) ...[
                  _LocationDetailsPanel(
                    display: selectedDisplay,
                    hours: selectedHours,
                  ),
                  const SizedBox(height: 14),
                ],
                if (onNearestLocationTap != null)
                  ListTile(
                    key: const ValueKey('home-nearest-location-button'),
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        sheetContext,
                      ).colorScheme.homeAccent.withValues(alpha: 0.10),
                      child: Icon(
                        Icons.my_location_rounded,
                        color: Theme.of(sheetContext).colorScheme.homeAccent,
                      ),
                    ),
                    title: const Text('Use nearest location'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onNearestLocationTap?.call();
                    },
                  ),
                if (onNearestLocationTap != null) const Divider(height: 18),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Change location',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(sheetContext).colorScheme.homeAccent,
                    ),
                  ),
                ),
                if (controller.locations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No locations available',
                      style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.fontSecondary,
                      ),
                    ),
                  )
                else
                  for (final item in controller.locations)
                    _LocationChoiceTile(
                      location: item,
                      selectedId: controller.locationIDSelected,
                      onSelected: (address) {
                        controller.selectLocation(
                          address,
                          locationId: item['id'] as int?,
                        );
                        Navigator.pop(sheetContext);
                      },
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, dynamic>? get _selectedLocation {
    return controller.selectedLocation;
  }
}

class _DirectionsAction extends StatelessWidget {
  final VoidCallback onPressed;

  const _DirectionsAction({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      key: const ValueKey('home-directions-button'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(36),
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colorScheme.homeCard,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.withValues(alpha: 0.22)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                Icons.navigation,
                color: colorScheme.homeAccent,
                size: 27,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Directions',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.homeAccent,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationDetailsPanel extends StatelessWidget {
  final _LocationDisplay display;
  final _LocationHours hours;

  const _LocationDetailsPanel({required this.display, required this.hours});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.homeCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.homeAccent.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            display.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: colorScheme.fontInverted,
            ),
          ),
          if (display.address != null && display.address != display.title) ...[
            const SizedBox(height: 8),
            _LocationMetaRow(
              icon: Icons.place_outlined,
              text: display.address!,
            ),
          ],
          const SizedBox(height: 8),
          _LocationMetaRow(
            icon: Icons.schedule_rounded,
            text: '${hours.statusLabel} - ${hours.hoursLabel}',
            color: hours.isOpen
                ? (colorScheme.brightness == Brightness.dark
                      ? Colors.green.shade300
                      : Colors.green.shade700)
                : (colorScheme.brightness == Brightness.dark
                      ? Colors.red.shade300
                      : Colors.red.shade700),
          ),
          if (hours.afterHoursAvailable) ...[
            const SizedBox(height: 8),
            const _LocationMetaRow(
              icon: Icons.lock_open_rounded,
              text: 'After-hours access available',
            ),
          ],
          if (display.details != null) ...[
            const SizedBox(height: 8),
            _LocationMetaRow(
              icon: Icons.info_outline_rounded,
              text: display.details!,
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationChoiceTile extends StatelessWidget {
  final Map<String, dynamic> location;
  final int? selectedId;
  final ValueChanged<String> onSelected;

  const _LocationChoiceTile({
    required this.location,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final display = _LocationDisplay.fromLocation(location);
    final hours = _LocationHours.fromLocation(location);
    final address = display.address;
    final isSelected = selectedId != null && location['id'] == selectedId;
    final subtitle = display.address == null || display.address == display.title
        ? hours.hoursLabel
        : '${display.address} - ${hours.hoursLabel}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.location_on_outlined),
      title: Text(
        display.title,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).colorScheme.fontInverted,
        ),
      ),
      subtitle: Text(subtitle, overflow: TextOverflow.ellipsis, maxLines: 1),
      trailing: isSelected
          ? Icon(
              Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.homeAccent,
            )
          : null,
      onTap: address == null ? null : () => onSelected(address),
    );
  }
}

class _LocationMetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _LocationMetaRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Theme.of(context).colorScheme.fontSecondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: textColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationDisplay {
  final String title;
  final String? address;
  final String? subtitle;
  final String? details;

  const _LocationDisplay({
    required this.title,
    required this.address,
    required this.subtitle,
    required this.details,
  });

  factory _LocationDisplay.fromLocation(
    Map<String, dynamic>? location, {
    String? selectedAddress,
  }) {
    final address =
        _readString(location, const ['Address', 'address']) ?? selectedAddress;
    final name = _readString(location, const [
      'Name',
      'name',
      'LocationName',
      'location_name',
      'BusinessName',
      'business_name',
    ]);
    final title = name ?? address ?? 'Select Location';
    final details = _readString(location, const ['Details', 'details']);
    final distance = _distanceLabel(location);
    final subtitle = distance ?? (name == null ? null : address);

    return _LocationDisplay(
      title: title,
      address: address,
      subtitle: subtitle,
      details: details,
    );
  }

  static String? _distanceLabel(Map<String, dynamic>? location) {
    final explicit = _readString(location, const [
      'Distance',
      'distance',
      'DistanceLabel',
      'distance_label',
    ]);
    if (explicit != null) return explicit;

    final miles = _readDouble(location, const [
      'DistanceMiles',
      'distance_miles',
    ]);
    if (miles != null) return '${miles.toStringAsFixed(1)} mi away';

    final meters = _readDouble(location, const [
      'DistanceMeters',
      'distance_meters',
    ]);
    if (meters != null) {
      final convertedMiles = meters / 1609.344;
      return '${convertedMiles.toStringAsFixed(1)} mi away';
    }

    return null;
  }
}

class _LocationHours {
  final bool isOpen;
  final String statusLabel;
  final String hoursLabel;
  final bool afterHoursAvailable;

  const _LocationHours({
    required this.isOpen,
    required this.statusLabel,
    required this.hoursLabel,
    required this.afterHoursAvailable,
  });

  factory _LocationHours.fromLocation(Map<String, dynamic>? location) {
    const defaultOpenHour = 6;
    const defaultCloseHour = 22;
    final openHour =
        _readInt(location, const ['OpenHour', 'open_hour']) ?? defaultOpenHour;
    final closeHour =
        _readInt(location, const ['CloseHour', 'close_hour']) ??
        defaultCloseHour;
    final hoursLabel =
        _readString(location, const [
          'Hours',
          'hours',
          'BusinessHours',
          'business_hours',
        ]) ??
        _formatHours(openHour, closeHour);
    final isOpen =
        _readBool(location, const [
          'IsOpen',
          'is_open',
          'OpenNow',
          'open_now',
        ]) ??
        _isWithinHours(openHour, closeHour);
    final afterHoursAvailable =
        _readBool(location, const [
          'AfterHoursAvailable',
          'after_hours_available',
          'AfterHours',
          'after_hours',
        ]) ??
        false;

    return _LocationHours(
      isOpen: isOpen,
      statusLabel: isOpen ? 'Open now' : 'Closed',
      hoursLabel: hoursLabel,
      afterHoursAvailable: afterHoursAvailable,
    );
  }

  static bool _isWithinHours(int openHour, int closeHour) {
    final now = DateTime.now();
    final normalizedOpen = openHour % 24;
    final normalizedClose = closeHour % 24;

    if (normalizedOpen == normalizedClose) return true;
    if (normalizedOpen < normalizedClose) {
      return now.hour >= normalizedOpen && now.hour < normalizedClose;
    }
    return now.hour >= normalizedOpen || now.hour < normalizedClose;
  }

  static String _formatHours(int openHour, int closeHour) {
    return '${_formatHour(openHour)} - ${_formatHour(closeHour)}';
  }

  static String _formatHour(int hour) {
    final normalized = hour % 24;
    final displayHour = normalized % 12 == 0 ? 12 : normalized % 12;
    final period = normalized >= 12 ? 'PM' : 'AM';
    return '$displayHour:00 $period';
  }
}

String? _readString(Map<String, dynamic>? location, List<String> keys) {
  if (location == null) return null;

  for (final key in keys) {
    final value = location[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }

  return null;
}

bool? _readBool(Map<String, dynamic>? location, List<String> keys) {
  if (location == null) return null;

  for (final key in keys) {
    final value = location[key];
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes') return true;
      if (normalized == 'false' || normalized == 'no') return false;
    }
  }

  return null;
}

int? _readInt(Map<String, dynamic>? location, List<String> keys) {
  if (location == null) return null;

  for (final key in keys) {
    final value = location[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
  }

  return null;
}

double? _readDouble(Map<String, dynamic>? location, List<String> keys) {
  if (location == null) return null;

  for (final key in keys) {
    final value = location[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
  }

  return null;
}
