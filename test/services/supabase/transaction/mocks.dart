import 'dart:async';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class SupabaseMock extends Mock implements SupabaseClient {}
class GoTrueMock extends Mock implements GoTrueClient {}

class FakeCreditResponse extends Fake implements PostgrestFilterBuilder<dynamic> {
  FakeCreditResponse({this.error, this.receipt = const {
    'amount': 4, 'refund_id': 9, 'status': 'pending',
  }});

  final Object? error;
  final Object? receipt;

  @override
  Future<U> then<U>(
    FutureOr<U> Function(dynamic) onValue, {
    Function? onError,
  }) {
    final response = error == null
        ? Future<dynamic>.value(receipt)
        : Future<dynamic>.error(error!);
    return response.then(onValue, onError: onError);
  }
}

class QueryBuilderMock extends Mock implements SupabaseQueryBuilder {

  @override
  PostgrestFilterBuilder<dynamic> insert(Object values, {bool defaultToNull = false}) {
    return FakeFilterBuilder([{'status': 'success', 'inserted': values}]);
  }

}

class FakeFilterBuilder extends Fake implements PostgrestFilterBuilder<PostgrestList> {
  final List<Map<String, dynamic>> fakeData;

  FakeFilterBuilder(this.fakeData);

  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestList) onValue, {Function? onError,}) {
    try {
      final result = onValue(fakeData);
      return Future.value(result);
    } catch (e) {
      if (onError != null) {
        onError(e);
        return Future.error(e);
      }
      return Future.error(e);
    }
  }

  @override
  PostgrestFilterBuilder<PostgrestList> neq(String column, dynamic value) {
    final filtered = fakeData.where((item) => item[column] != value).toList();
    return FakeFilterBuilder(filtered);
  }

  @override
  PostgrestTransformBuilder<PostgrestMap> single() {
    return FakeSingleBuilder(fakeData.isNotEmpty ? fakeData.first : {});
  }

  @override
  Future<PostgrestList> catchError(Function onError, {bool Function(Object)? test}) {
    return Future.value(fakeData);
  }

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, dynamic value) {
    return this;
  }

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> order(String column, {bool ascending = true, bool nullsFirst = false, String? referencedTable}) {
    return this;
  }

  // Add this method
  @override
  PostgrestFilterBuilder<PostgrestList> select([String columns = '*']) {
    return this;
  }
}


class FakeSingleBuilder extends Fake implements PostgrestTransformBuilder<PostgrestMap> {
  final Map<String, dynamic> fakeData;

  FakeSingleBuilder(this.fakeData);

  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestMap) onValue, {Function? onError}) {
    try {
      final result = onValue(fakeData);
      return Future.value(result);
    } catch (e) {
      if (onError != null) {
        onError(e);
        return Future.error(e);
      }
      return Future.error(e);
    }
  }

  @override
  Future<PostgrestMap> catchError(Function onError, {bool Function(Object)? test}) {
    return Future.value(fakeData);
  }
}
