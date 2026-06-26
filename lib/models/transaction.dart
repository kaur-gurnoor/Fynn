import 'dart:convert';

enum TransactionType { credit, debit }

class Transaction {
  final String id;
  final DateTime date;
  final String description;
  final double amount;
  final TransactionType type;
  final String category;

  const Transaction({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    required this.category,
  });

  bool get isCredit => type == TransactionType.credit;

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        description: j['description'] as String,
        amount: (j['amount'] as num).toDouble(),
        type: j['type'] == 'credit'
            ? TransactionType.credit
            : TransactionType.debit,
        category: j['category'] as String? ?? 'Uncategorised',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'description': description,
        'amount': amount,
        'type': type == TransactionType.credit ? 'credit' : 'debit',
        'category': category,
      };

  String toJsonString() => jsonEncode(toJson());

  static Transaction fromJsonString(String s) =>
      Transaction.fromJson(jsonDecode(s) as Map<String, dynamic>);

  static String atKeyName(String id) => 'tx_$id';
}
