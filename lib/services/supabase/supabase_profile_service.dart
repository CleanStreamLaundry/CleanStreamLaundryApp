import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_action_context.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProfileService extends ProfileService {
  late final SupabaseClient _client;
  final PostgrestClient Function()? _publicPolicyClientFactory;

  SupabaseProfileService({
    required SupabaseClient client,
    PostgrestClient Function()? publicPolicyClientFactory,
  }) : _publicPolicyClientFactory = publicPolicyClientFactory {
    _client = client;
  }

  @override
  Future<NewsletterStatus> getNewsletterStatus() => _newsletter('status');

  @override
  Future<NewsletterStatus> requestNewsletter(String version) =>
      _newsletter('request', version: version);

  @override
  Future<NewsletterStatus> withdrawNewsletter() => _newsletter('withdraw');

  Future<NewsletterStatus> _newsletter(String action, {String? version}) async {
    final session = _client.auth.currentSession;
    final bearer = _currentBearer(expectedUserId: session?.user.id);
    var changed = false;
    var firstEvent = true;
    final subscription = _client.auth.onAuthStateChange.listen(
      (state) {
        // Auth replays its latest event to each new subscriber.
        if (!firstEvent || !identical(state.session, session)) changed = true;
        firstEvent = false;
      },
      onError: (Object _) => changed = true,
      onDone: () => changed = true,
    );
    final Object? response;
    try {
      final result = await _client.functions
          .invoke(
            'newsletter',
            headers: {'Authorization': bearer},
            body: {
              'action': action,
              if (action == 'request') ...{
                'opt_in': true,
                'version': version,
                'source': 'settings',
              },
            },
          )
          .timeout(const Duration(seconds: 10));
      if (result.status != 200) {
        throw StateError('Newsletter request unavailable');
      }
      response = result.data;
    } finally {
      await subscription.cancel();
    }
    if (changed ||
        !identical(session, _client.auth.currentSession) ||
        session!.isExpired ||
        session.user.id != _client.auth.currentUser?.id) {
      throw StateError('The newsletter session changed');
    }
    final status = NewsletterStatus.fromJson(response);
    if (status.subjectId != session.user.id) {
      throw const FormatException('Newsletter subject mismatch');
    }
    return status;
  }

  @override
  Future<AdmissionStatus> getAdmissionStatus() async {
    final bearer = _currentBearer();
    final response = await _client
        .rpc('get_admission_status')
        .setHeader('Authorization', bearer)
        .timeout(const Duration(seconds: 10));
    return AdmissionStatus.fromJson(response);
  }

  @override
  Future<AdmissionStatus> requestAccountDeletion({Map<String, dynamic>? consent}) =>
      _changeLifecycle(
        'request_account_deletion_with_consent', 'pending_deletion',
        params: {
          'p_context_id': consent?['context_id'],
          'p_acknowledged': consent?['acknowledged'] == true,
        },
      );

  @override
  Future<LoyaltyActionContext> getLoyaltyActionContext(String action) async {
    final session = _client.auth.currentSession;
    final bearer = _currentBearer(expectedUserId: session?.user.id);
    final response = await _client.rpc('get_loyalty_action_context',
      params: {'p_action': action},
    ).setHeader('Authorization', bearer).timeout(const Duration(seconds: 10));
    final result = LoyaltyActionContext.fromJson(response);
    if (!identical(session, _client.auth.currentSession) ||
        session == null || session.isExpired ||
        result.subjectId != session.user.id || result.action != action) {
      throw StateError('The account or consent details changed');
    }
    return result;
  }

  @override
  Future<AdmissionStatus> restoreAccount() =>
      _changeLifecycle('restore_account', 'legacy_active');

  Future<AdmissionStatus> _changeLifecycle(
    String rpc,
    String expectedState, {
    Map<String, dynamic>? params,
  }) async {
    final session = _client.auth.currentSession;
    final bearer = _currentBearer(expectedUserId: session?.user.id);
    final response = await _client
        .rpc(rpc, params: params)
        .setHeader('Authorization', bearer)
        .timeout(const Duration(seconds: 10));
    final status = AdmissionStatus.fromJson(response);
    if (!identical(session, _client.auth.currentSession) ||
        session!.expiresAt == null ||
        session.isExpired) {
      throw StateError('The account session changed during the request');
    }
    if (status.subjectId != session.user.id ||
        status.accountState != expectedState) {
      throw const FormatException('Account lifecycle acknowledgement mismatch');
    }
    return status;
  }

  @override
  Future<LoyaltyPolicyDescriptor> getLoyaltyPolicyDescriptor() async {
    final client = _publicPolicyClientFactory?.call();
    if (client == null) {
      throw StateError('Public policy client is not configured');
    }
    try {
      final response = await client
          .rpc('get_loyalty_policy_descriptor')
          .timeout(const Duration(seconds: 10));
      return LoyaltyPolicyDescriptor.fromJson(response);
    } finally {
      await client.dispose();
    }
  }

  @override
  Future<LoyaltyPolicyStatus> getLoyaltyPolicyStatus() async {
    final bearer = _currentBearer();
    final response = await _client
        .rpc('get_loyalty_policy_status')
        .setHeader('Authorization', bearer)
        .timeout(const Duration(seconds: 10));
    return LoyaltyPolicyStatus.fromJson(response);
  }

  @override
  Future<LoyaltyPolicyStatus> acceptLoyaltyPolicy(String version) async {
    final bearer = _currentBearer();
    final response = await _client
        .rpc('accept_loyalty_policy', params: {'p_version': version})
        .setHeader('Authorization', bearer)
        .timeout(const Duration(seconds: 10));
    return LoyaltyPolicyStatus.fromJson(response);
  }

  @override
  Future<void> createAccount({required String id, required String name}) async {
    final bearer = _currentBearer(expectedUserId: id);
    await _client
        .rpc('ensure_own_profile', params: {'p_full_name': name})
        .setHeader('Authorization', bearer)
        .timeout(const Duration(seconds: 10));
  }

  String _currentBearer({String? expectedUserId}) {
    final auth = _client.auth;
    final session = auth.currentSession;
    final userId = expectedUserId ?? auth.currentUser?.id;
    if (userId == null ||
        userId.isEmpty ||
        session == null ||
        session.user.id != userId ||
        session.accessToken.isEmpty ||
        session.expiresAt == null ||
        session.isExpired) {
      throw StateError('A current matching session is required');
    }
    // Keep the captured identity even if SDK refresh awaits an account change.
    return 'Bearer ${session.accessToken}';
  }

  @override
  Future<Map<String, dynamic>?> getUserBalanceById(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select("full_name, balance, reward_tracker")
          .eq('id', userId)
          .single();
      return response;
    } on PostgrestException {
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> updateName(String name) async {
    final userId = _client.auth.currentUser?.id;

    if (userId == null) {
      throw Exception('No user logged in');
    }

    try {
      await _client
          .from('profiles')
          .update({"full_name": name})
          .eq('id', userId);
    } catch (e) {
      throw Exception('Failed to update name: $e');
    }
  }

  @override
  Future<void> updateBalanceById(String userId, double balance) async {
    try {
      await _client
          .from("profiles")
          .update({"balance": balance})
          .eq("id", userId);
    } on PostgrestException {
      return;
    } catch (e) {
      return;
    }
  }

  @override
  Future<void> updateRewardsById(String userId, double amount) async {
    try {
      await _client
          .from("profiles")
          .update({"reward_tracker": amount})
          .eq("id", userId);
    } on PostgrestException {
      return;
    } catch (e) {
      return;
    }
  }

  @override
  Future<String?> getUserNameById(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select("full_name")
          .eq('id', userId)
          .single();
      return response["full_name"];
    } on PostgrestException {
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<String?> getCurrentUserRole() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final response = await _client
          .from('profiles')
          .select('roles')
          .eq('id', userId)
          .single();
      return response['roles'] as String?;
    } on PostgrestException {
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<String?> getUserRefundAttempts(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select("refund_attempts")
          .eq('id', userId)
          .single();
      return response["refund_attempts"].toString();
    } on PostgrestException {
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<int> getNotificationLeadTime() async {
    final user = _client.auth.currentUser;
    if (user == null) return 5;

    try {
      final response = await _client
          .from('profiles')
          .select('notif_lead_time')
          .eq('id', user.id)
          .maybeSingle();

      final value = response?['notif_lead_time'];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 5;
    } on PostgrestException {
      return 5;
    } catch (_) {
      return 5;
    }
  }

  @override
  Future<void> setNotificationLeadTime(int value) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client
        .from('profiles')
        .update({'notif_lead_time': value})
        .eq('id', user.id);
  }
}
