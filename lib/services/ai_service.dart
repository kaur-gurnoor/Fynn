import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/transaction.dart';
import '../models/insight.dart';

class AiService {
  static const _endpoint = 'http://localhost:11434/api/generate';
  static const _model = 'llama3';

  const AiService();

  Future<Insight> generateCashFlow(List<Transaction> transactions) async {
    final summary = _buildSummary(transactions);
    final raw = await _call(
      'You are a financial analyst AI. Analyse the following transaction history '
      'and produce a 30-day cash flow forecast.\n\n'
      '$summary\n\n'
      'Respond with ONLY valid JSON — no markdown, no explanation — in this exact shape:\n'
      '{"forecast_period":"YYYY-MM-DD to YYYY-MM-DD","projected_income":0.00,'
      '"projected_expenses":0.00,"projected_net":0.00,"confidence":"high|medium|low",'
      '"monthly_trend":[{"month":"Jan","income":0.00,"expenses":0.00}],'
      '"top_expense_categories":[{"category":"X","amount":0.00}],'
      '"insights":["insight 1","insight 2"],'
      '"recommendation":"one sentence recommendation"}',
    );
    return Insight(
      type: InsightType.cashFlow,
      content: _extractJson(raw),
      generatedAt: DateTime.now(),
    );
  }

  Future<Insight> generateAnomalyReport(List<Transaction> transactions) async {
    final summary = _buildSummary(transactions);
    final raw = await _call(
      'You are a financial fraud and anomaly detection expert. '
      'Review the following transactions and identify anything unusual.\n\n'
      '$summary\n\n'
      'Respond with ONLY valid JSON — no markdown, no explanation — in this exact shape:\n'
      '{"anomaly_count":0,"risk_level":"low|medium|high",'
      '"anomalies":[{"date":"YYYY-MM-DD","description":"tx description",'
      '"amount":0.00,"reason":"why unusual","severity":"low|medium|high"}],'
      '"patterns":["pattern 1","pattern 2"],'
      '"recommendation":"one sentence recommendation"}',
    );
    return Insight(
      type: InsightType.anomaly,
      content: _extractJson(raw),
      generatedAt: DateTime.now(),
    );
  }

  Future<Insight> generateBriefing(List<Transaction> transactions) async {
    final summary = _buildSummary(transactions);
    final raw = await _call(
      'You are a virtual CFO. Write a concise, professional weekly financial '
      'briefing for a small business owner based on the following transaction data.\n\n'
      '$summary\n\n'
      'Write in plain text (no markdown formatting). Include:\n'
      '- Executive summary (2-3 sentences)\n'
      '- Key financial metrics this period\n'
      '- Notable income and expense movements\n'
      '- 2-3 actionable recommendations\n'
      '- Overall financial health score (1-10)\n\n'
      'Keep it practical and jargon-free. Address the owner directly.',
    );
    return Insight(
      type: InsightType.briefing,
      content: raw.trim(),
      generatedAt: DateTime.now(),
    );
  }

  Future<String> chat({
    required List<Transaction> transactions,
    required List<Map<String, String>> history,
    required String userMessage,
  }) async {
    final summary = _buildSummary(transactions);
    final historyBlock = history.isEmpty
        ? ''
        : '${history.map((m) => '${m['role'] == 'user' ? 'User' : 'Fynn'}: ${m['content']}').join('\n')}\n\n';
    final prompt = 'You are Fynn, a helpful AI financial assistant for small '
        'business owners. Answer questions concisely based on the financial '
        'data provided. Keep answers to 2-4 sentences unless more detail is '
        'needed. If something is not in the data, say so.\n\n'
        'FINANCIAL DATA:\n$summary\n\n'
        '${historyBlock}User: $userMessage\n\nFynn:';
    return (await _call(prompt)).trim();
  }

  Future<String> _call(String prompt) async {
    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': _model,
            'prompt': prompt,
            'stream': false,
          }),
        )
        .timeout(const Duration(minutes: 5));

    if (response.statusCode != 200) {
      throw Exception(
        'Ollama error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['response'] as String;
  }

  // Strip markdown code fences if the model wraps JSON in them
  String _extractJson(String raw) {
    final trimmed = raw.trim();
    final fenceStart = trimmed.indexOf('```');
    if (fenceStart != -1) {
      final contentStart = trimmed.indexOf('\n', fenceStart) + 1;
      final fenceEnd = trimmed.lastIndexOf('```');
      if (contentStart > 0 && fenceEnd > contentStart) {
        return trimmed.substring(contentStart, fenceEnd).trim();
      }
    }
    // If no fences, find the first { and last }
    final jsonStart = trimmed.indexOf('{');
    final jsonEnd = trimmed.lastIndexOf('}');
    if (jsonStart != -1 && jsonEnd > jsonStart) {
      return trimmed.substring(jsonStart, jsonEnd + 1);
    }
    return trimmed;
  }

  String _buildSummary(List<Transaction> transactions) {
    if (transactions.isEmpty) return 'No transactions available.';

    double totalIncome = 0;
    double totalExpenses = 0;
    final categoryTotals = <String, double>{};

    for (final tx in transactions) {
      if (tx.isCredit) {
        totalIncome += tx.amount;
      } else {
        totalExpenses += tx.amount;
        categoryTotals[tx.category] =
            (categoryTotals[tx.category] ?? 0) + tx.amount;
      }
    }

    final categoryStr = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final txSample = transactions
        .take(30)
        .map((t) =>
            '${t.date.toIso8601String().substring(0, 10)} | '
            '${t.isCredit ? '+' : '-'}\$${t.amount.toStringAsFixed(2)} | '
            '${t.description} | ${t.category}')
        .join('\n');

    return '''
PERIOD: ${transactions.last.date.toIso8601String().substring(0, 10)} to ${transactions.first.date.toIso8601String().substring(0, 10)}
TOTAL TRANSACTIONS: ${transactions.length}
TOTAL INCOME: \$${totalIncome.toStringAsFixed(2)}
TOTAL EXPENSES: \$${totalExpenses.toStringAsFixed(2)}
NET: \$${(totalIncome - totalExpenses).toStringAsFixed(2)}

TOP EXPENSE CATEGORIES:
${categoryStr.take(8).map((e) => '  ${e.key}: \$${e.value.toStringAsFixed(2)}').join('\n')}

RECENT TRANSACTIONS (up to 30):
$txSample
''';
  }
}
