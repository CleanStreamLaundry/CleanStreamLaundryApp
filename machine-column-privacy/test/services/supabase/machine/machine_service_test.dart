import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_machine_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'mocks.dart';

void main() {
  late SupabaseMock supabaseMock;
  late QueryBuilderMock queryBuilderMock;
  late FakeFilterBuilder fakeFilterBuilder;
  late SupabaseMachineService machineHandler;

  setUp(() {
    supabaseMock = SupabaseMock();
    queryBuilderMock = QueryBuilderMock();
    fakeFilterBuilder = FakeFilterBuilder(5);
    machineHandler = SupabaseMachineService(client: supabaseMock);

    when(() => supabaseMock.from('Machines')).thenAnswer((_) => queryBuilderMock);
    when(() => queryBuilderMock.select(any())).thenAnswer((_) => fakeFilterBuilder);
  });

  test('getDryerCountByLocation returns correct count', () async {
    final result = await machineHandler.getDryerCountByLocation('1');
    expect(result, 5);
    verify(() => queryBuilderMock.select('id')).called(1);
  });

  test('getDryerCountByLocation throws Postgrest Exception', () async {
    when(() => supabaseMock.from('Machines')).thenThrow(PostgrestException(message: "Test Exception"));
    final result = await machineHandler.getDryerCountByLocation('1');
    expect(result, 0);
  });

  test('getDryerCountByLocation throws unknown exception', () async {
    when(() => supabaseMock.from('Machines')).thenThrow(Exception("Test exception"));
    final result = await machineHandler.getDryerCountByLocation('1');
    expect(result, 0);
  });

  test('getIdleDryerCountByLocation returns correct count', () async {
    final result = await machineHandler.getIdleDryerCountByLocation('1');
    expect(result, 5);
    verify(() => queryBuilderMock.select('id')).called(1);
  });

  test('getIdleDryerCountByLocation throws Postgres exception', () async {
    when(() => supabaseMock.from('Machines')).thenThrow(PostgrestException(message: "Test Exception"));
    final result = await machineHandler.getIdleDryerCountByLocation('1');
    expect(result, 0);
  });

  test('getIdleDryerCountByLocation throws unknown exception', () async {
    when(() => supabaseMock.from('Machines')).thenThrow(Exception("Test exception"));
    final result = await machineHandler.getIdleDryerCountByLocation('1');
    expect(result, 0);
  });

  test('getWasherCountByLocation returns correct count', () async {
    final result = await machineHandler.getWasherCountByLocation('1');
    expect(result, 5);
    verify(() => queryBuilderMock.select('id')).called(1);
  });

  test('getWasherCountByLocation throws Postgres exception', () async {
    when(() => supabaseMock.from('Machines')).thenThrow(PostgrestException(message: "Test Exception"));
    final result = await machineHandler.getWasherCountByLocation('1');
    expect(result, 0);
  });

  test('getWasherCountByLocation throws unknown exception', () async {
    when(() => supabaseMock.from('Machines')).thenThrow(Exception("Test exception"));
    final result = await machineHandler.getWasherCountByLocation('1');
    expect(result, 0);
  });

  test('getIdleWasherCountByLocation returns correct count', () async {
    final result = await machineHandler.getIdleWasherCountByLocation('1');
    expect(result, 5);
    verify(() => queryBuilderMock.select('id')).called(1);
  });

  test('getIdleWasherCountByLocation throws Postgres exception', () async {
    when(() => supabaseMock.from('Machines')).thenThrow(PostgrestException(message: "Test Exception"));
    final result = await machineHandler.getIdleWasherCountByLocation('1');
    expect(result, 0);
  });

  test('getIdleWasherCountByLocation throws unknown exception', () async {
    when(() => supabaseMock.from('Machines')).thenThrow(Exception("Test exception"));
    final result = await machineHandler.getIdleWasherCountByLocation('1');
    expect(result, 0);
  });

  test('getMachineByIdTest',() async {
    FakeFilterBuilderMap fakeFilterBuilderMap = FakeFilterBuilderMap({"Name": "Dryer 1", "Price": 2.75});
    when(() => queryBuilderMock.select(any())).thenAnswer((_) => fakeFilterBuilderMap);
    final result = await machineHandler.getMachineById("1");
    expect(result?["Price"], 2.75);
    verify(() => queryBuilderMock.select('Name, Price')).called(1);
  });

  test('getMachineByIdTest error is Postgres error is thrown',() async {
    when(() => queryBuilderMock.select(any())).thenThrow(PostgrestException(message: "Test Exception"));
    final result = await machineHandler.getMachineById("1");
    expect(result,null);
  });

  test('getMachineByIdTest error is an unknown error',() async {
    when(() => queryBuilderMock.select(any())).thenThrow(Exception("Test exception"));
    final result = await machineHandler.getMachineById("1");
    expect(result,null);
  });

}
