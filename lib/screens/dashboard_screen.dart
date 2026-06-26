import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/transaction_service.dart';
import '../services/at_service.dart';
import '../widgets/stat_card.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/empty_state.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Transaction> _transactions = [];
  bool _loading = true;

  final _svc = TransactionService.instance;
  final _at = AtService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final txns = await _svc.getAll();
      if (mounted) setState(() => _transactions = txns);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Load error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final income = _svc.totalIncome(_transactions);
    final expenses = _svc.totalExpenses(_transactions);
    final net = _svc.netBalance(_transactions);
    final recent = _transactions.take(5).toList();
    final fmt = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dashboard',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            Text(
              _at.currentAtsign,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF3B82F6),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats row
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: 'Net Balance',
                            value: fmt.format(net),
                            icon: Icons.account_balance_rounded,
                            color: net >= 0
                                ? const Color(0xFF22C55E)
                                : Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: 'Total Income',
                            value: fmt.format(income),
                            icon: Icons.arrow_downward_rounded,
                            color: const Color(0xFF22C55E),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            label: 'Total Expenses',
                            value: fmt.format(expenses),
                            icon: Icons.arrow_upward_rounded,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StatCard(
                      label: 'Transactions',
                      value: '${_transactions.length}',
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xFF3B82F6),
                    ),

                    const SizedBox(height: 28),

                    const Text(
                      'Recent Transactions',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (recent.isEmpty)
                      const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No transactions yet',
                        subtitle:
                            'Go to Transactions and upload a CSV bank export.',
                      )
                    else
                      ...recent.map((tx) => TransactionTile(transaction: tx)),
                  ],
                ),
              ),
            ),
    );
  }
}
