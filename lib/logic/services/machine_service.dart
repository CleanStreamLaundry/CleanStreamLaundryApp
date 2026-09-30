import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';

abstract class MachineService {
  Future<MachineAvailability> getAvailability(int locationId);
  Future<Map<String, dynamic>?> getMachineById(String machineId);
  Future<int> getIdleWasherCountByLocation(String locationId);
  Future<int> getIdleDryerCountByLocation(String locationId);
  Future<int> getWasherCountByLocation(String locationId);
  Future<int> getDryerCountByLocation(String locationId);
}
