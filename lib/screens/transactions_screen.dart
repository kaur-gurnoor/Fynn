import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/transaction_service.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/empty_state.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Transaction> _all = [];
  List<Transaction> _filtered = [];
  bool _loading = true;
  bool _uploading = false;
  String _query = '';

  final _svc = TransactionService.instance;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final txns = await _svc.getAll();
      if (mounted) {
        setState(() {
          _all = txns;
          _filter();
        });
      }
    } catch (e) {
      _showError('Load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _query.toLowerCase();
    _filtered = q.isEmpty
        ? _all
        : _all
            .where((t) =>
                t.description.toLowerCase().contains(q) ||
                t.category.toLowerCase().contains(q))
            .toList();
  }

  Future<void> _uploadCsv() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _showError('Could not read file. Please try again.');
      return;
    }

    setState(() => _uploading = true);
    try {
      final content = String.fromCharCodes(bytes);
      final parsed = _svc.parseCsv(content);
      if (parsed.isEmpty) {
        _showError('No transactions found in the CSV. Check the file format.');
        return;
      }

      await _svc.storeAll(parsed);

      // Immediately populate list with freshly imported transactions
      if (mounted) {
        final existingIds = {for (final t in _all) t.id};
        setState(() {
          _all = [
            ...parsed.where((t) => !existingIds.contains(t.id)),
            ..._all,
          ]..sort((a, b) => b.date.compareTo(a.date));
          _filter();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${parsed.length} transactions imported and encrypted on your atServer.',
            ),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
      }
    } on FormatException catch (e) {
      _showError('CSV format error: ${e.message}');
    } catch (e) {
      _showError('Import error: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteTransaction(Transaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Delete Transaction',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${tx.description}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _svc.delete(tx.id);
    await _load();
  }

  Future<void> _deleteAll() async {
    if (_all.isEmpty) return;

    // First confirmation
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete All Transactions', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to delete all transactions? This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    // Second confirmation — must type DELETE
    final confirmCtrl = TextEditingController();
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Final Confirmation', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will permanently delete all your financial data from your atServer.',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 16),
              const Text('Type DELETE to confirm:', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, letterSpacing: 1.2),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  hintText: 'DELETE',
                  hintStyle: const TextStyle(color: Colors.white24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                ),
                onChanged: (_) => setS(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: confirmCtrl.text == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Delete Everything', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
    if (second != true || !mounted) return;

    try {
      await _svc.deleteAll();
      if (mounted) {
        setState(() { _all = []; _filtered = []; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All transactions deleted.')),
        );
      }
    } catch (e) {
      _showError('Delete error: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  String get _summary {
    final income = _svc.totalIncome(_filtered);
    final expenses = _svc.totalExpenses(_filtered);
    final fmt = NumberFormat.currency(symbol: '\$');
    return 'Income ${fmt.format(income)} · Expenses ${fmt.format(expenses)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Transactions',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        actions: [
          if (_uploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF3B82F6),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _uploadCsv,
              icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
              tooltip: 'Import CSV',
            ),
          if (_all.isNotEmpty)
            IconButton(
              onPressed: _deleteAll,
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              tooltip: 'Delete all transactions',
            ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search transactions…',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white38,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _query = '';
                            _filter();
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
              ),
              onChanged: (v) => setState(() {
                _query = v;
                _filter();
              }),
            ),
          ),

          // Summary bar
          if (_filtered.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} transactions · $_summary',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          // List
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF3B82F6),
                    ),
                  )
                : _filtered.isEmpty
                    ? _all.isEmpty
                        ? Center(
                            child: EmptyState(
                              icon: Icons.upload_file_outlined,
                              title: 'No transactions',
                              subtitle:
                                  'Tap the upload icon to import a CSV bank export.\nTransactions are encrypted on your atServer.',
                              action: ElevatedButton.icon(
                                onPressed: _uploadCsv,
                                icon: const Icon(Icons.upload_file_rounded),
                                label: const Text('Import CSV'),
                              ),
                            ),
                          )
                        : const Center(
                            child: Text(
                              'No matching transactions.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: const Color(0xFF3B82F6),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => TransactionTile(
                            transaction: _filtered[i],
                            onDelete: () => _deleteTransaction(_filtered[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
