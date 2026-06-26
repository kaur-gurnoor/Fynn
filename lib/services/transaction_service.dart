import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import 'at_service.dart';

class TransactionService {
  static TransactionService? _instance;
  static TransactionService get instance =>
      _instance ??= TransactionService._();
  TransactionService._();

  final _at = AtService.instance;

  // ── CSV parsing ───────────────────────────────────────────────────────────

  List<Transaction> parseCsv(String csvContent) {
    final rows = const CsvToListConverter(eol: '\n').convert(csvContent);
    if (rows.isEmpty) return [];

    // Find header row
    final headers =
        rows.first.map((h) => h.toString().toLowerCase().trim()).toList();

    final dateCol = _findCol(headers, ['date', 'transaction date', 'posted']);
    final descCol = _findCol(headers, [
      'description',
      'memo',
      'payee',
      'details',
      'narrative',
      'particulars',
    ]);
    final amtCol = _findCol(headers, ['amount', 'transaction amount']);
    final debitCol = _findCol(headers, ['debit', 'withdrawals', 'withdrawal']);
    final creditCol = _findCol(headers, ['credit', 'deposits', 'deposit']);

    if (dateCol == -1 || descCol == -1) {
      throw FormatException(
        'Could not detect required columns (date, description) in CSV.',
      );
    }

    final results = <Transaction>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) {
        continue;
      }

      try {
        final date = _parseDate(row[dateCol].toString().trim());
        final desc = row[descCol].toString().trim();
        double amount;
        TransactionType type;

        if (amtCol != -1) {
          final raw = _parseAmount(row[amtCol].toString());
          amount = raw.abs();
          type = raw >= 0 ? TransactionType.credit : TransactionType.debit;
        } else if (debitCol != -1 && creditCol != -1) {
          final debit = _parseAmount(row[debitCol].toString());
          final credit = _parseAmount(row[creditCol].toString());
          if (credit != 0) {
            amount = credit;
            type = TransactionType.credit;
          } else {
            amount = debit;
            type = TransactionType.debit;
          }
        } else {
          continue;
        }

        final id =
            '${date.millisecondsSinceEpoch}_${desc.hashCode.abs()}';
        results.add(Transaction(
          id: id,
          date: date,
          description: desc,
          amount: amount,
          type: type,
          category: _categorise(desc),
        ));
      } catch (_) {
        continue;
      }
    }

    results.sort((a, b) => b.date.compareTo(a.date));
    return results;
  }

  int _findCol(List<String> headers, List<String> candidates) {
    for (final c in candidates) {
      final i = headers.indexWhere((h) => h.contains(c));
      if (i != -1) return i;
    }
    return -1;
  }

  DateTime _parseDate(String raw) {
    final formats = [
      DateFormat('dd/MM/yyyy'),
      DateFormat('MM/dd/yyyy'),
      DateFormat('yyyy-MM-dd'),
      DateFormat('d MMM yyyy'),
      DateFormat('MMM d, yyyy'),
      DateFormat('MM-dd-yyyy'),
    ];
    for (final fmt in formats) {
      try {
        return fmt.parseStrict(raw);
      } catch (_) {}
    }
    throw FormatException('Unrecognised date format: $raw');
  }

  double _parseAmount(String raw) {
    if (raw.trim().isEmpty) return 0;
    return double.parse(
      raw.replaceAll(RegExp(r'[^\d.\-]'), ''),
    );
  }

  String _categorise(String desc) {
    final d = desc.toLowerCase();
    if (d.contains(RegExp(r'salary|payroll|paycheck|wage'))) return 'Income';
    if (d.contains(RegExp(r'rent|mortgage|lease'))) return 'Rent';
    if (d.contains(RegExp(r'electric|gas|water|utility|utilities'))) {
      return 'Utilities';
    }
    if (d.contains(RegExp(r'amazon|ebay|shop|store|retail'))) {
      return 'Shopping';
    }
    if (d.contains(RegExp(r'restaurant|cafe|coffee|food|grub|uber eat'))) {
      return 'Food & Dining';
    }
    if (d.contains(RegExp(r'uber|lyft|taxi|transit|bus|train|fuel|gas stat'))) {
      return 'Transport';
    }
    if (d.contains(RegExp(r'netflix|spotify|hulu|subscri|membership'))) {
      return 'Subscriptions';
    }
    if (d.contains(RegExp(r'insurance|insur'))) return 'Insurance';
    if (d.contains(RegExp(r'transfer|zelle|paypal|venmo|wire'))) {
      return 'Transfers';
    }
    if (d.contains(RegExp(r'atm|cash|withdrawal'))) return 'Cash';
    return 'Other';
  }

  // ── atServer storage ──────────────────────────────────────────────────────

  Future<void> storeAll(List<Transaction> transactions) async {
    for (final tx in transactions) {
      await _at.put(Transaction.atKeyName(tx.id), tx.toJsonString());
    }
  }

  Future<List<Transaction>> getAll() async {
    final keys = await _at.scan('tx_');
    final results = <Transaction>[];
    for (final k in keys) {
      final val = await _at.get(k.key);
      if (val != null) {
        try {
          results.add(Transaction.fromJsonString(val));
        } catch (_) {}
      }
    }
    results.sort((a, b) => b.date.compareTo(a.date));
    return results;
  }

  Future<void> delete(String id) async {
    await _at.delete(Transaction.atKeyName(id));
  }

  Future<void> deleteAll() async {
    final keys = await _at.scan('tx_');
    for (final k in keys) {
      await _at.delete(k.key);
    }
  }

  // ── Summary helpers ───────────────────────────────────────────────────────

  double totalIncome(List<Transaction> txns) => txns
      .where((t) => t.isCredit)
      .fold(0, (sum, t) => sum + t.amount);

  double totalExpenses(List<Transaction> txns) => txns
      .where((t) => !t.isCredit)
      .fold(0, (sum, t) => sum + t.amount);

  double netBalance(List<Transaction> txns) =>
      totalIncome(txns) - totalExpenses(txns);
}
