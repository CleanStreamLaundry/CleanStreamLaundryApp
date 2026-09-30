import 'dart:async';

import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TopupRefundsController extends ChangeNotifier {
  final _auth = GetIt.instance<AuthService>();
  final _wallet = GetIt.instance<WalletService>();
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  int _generation = 0;
  bool _disposed = false;
  bool _active = true;
  bool _writing = false;
  final _uncertain = <String>{};

  List<RefundableTopup> topups = [];
  List<TopupRefund> refunds = [];
  String? topupsError, refundsError, message;
  bool loadingTopups = false, loadingRefunds = false;
  bool topupsLoaded = false, refundsLoaded = false;
  bool moreTopups = false, moreRefunds = false;
  String? _topupCursor;
  TopupRefund? _refundCursor;

  int get generation => _generation;
  bool get writing => _writing;
  bool get hasSession => _validSession(_session);
  bool isUncertain(String loadId) => _uncertain.contains(loadId);

  bool _validSession(Session? session) =>
      session != null &&
      identical(session, _auth.currentSession) &&
      session.user.id == _auth.getCurrentUserId &&
      session.accessToken.isNotEmpty &&
      session.expiresAt != null &&
      !session.isExpired;

  bool _current(int generation) =>
      !_disposed &&
      _active &&
      generation == _generation &&
      _validSession(_session);

  Future<void> initialize() {
    _session = _auth.currentSession;
    _subscription ??= _auth.authStateChanges.listen((_) {
      if (_disposed) return;
      _resetSession();
      if (_active && hasSession) unawaited(refresh());
    });
    return refresh();
  }

  void _resetSession() {
    _generation++;
    _session = _auth.currentSession;
    topups = [];
    refunds = [];
    _topupCursor = null;
    _refundCursor = null;
    topupsLoaded = refundsLoaded = moreTopups = moreRefunds = false;
    loadingTopups = loadingRefunds = _writing = false;
    topupsError = refundsError = message = null;
    _uncertain.clear();
    notifyListeners();
  }

  // Composer can deactivate a retained route when admission or visibility changes.
  void setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    _resetSession();
    if (active) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed || !_active || _writing) return;
    if (!identical(_session, _auth.currentSession)) _resetSession();
    if (!hasSession) {
      message = 'A current signed-in session is required.';
      notifyListeners();
      return;
    }
    final epoch = _generation;
    await _readTopups();
    if (_current(epoch)) await _readRefunds();
  }

  Future<void> loadMoreTopups() => _readTopups(append: true);
  Future<void> loadMoreRefunds() => _readRefunds(append: true);

  Future<void> _readTopups({bool append = false}) async {
    final epoch = _generation;
    if (!_current(epoch) || loadingTopups || (append && !moreTopups)) return;
    final session = _session!;
    loadingTopups = true;
    notifyListeners();
    try {
      final page = await _wallet.listRefundableTopups(
        session: session,
        beforeLoadId: append ? _topupCursor : null,
      );
      if (!_current(epoch)) return;
      topups = {
        if (append)
          for (final row in topups) row.loadId: row,
        for (final row in page) row.loadId: row,
      }.values.toList();
      _topupCursor = page.isEmpty ? null : page.last.loadId;
      moreTopups = page.length == WalletService.topupRefundPageSize;
      topupsLoaded = true;
      topupsError = null;
      for (final row in page) {
        if (row.refund != null) _uncertain.remove(row.loadId);
      }
    } catch (_) {
      if (_current(epoch)) {
        topupsError =
            'Top-ups could not be refreshed. Shown information may be out of date.';
      }
    } finally {
      if (_current(epoch)) {
        loadingTopups = false;
        notifyListeners();
      }
    }
  }

  Future<void> _readRefunds({bool append = false}) async {
    final epoch = _generation;
    if (!_current(epoch) || loadingRefunds || (append && !moreRefunds)) return;
    final session = _session!;
    loadingRefunds = true;
    notifyListeners();
    try {
      final page = await _wallet.listTopupRefunds(
        session: session,
        before: append ? _refundCursor : null,
      );
      if (!_current(epoch)) return;
      refunds = {
        if (append)
          for (final row in refunds) row.id: row,
        for (final row in page) row.id: row,
      }.values.toList();
      _refundCursor = page.isEmpty ? null : page.last;
      moreRefunds = page.length == WalletService.topupRefundPageSize;
      refundsLoaded = true;
      refundsError = null;
      for (final row in page) {
        _uncertain.remove(row.loadId);
      }
    } catch (_) {
      if (_current(epoch)) {
        refundsError =
            'Requests could not be refreshed. Shown statuses may be out of date.';
      }
    } finally {
      if (_current(epoch)) {
        loadingRefunds = false;
        notifyListeners();
      }
    }
  }

  bool canRequest(RefundableTopup topup, int epoch) =>
      _current(epoch) &&
      !_writing &&
      !loadingTopups &&
      !loadingRefunds &&
      topupsError == null &&
      refundsError == null &&
      topup.isAdvisoryEligible &&
      !_uncertain.contains(topup.loadId) &&
      !refunds.any((r) => r.loadId == topup.loadId) &&
      topups.any((r) => identical(r, topup));

  Future<void> request(
    RefundableTopup topup, {
    required int expectedGeneration,
  }) async {
    if (!canRequest(topup, expectedGeneration)) return;
    final session = _session!;
    _writing = true;
    message = null;
    // Keep this load blocked until an authoritative list confirms an operation.
    // A timeout/malformed acknowledgement cannot prove the reservation failed.
    _uncertain.add(topup.loadId);
    notifyListeners();
    try {
      final refund = await _wallet.requestTopupRefund(
        session: session,
        loadId: topup.loadId,
      );
      if (!_current(expectedGeneration)) return;
      if (refund.customerId != session.user.id ||
          refund.loadId != topup.loadId ||
          refund.principalCents != topup.principalCents ||
          refund.paymentSucceededAt != topup.paymentSucceededAt) {
        throw const FormatException('Refund acknowledgement mismatch');
      }
      refunds = [refund, ...refunds.where((r) => r.id != refund.id)];
      message = 'Request recorded. This is not confirmation of repayment.';
    } catch (error) {
      if (!_current(expectedGeneration)) return;
      final code = error is PostgrestException ? error.code : null;
      message = switch (code) {
        'PT401' || 'PT403' =>
          'Your account cannot request a refund right now. Refresh your account access.',
        'PT404' => 'This top-up is no longer available.',
        'PT409' =>
          'The server could not accept this request. Eligibility or available funds changed.',
        _ =>
          'The request outcome is not yet confirmed. Checking your requests; do not submit again. Contact support if it remains unconfirmed.',
      };
      if (const ['PT401', 'PT403', 'PT404', 'PT409'].contains(code)) {
        _uncertain.remove(topup.loadId);
      }
    } finally {
      if (_current(expectedGeneration)) {
        // Read-only reconciliation, never an automatic replay of the mutation.
        await _readTopups();
        if (_current(expectedGeneration)) await _readRefunds();
        if (_current(expectedGeneration)) {
          _writing = false;
          notifyListeners();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }
}
