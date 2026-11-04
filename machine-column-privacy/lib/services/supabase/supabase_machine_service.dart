import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';

class SupabaseMachineService extends MachineService {
  late final SupabaseClient _client;

  SupabaseMachineService({required SupabaseClient client}) {
    _client = client;
  }

  @override
  Future<MachineAvailability> getAvailability(int locationId) async {
    final response = await _client.functions
        .invoke('machine-availability', body: {'locationId': locationId})
        .timeout(const Duration(seconds: 24));
    if (response.status != 200 || response.data is! Map) {
      throw StateError('Unable to check machine availability');
    }
    return MachineAvailability.fromJson(
      Map<String, dynamic>.from(response.data),
    );
  }

  @override
  Future<int> getDryerCountByLocation(String locationId) async {
    try {
      final response = await _client
          .from('Machines')
          .select('id')
          .eq('Location_ID', locationId)
          .eq('Machine_type', 'Dryer')
          .count(CountOption.exact);

      return response.count;
    } on PostgrestException {
      return 0;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<int> getIdleDryerCountByLocation(String locationId) async {
    try {
      final response = await _client
          .from('Machines')
          .select('id')
          .eq('Location_ID', locationId)
          .eq('Status', 'idle')
          .eq('Machine_type', 'Dryer')
          .count(CountOption.exact);

      return response.count;
    } on PostgrestException {
      return 0;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<int> getIdleWasherCountByLocation(String locationId) async {
    try {
      final response = await _client
          .from('Machines')
          .select('id')
          .eq('Location_ID', locationId)
          .eq('Status', 'idle')
          .eq('Machine_type', 'Washer')
          .count(CountOption.exact);

      return response.count;
    } on PostgrestException {
      return 0;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<Map<String, dynamic>?> getMachineById(String machineId) async {
    try {
      final response = await _client
          .from('Machines')
          .select("Name, Price")
          .eq('id', machineId)
          .single();
      return response;
    } on PostgrestException {
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<int> getWasherCountByLocation(String locationId) async {
    try {
      final response = await _client
          .from('Machines')
          .select('id')
          .eq('Location_ID', locationId)
          .eq('Machine_type', 'Washer')
          .count(CountOption.exact);

      return response.count;
    } on PostgrestException {
      return 0;
    } catch (e) {
      return 0;
    }
  }
}
