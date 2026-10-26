import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_action_context.dart';

abstract class ProfileService {
  Future<NewsletterStatus> getNewsletterStatus();
  Future<NewsletterStatus> requestNewsletter(String version);
  Future<NewsletterStatus> withdrawNewsletter();
  Future<AdmissionStatus> getAdmissionStatus();
  Future<AdmissionStatus> requestAccountDeletion({Map<String, dynamic>? consent});
  Future<LoyaltyActionContext> getLoyaltyActionContext(String action);
  Future<AdmissionStatus> restoreAccount();
  Future<LoyaltyPolicyDescriptor> getLoyaltyPolicyDescriptor();
  Future<LoyaltyPolicyStatus> getLoyaltyPolicyStatus();
  Future<LoyaltyPolicyStatus> acceptLoyaltyPolicy(String version);
  Future<void> createAccount({required String id, required String name});
  Future<Map<String, dynamic>?> getUserBalanceById(String userId);
  Future<void> updateBalanceById(String userId, double balance);
  Future<String?> getUserNameById(String userId);
  Future<String?> getCurrentUserRole();
  Future<String?> getUserRefundAttempts(String userId);
  Future<void> updateName(String name);
  Future<int> getNotificationLeadTime();
  Future<void> setNotificationLeadTime(int value);
  Future<void> updateRewardsById(String userId, double amount);
}
