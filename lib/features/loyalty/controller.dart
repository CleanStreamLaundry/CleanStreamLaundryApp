import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_ledger_entry.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_action_context.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';
import 'package:intl/intl.dart';

class LoyaltyController extends ChangeNotifier {
  static const refreshMaxAge = Duration(seconds: 30);
  static const requestTimeout = Duration(seconds: 20);

  LoyaltyController({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _authService = GetIt.instance<AuthService>();
  final _profileService = GetIt.instance<ProfileService>();
  final _paymentProcessor = GetIt.instance<PaymentProcessor>();
  final _walletService = GetIt.instance<WalletService>();

  double? userBalance;
  double? paidBalance;
  double? promoBalance;
  double? userReward;
  String? userName;
  String? errorMessage;
  bool isLoading = true;
  bool showPastTransactions = false;
  bool isRefreshing = false;
  bool isPaying = false;
  bool isLoadingMore = false;
  bool isLoadingRewards = false;
  bool hasMoreTransactions = false;
  bool hasMoreRewards = false;
  String? transactionsError;
  String? rewardsError;

  List<String> recentTransactions = [];
  List<String> rewardTransactions = [];
  List<WalletLedgerEntry> _ledger = [];
  List<WalletLedgerEntry> _rewards = [];
  WalletLedgerEntry? _ledgerCursor;
  WalletLedgerEntry? _rewardsCursor;
  String? _userId;
  String? _walletAccountId;
  DateTime? _ledgerSince;
  DateTime? _rewardsSince;
  DateTime? _lastRefresh;
  int _accountEpoch = 0;
  int _readEpoch = 0;
  bool _disposed = false;
  bool _active = true;
  final _cancelReads = <void Function()>{};
  StreamSubscription<bool>? _authSubscription;
  Future<void>? _refreshFuture;
  Future<PaymentResult>? _paymentFuture;

  int get accountEpoch => _accountEpoch;
  bool get isCurrentAccount =>
      _userId != null && _userId == _authService.getCurrentUserId;

  void setActive(bool active) {
    if (!_disposed) _active = active;
  }

  Future<T> _bounded<T>(Future<T> request) {
    final result = Completer<T>();
    void cancel() {
      if (!result.isCompleted) {
        result.completeError(StateError('Wallet closed'));
      }
    }

    final timer = Timer(requestTimeout, () {
      result.completeError(TimeoutException('Wallet read timed out'));
    });
    _cancelReads.add(cancel);
    request.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future.whenComplete(() {
      timer.cancel();
      _cancelReads.remove(cancel);
    });
  }

  bool _current(String userId, int epoch) =>
      !_disposed &&
      epoch == _readEpoch &&
      _userId == userId &&
      _authService.getCurrentUserId == userId;

  void _syncAccount({bool signedOut = false}) {
    final next = signedOut ? null : _authService.getCurrentUserId;
    if (next == _userId) return;
    _userId = next;
    _accountEpoch++;
    _readEpoch++;
    _refreshFuture = null;
    _walletAccountId = null;
    _ledgerSince = _rewardsSince = null;
    _lastRefresh = null;
    userBalance = paidBalance = promoBalance = userReward = null;
    userName = errorMessage = transactionsError = rewardsError = null;
    _ledger = [];
    _rewards = [];
    _ledgerCursor = _rewardsCursor = null;
    recentTransactions = [];
    rewardTransactions = [];
    showPastTransactions = false;
    hasMoreTransactions = hasMoreRewards = false;
    isLoadingMore = isLoadingRewards = isRefreshing = false;
    isLoading = true;
  }

  Future<void> initialize() {
    _authSubscription ??= _authService.onAuthChange.listen((signedIn) {
      if (_disposed) return;
      final previous = _accountEpoch;
      _syncAccount(signedOut: !signedIn);
      if (previous != _accountEpoch) {
        notifyListeners();
        if (signedIn && _active) unawaited(refresh());
      }
    });
    return refresh();
  }

  Future<void> refresh({bool ifStale = false}) => _refresh(ifStale: ifStale);

  Future<void> _refresh({bool ifStale = false, bool reconciliation = false}) {
    if (_disposed) return Future.value();
    _syncAccount();
    if (!_active && !reconciliation) return Future.value();
    final userId = _userId;
    if (userId == null) {
      errorMessage = 'User not known';
      isLoading = false;
      notifyListeners();
      return Future.value();
    }
    if (_refreshFuture != null) return _refreshFuture!;
    if (ifStale &&
        (isPaying ||
            (_lastRefresh != null &&
                _now().difference(_lastRefresh!) < refreshMaxAge))) {
      return Future.value();
    }
    final epoch = ++_readEpoch;
    isLoadingMore = isLoadingRewards = false;
    isRefreshing = true;
    late final Future<void> pending;
    pending =
        Future<void>.microtask(
          () => _readWallet(userId, epoch, reconciliation: reconciliation),
        ).whenComplete(() {
          if (identical(_refreshFuture, pending)) _refreshFuture = null;
        });
    _refreshFuture = pending;
    notifyListeners();
    return pending;
  }

  Future<void> _readWallet(
    String userId,
    int epoch, {
    required bool reconciliation,
  }) async {
    if (!_current(userId, epoch)) return;
    try {
      if (!_active && !reconciliation) return;
      final results = await _bounded(
        Future.wait([
          _profileService.getUserBalanceById(userId),
          _walletService.getBalance(),
        ]),
      );
      if (!_current(userId, epoch)) return;
      final profile = results[0] as Map<String, dynamic>?;
      final balance = results[1] as WalletBalance;
      if (profile == null) throw StateError('Profile unavailable');
      userBalance = balance.totalBalance;
      paidBalance = balance.paidBalance;
      promoBalance = balance.promoBalance;
      userName = profile['full_name'] ?? 'John Doe';
      userReward = (profile['reward_tracker'] as num?)?.toDouble() ?? 0.0;
      if (_walletAccountId != balance.walletAccountId) {
        _ledger = [];
        _rewards = [];
        _ledgerCursor = _rewardsCursor = null;
        _ledgerSince = _rewardsSince = null;
        recentTransactions = [];
        rewardTransactions = [];
        hasMoreTransactions = hasMoreRewards = false;
      }
      _walletAccountId = balance.walletAccountId;
      final since = _now().subtract(const Duration(days: 30));
      errorMessage = null;
      notifyListeners();
      if (!_active && !reconciliation) return;
      // Both lists have independent cursors and error states, not a truncated
      // rewards subset of the first general-history page.
      await Future.wait([
        _readPage(userId, epoch, since: since),
        _readPage(userId, epoch, since: since, rewardsOnly: true),
      ]);
      if (!_current(userId, epoch)) return;
      if (transactionsError == null && rewardsError == null) {
        _lastRefresh = _now();
      }
    } catch (_) {
      if (!_current(userId, epoch)) return;
      errorMessage = 'Failed to fetch balance';
    } finally {
      if (_current(userId, epoch)) {
        isLoading = false;
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _readPage(
    String userId,
    int epoch, {
    required DateTime since,
    bool rewardsOnly = false,
    bool append = false,
  }) async {
    if (!_current(userId, epoch)) return;
    final walletId = _walletAccountId;
    if (walletId == null) return;
    final existing = rewardsOnly ? _rewards : _ledger;
    final before = append
        ? (rewardsOnly ? _rewardsCursor : _ledgerCursor)
        : null;
    try {
      final rows = await _bounded(
        _walletService.getLedger(
          userId: userId,
          walletAccountId: walletId,
          since: since,
          before: before,
          rewardsOnly: rewardsOnly,
        ),
      );
      if (!_current(userId, epoch) || walletId != _walletAccountId) return;
      final batch = rows.take(WalletService.ledgerPageSize).toList();
      final cursor = batch.isEmpty ? null : batch.last;
      final hasMore = rows.length > WalletService.ledgerPageSize;
      final page = batch.where(
        (entry) =>
            entry.createdAt.isAfter(since) &&
            (!rewardsOnly ||
                entry.entryType == 'load_bonus' ||
                (entry.amountCents > 0 && entry.promoAmountCents > 0)),
      );
      // Preserve loaded older pages during a head refresh, but fetch the next
      // page from the new server cursor so newly inserted rows cannot leave gaps.
      // Appending never invalidates already loaded rows in the same time window.
      final retained = existing.where(
        (entry) =>
            entry.createdAt.isAfter(since) &&
            (append ||
                (hasMore &&
                    cursor != null &&
                    _compareEntries(entry, cursor) > 0)),
      );
      final merged = <int, WalletLedgerEntry>{
        for (final entry in retained) entry.id: entry,
        for (final entry in page) entry.id: entry,
      }.values.toList()..sort(_compareEntries);
      if (rewardsOnly) {
        _rewardsSince = since;
        _rewardsCursor = cursor;
        _rewards = merged;
        rewardTransactions = _rewards.map(_formatWalletLedgerEntry).toList();
        hasMoreRewards = hasMore;
        rewardsError = null;
      } else {
        _ledgerSince = since;
        _ledgerCursor = cursor;
        _ledger = merged;
        _updateTransactions();
        hasMoreTransactions = hasMore;
        transactionsError = null;
      }
    } catch (_) {
      if (!_current(userId, epoch)) return;
      if (rewardsOnly) {
        rewardsError = 'Unable to refresh rewards';
      } else {
        transactionsError = 'Unable to refresh transactions';
      }
    } finally {
      if (_current(userId, epoch)) notifyListeners();
    }
  }

  Future<void> toggleTransactionView() async {
    if (_disposed) return;
    showPastTransactions = !showPastTransactions;
    _updateTransactions();
    notifyListeners();
  }

  int _compareEntries(WalletLedgerEntry left, WalletLedgerEntry right) {
    final time = right.createdAt.compareTo(left.createdAt);
    return time == 0 ? right.id.compareTo(left.id) : time;
  }

  void _updateTransactions() {
    recentTransactions = (showPastTransactions ? _ledger : _ledger.take(3))
        .map(_formatWalletLedgerEntry)
        .toList();
  }

  Future<void> loadMoreTransactions({bool rewardsOnly = false}) async {
    if (_disposed) return;
    _syncAccount();
    if (!_active) return;
    final since = rewardsOnly ? _rewardsSince : _ledgerSince;
    if (_refreshFuture != null || since == null || !isCurrentAccount) return;
    if (rewardsOnly
        ? isLoadingRewards || !hasMoreRewards
        : isLoadingMore || !hasMoreTransactions) {
      return;
    }
    final epoch = _readEpoch;
    if (rewardsOnly) {
      isLoadingRewards = true;
    } else {
      isLoadingMore = true;
    }
    notifyListeners();
    try {
      await _readPage(
        _userId!,
        epoch,
        since: since,
        rewardsOnly: rewardsOnly,
        append: true,
      );
    } finally {
      if (!_disposed && epoch == _readEpoch) {
        if (rewardsOnly) {
          isLoadingRewards = false;
        } else {
          isLoadingMore = false;
        }
        notifyListeners();
      }
    }
  }

  Future<void> fetchTransactions() => refresh();

  Future<LoyaltyActionContext> loadPurchaseConsent() async {
    _syncAccount();
    final account = _accountEpoch;
    final user = _userId;
    if (_disposed || !isCurrentAccount) throw StateError('Account changed');
    final result = await _profileService.getLoyaltyActionContext('wallet_load');
    if (_disposed || account != _accountEpoch || !isCurrentAccount ||
        result.subjectId != user) {
      throw StateError('Account changed');
    }
    return result;
  }

  Future<PaymentResult> loadCard(double amount, {Map<String, dynamic>? consent}) {
    if (_disposed) return Future.value(PaymentResult.pending);
    if (_paymentFuture != null) return _paymentFuture!;
    if (isPaying) return Future.value(PaymentResult.pending);
    _syncAccount();
    if (!isCurrentAccount) return Future.value(PaymentResult.pending);
    final account = _accountEpoch;
    final userId = _userId!;
    isPaying = true;
    notifyListeners();
    late final Future<PaymentResult> payment;
    payment = _pay(amount, userId, account, consent).whenComplete(() {
      if (identical(_paymentFuture, payment)) _paymentFuture = null;
      if (!_disposed) {
        isPaying = false;
        notifyListeners();
      }
    });
    return _paymentFuture = payment;
  }

  Future<PaymentResult> _pay(
    double amount,
    String userId,
    int account,
    Map<String, dynamic>? consent,
  ) async {
    if (_disposed ||
        account != _accountEpoch ||
        userId != _authService.getCurrentUserId) {
      return PaymentResult.pending;
    }
    final result = await _paymentProcessor.processPayment(
      amount,
      'Loyalty Card',
      consent: consent,
    );
    if (_disposed ||
        account != _accountEpoch ||
        userId != _authService.getCurrentUserId) {
      return PaymentResult.pending;
    }
    if (result == PaymentResult.success || result == PaymentResult.pending) {
      // Invalidate any pre-payment read, then serialize one authoritative read.
      _readEpoch++;
      await _refreshFuture;
      if (_disposed ||
          account != _accountEpoch ||
          userId != _authService.getCurrentUserId) {
        return PaymentResult.pending;
      }
      // A deliberately started payment still needs its authoritative read when
      // the retained page is hidden. Visibility only defers display refreshes.
      await _refresh(reconciliation: true);
      if (_disposed ||
          account != _accountEpoch ||
          userId != _authService.getCurrentUserId) {
        return PaymentResult.pending;
      }
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final cancel in _cancelReads.toList()) {
      cancel();
    }
    _readEpoch++;
    _accountEpoch++;
    _authSubscription?.cancel();
    super.dispose();
  }

  String _formatWalletLedgerEntry(WalletLedgerEntry entry) {
    final amount = entry.amountCents.abs() / 100.0;
    final formattedAmount = '\$${amount.toStringAsFixed(2)}';
    final formattedDate = DateFormat(
      'MMM dd, yyyy',
    ).format(entry.createdAt.toLocal());

    return '$formattedAmount ${_ledgerAction(entry)} on $formattedDate';
  }

  String _ledgerAction(WalletLedgerEntry entry) {
    switch (entry.entryType) {
      case 'load_paid':
        return 'added to Loyalty Card';
      case 'load_bonus':
        return 'added as promotional credit';
      case 'redeem_paid':
      case 'redeem_promo':
        return entry.machineId == null
            ? 'used for machine payment'
            : 'used for machine #${entry.machineId}';
      default:
        if (entry.amountCents < 0) {
          return 'deducted from Loyalty Card';
        }
        return 'posted to Loyalty Card';
    }
  }

  @Deprecated('Rewards are now calculated by the server wallet ledger.')
  double checkRewards(double amount) {
    double combined = (userReward ?? 0) + amount;
    double remainder = combined % 20;
    int rewardsEarned = combined ~/ 20;

    userReward = remainder;

    return amount + (rewardsEarned * 5);
  }
}
