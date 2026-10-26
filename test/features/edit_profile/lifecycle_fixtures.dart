import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const callerId = '11111111-1111-4111-8111-111111111111';

Session callerSession({
  String id = callerId,
  String token = 'token-a',
  int? expiry,
}) =>
    Session(
        accessToken: token,
        tokenType: 'bearer',
        user: User(
          id: id,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '',
        ),
      )
      ..expiresAt =
          expiry ??
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000;

AdmissionStatus lifecycleStatus({bool pending = true, String id = callerId}) =>
    AdmissionStatus.fromJson({
      'subject_id': id,
      'account_access': pending ? 'restricted' : 'eligible',
      'next_step': pending ? 'blocked' : 'home',
      'reason': pending ? 'explicit_restore_required' : null,
      'account_state': pending ? 'pending_deletion' : 'legacy_active',
      'restore_until': pending ? '2026-12-29T12:34:56Z' : null,
    });
