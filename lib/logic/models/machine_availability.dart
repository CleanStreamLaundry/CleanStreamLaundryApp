class MachineAvailabilityCount {
  final int total;
  final int available;
  final int busy;
  final int unknown;

  const MachineAvailabilityCount({
    required this.total,
    required this.available,
    required this.busy,
    required this.unknown,
  });

  factory MachineAvailabilityCount.fromJson(Map<String, dynamic> json) {
    final values = [
      'total',
      'available',
      'busy',
      'unknown',
    ].map((key) => json[key]).toList();
    if (values.any((value) => value is! int || value < 0) ||
        values[0] != values[1] + values[2] + values[3]) {
      throw const FormatException('Invalid availability counts');
    }
    return MachineAvailabilityCount(
      total: values[0],
      available: values[1],
      busy: values[2],
      unknown: values[3],
    );
  }

  int? get displayedAvailable =>
      total > 0 && unknown == total ? null : available;
}

class MachineAvailability {
  final MachineAvailabilityCount washers;
  final MachineAvailabilityCount dryers;
  final DateTime? checkedAt;
  final bool configured;

  const MachineAvailability({
    required this.washers,
    required this.dryers,
    required this.checkedAt,
    required this.configured,
  });

  factory MachineAvailability.fromJson(Map<String, dynamic> json) =>
      MachineAvailability(
        washers: MachineAvailabilityCount.fromJson(
          Map<String, dynamic>.from(json['washers'] as Map),
        ),
        dryers: MachineAvailabilityCount.fromJson(
          Map<String, dynamic>.from(json['dryers'] as Map),
        ),
        checkedAt: DateTime.tryParse(
          json['checkedAt'] as String? ?? '',
        )?.toLocal(),
        configured: json['configured'] == true,
      );

  int get unknown => washers.unknown + dryers.unknown;
}
