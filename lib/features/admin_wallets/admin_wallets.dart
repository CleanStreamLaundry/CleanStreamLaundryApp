import 'dart:async';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:clean_stream_laundry_app/logic/services/admin_wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminWalletsPage extends StatefulWidget {
  const AdminWalletsPage({super.key});

  @override
  State<AdminWalletsPage> createState() => _AdminWalletsPageState();
}

class _AdminWalletsPageState extends State<AdminWalletsPage> {
  final AdminWalletService _service = GetIt.instance<AdminWalletService>();
  final AuthService _auth = GetIt.instance<AuthService>();
  late final StreamSubscription<AuthState> _authSubscription;
  Session? _observedSession;
  int _generation = 0;
  bool _authAvailable = true;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  List<Map<String, dynamic>> _wallets = [];
  Map<String, dynamic>? _selectedDetail;
  String? _selectedWalletId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _observedSession = _auth.currentSession;
    _authSubscription = _auth.authStateChanges.listen(
      (state) {
        if (!identical(state.session, _observedSession) ||
            state.event == AuthChangeEvent.signedOut) {
          _observedSession = state.session;
          _invalidateSession();
        }
      },
      onError: (Object _) {
        _authAvailable = false;
        _invalidateSession();
      },
      onDone: () {
        _authAvailable = false;
        _invalidateSession();
      },
    );
    _search();
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_authSubscription.cancel());
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _invalidateSession() {
    _generation++;
    if (!mounted) return;
    _searchController.clear();
    _noteController.clear();
    setState(() {
      _wallets = [];
      _selectedDetail = null;
      _selectedWalletId = null;
      _loading = false;
      _error = 'Session changed; refresh wallets before continuing.';
    });
  }

  bool _current(Session? session, int generation, {String? walletId}) {
    return mounted &&
        _authAvailable &&
        generation == _generation &&
        session != null &&
        identical(session, _observedSession) &&
        identical(session, _auth.currentSession) &&
        session.user.id == _auth.getCurrentUserId &&
        session.accessToken.isNotEmpty &&
        session.expiresAt != null &&
        !session.isExpired &&
        (walletId == null || walletId == _selectedWalletId);
  }

  Future<void> _search() async {
    final session = _auth.currentSession;
    final generation = _generation;
    if (!_current(session, generation)) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Current wallet owner session required.';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wallets = await _service.searchWallets(_searchController.text);
      if (!_current(session, generation)) return;
      _wallets = wallets;
    } catch (error) {
      if (!_current(session, generation)) return;
      _error = error.toString();
    } finally {
      if (_current(session, generation)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectWallet(String walletId) async {
    final session = _auth.currentSession;
    final generation = _generation;
    if (!_current(session, generation)) return;
    setState(() {
      _selectedWalletId = walletId;
      _selectedDetail = null;
      _loading = true;
    });
    try {
      final detail = await _service.getWalletDetail(walletId);
      if (!_current(session, generation, walletId: walletId)) return;
      _selectedDetail = detail;
    } catch (error) {
      if (!_current(session, generation, walletId: walletId)) return;
      _error = error.toString();
    } finally {
      if (_current(session, generation, walletId: walletId)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _recordComplaint() async {
    final session = _auth.currentSession;
    final generation = _generation;
    final walletId = _selectedWalletId;
    final note = _noteController.text.trim();
    if (walletId == null || note.isEmpty ||
        !_current(session, generation, walletId: walletId)) {
      return;
    }

    try {
      await _service.recordDeletedAccountComplaint(
        walletAccountId: walletId,
        note: note,
      );
      if (!_current(session, generation, walletId: walletId)) return;
      _noteController.clear();
      await _selectWallet(walletId);
    } catch (error) {
      if (!_current(session, generation, walletId: walletId)) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _toggleLock(bool locked) async {
    final session = _auth.currentSession;
    final generation = _generation;
    final walletId = _selectedWalletId;
    if (walletId == null ||
        !_current(session, generation, walletId: walletId)) {
      return;
    }

    try {
      await _service.lockWallet(walletId, locked);
      if (!_current(session, generation, walletId: walletId)) return;
      await _search();
      if (!_current(session, generation, walletId: walletId)) return;
      await _selectWallet(walletId);
    } catch (error) {
      if (!_current(session, generation, walletId: walletId)) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _showMoneyAction({
    required String title,
    required bool cashRedemption,
  }) async {
    final session = _auth.currentSession;
    final generation = _generation;
    final walletId = _selectedWalletId;
    if (walletId == null ||
        !_current(session, generation, walletId: walletId)) {
      return;
    }

    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Required note',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true ||
        !_current(session, generation, walletId: walletId)) {
      return;
    }

    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final amountCents = (amount * 100).round();
    final note = noteController.text.trim();
    if (amountCents <= 0 || note.isEmpty) return;

    try {
      if (cashRedemption) {
        await _service.recordCashRedemptionOrStripeRefund(
          walletAccountId: walletId,
          amountCents: amountCents,
          note: note,
        );
      } else {
        await _service.adjustWallet(
          walletAccountId: walletId,
          amountCents: amountCents,
          paidAmountCents: 0,
          promoAmountCents: amountCents,
          note: note,
        );
      }

      if (!_current(session, generation, walletId: walletId)) return;
      await _selectWallet(walletId);
    } catch (error) {
      if (!_current(session, generation, walletId: walletId)) return;
      setState(() => _error = error.toString());
    }
  }

  String _money(dynamic cents) {
    final value = ((cents as num?)?.toInt() ?? 0) / 100.0;
    return '\$${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final detail = _selectedDetail;
    final balance = detail?['balance'] as Map<String, dynamic>?;

    return BasePage(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin Wallets',
              style: TextStyle(
                color: Theme.of(context).colorScheme.fontSecondary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText:
                          'Search wallet ID, user ID, or Stripe reference',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: 'Search',
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 380,
                    child: _loading && _wallets.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            itemCount: _wallets.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final wallet = _wallets[index];
                              final walletId =
                                  wallet['wallet_account_id'] as String;
                              return ListTile(
                                selected: walletId == _selectedWalletId,
                                title: Text(walletId),
                                subtitle: Text(
                                  '${wallet['status']} | ${_money(wallet['total_balance_cents'])}',
                                ),
                                onTap: () => _selectWallet(walletId),
                              );
                            },
                          ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: detail == null
                        ? const Center(child: Text('Select a wallet'))
                        : ListView(
                            children: [
                              Text(
                                'Total ${_money(balance?['total_balance_cents'])}',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Paid ${_money(balance?['paid_balance_cents'])} | Promo ${_money(balance?['promo_balance_cents'])} | Status ${balance?['status']}',
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _toggleLock(true),
                                    icon: const Icon(Icons.lock_outline),
                                    label: const Text('Lock'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _toggleLock(false),
                                    icon: const Icon(Icons.lock_open_outlined),
                                    label: const Text('Unlock'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _showMoneyAction(
                                      title: 'Add Promo Adjustment',
                                      cashRedemption: false,
                                    ),
                                    icon: const Icon(Icons.add_card_outlined),
                                    label: const Text('Adjust'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _showMoneyAction(
                                      title:
                                          'Legal Cash Redemption or Stripe Refund',
                                      cashRedemption: true,
                                    ),
                                    icon: const Icon(Icons.currency_exchange),
                                    label: const Text('Cash/Refund'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _noteController,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Deleted-account complaint note',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _recordComplaint,
                                icon: const Icon(Icons.report_outlined),
                                label: const Text('Record Complaint'),
                              ),
                              const SizedBox(height: 24),
                              _AdminSection(
                                title: 'Loads',
                                rows: detail['loads'] as List,
                              ),
                              _AdminSection(
                                title: 'Redemptions',
                                rows: detail['redemptions'] as List,
                              ),
                              _AdminSection(
                                title: 'Ledger',
                                rows: detail['ledger'] as List,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminSection extends StatelessWidget {
  final String title;
  final List rows;

  const _AdminSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('$title (${rows.length})'),
      children: rows.take(25).map((row) {
        final data = Map<String, dynamic>.from(row as Map);
        return ListTile(
          dense: true,
          title: Text(
            data['entry_type']?.toString() ??
                data['status']?.toString() ??
                data['id'].toString(),
          ),
          subtitle: Text(data.toString()),
        );
      }).toList(),
    );
  }
}
