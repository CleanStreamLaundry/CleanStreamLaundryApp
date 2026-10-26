import 'dart:convert';

import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockAdmissionAuthService extends Mock implements AuthService {}

class MockAdmissionProfileService extends Mock implements ProfileService {}

const accountA = '11111111-1111-1111-1111-111111111111';
const accountB = '22222222-2222-2222-2222-222222222222';

Session admissionSession({
  required DateTime expiresAt,
  String id = accountA,
  String revision = 'initial',
}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return Session(
    accessToken:
        '${part({'alg': 'HS256'})}.${part({'sub': id, 'exp': expiresAt.millisecondsSinceEpoch ~/ 1000, 'synthetic_revision': revision})}.synthetic',
    tokenType: 'bearer',
    refreshToken: 'synthetic-refresh',
    user: User(
      id: id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '',
    ),
  );
}

AdmissionStatus admissionStatus({
  String id = accountA,
  String step = 'home',
  String? reason,
}) => AdmissionStatus.fromJson({
  'subject_id': id,
  'account_access': const ['home', 'review_terms'].contains(step)
      ? 'eligible'
      : 'restricted',
  'next_step': step,
  'reason': reason,
  'account_state': reason == 'account_restricted' ? 'blocked' : 'legacy_active',
  'restore_until': null,
});
