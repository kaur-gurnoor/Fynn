import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/insight.dart';
import '../models/transaction.dart';
import '../services/transaction_service.dart';
import '../services/ai_service.dart';
import '../services/at_service.dart';
import '../services/pdf_service.dart';
import '../widgets/empty_state.dart';

// ── Main screen ───────────────────────────────────────────────────────────────

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  Insight? _cashFlow;
  Insight? _anomaly;
  Insight? _briefing;

  List<Transaction> _transactions = [];
  bool _txLoading = true;
  bool _generating = false;
  String? _error;

  final _txSvc = TransactionService.instance;
  final _atSvc = AtService.instance;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadTransactions(), _loadSaved()]);
  }

  Future<void> _loadTransactions() async {
    try {
      final txns = await _txSvc.getAll();
      if (mounted) setState(() => _transactions = txns);
    } finally {
      if (mounted) setState(() => _txLoading = false);
    }
  }

  Future<void> _loadSaved() async {
    for (final type in InsightType.values) {
      final dummy = Insight(type: type, content: '', generatedAt: DateTime.now());
      final val = await _atSvc.get(dummy.atKeyName);
      if (val != null && mounted) {
        try {
          final insight = Insight.fromJsonString(val);
          setState(() {
            switch (type) {
              case InsightType.cashFlow:
                _cashFlow = insight;
              case InsightType.anomaly:
                _anomaly = insight;
              case InsightType.briefing:
                _briefing = insight;
            }
          });
        } catch (_) {}
      }
    }
  }

  Future<void> _generate() async {
    final txns = await _txSvc.getAll();
    if (mounted) setState(() => _transactions = txns);
    if (txns.isEmpty) {
      if (mounted) setState(() => _error = 'No transactions to analyse. Import a CSV first.');
      return;
    }
    if (mounted) setState(() { _generating = true; _error = null; });
    try {
      const ai = AiService();
      final cf = await ai.generateCashFlow(txns);
      final an = await ai.generateAnomalyReport(txns);
      final br = await ai.generateBriefing(txns);
      await _atSvc.put(cf.atKeyName, cf.toJsonString());
      await _atSvc.put(an.atKeyName, an.toJsonString());
      await _atSvc.put(br.atKeyName, br.toJsonString());
      if (mounted) setState(() { _cashFlow = cf; _anomaly = an; _briefing = br; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _regenerate() async {
    for (final key in ['insight_cashflow', 'insight_anomaly', 'insight_briefing']) {
      try { await _atSvc.delete(key); } catch (_) {}
    }
    if (mounted) setState(() { _cashFlow = null; _anomaly = null; _briefing = null; });
    await _generate();
  }

  Future<void> _generatePdf() async {
    final txns = await _txSvc.getAll();
    if (mounted) setState(() => _transactions = txns);
    if (txns.isEmpty) {
      _showSnack('No transactions to include in report.');
      return;
    }
    try {
      await PdfService.generateAndShare(
        transactions: txns,
        atsign: _atSvc.currentAtsign,
        cashFlow: _cashFlow,
        briefing: _briefing,
      );
    } catch (e) {
      _showSnack('PDF error: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  bool get _hasInsights => _cashFlow != null || _anomaly != null || _briefing != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI Insights',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white),
        ),
        actions: [
          if (_generating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
              ),
            )
          else ...[
            if (_hasInsights)
              IconButton(
                onPressed: _regenerate,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                tooltip: 'Regenerate insights',
              ),
            IconButton(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF3B82F6)),
              tooltip: 'Generate AI analysis',
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: const Color(0xFF3B82F6),
          unselectedLabelColor: Colors.white54,
          indicatorColor: const Color(0xFF3B82F6),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Cash Flow'),
            Tab(text: 'Anomalies'),
            Tab(text: 'Briefing'),
            Tab(text: 'Ask Fynn'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.red.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                    onPressed: () => setState(() => _error = null),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(
                  transactions: _transactions,
                  txLoading: _txLoading,
                  hasInsights: _hasInsights,
                  generating: _generating,
                  onGenerate: _generate,
                  onRegenerate: _regenerate,
                  onPdf: _generatePdf,
                ),
                _CashFlowTab(insight: _cashFlow, onGenerate: _generate, onRegenerate: _regenerate),
                _AnomalyTab(insight: _anomaly, onGenerate: _generate, onRegenerate: _regenerate),
                _BriefingTab(insight: _briefing, onGenerate: _generate),
                _ChatTab(transactions: _transactions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.transactions,
    required this.txLoading,
    required this.hasInsights,
    required this.generating,
    required this.onGenerate,
    required this.onRegenerate,
    required this.onPdf,
  });

  final List<Transaction> transactions;
  final bool txLoading;
  final bool hasInsights;
  final bool generating;
  final VoidCallback onGenerate;
  final VoidCallback onRegenerate;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    if (txLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
    }
    if (transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'No transactions',
        subtitle: 'Import a CSV to see spending analysis and AI insights.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SpendingPieChart(transactions: transactions),
          const SizedBox(height: 20),
          _TaxCard(transactions: transactions),
          const SizedBox(height: 20),
          _BenchmarkCard(transactions: transactions),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: const Text('Export PDF Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: generating ? null : (hasInsights ? onRegenerate : onGenerate),
              icon: generating
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
                    )
                  : Icon(
                      hasInsights ? Icons.refresh_rounded : Icons.auto_awesome_rounded,
                      size: 18,
                    ),
              label: Text(
                generating
                    ? 'Generating…'
                    : hasInsights
                        ? 'Regenerate AI Insights'
                        : 'Generate AI Insights',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3B82F6),
                side: const BorderSide(color: Color(0xFF3B82F6)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Cash Flow Tab ─────────────────────────────────────────────────────────────

class _CashFlowTab extends StatelessWidget {
  const _CashFlowTab({
    required this.insight,
    required this.onGenerate,
    required this.onRegenerate,
  });

  final Insight? insight;
  final VoidCallback onGenerate;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    if (insight == null) {
      return EmptyState(
        icon: Icons.auto_graph_outlined,
        title: 'No forecast yet',
        subtitle: 'Tap Generate to create a 30-day cash flow forecast.',
        action: ElevatedButton.icon(
          onPressed: onGenerate,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Generate'),
        ),
      );
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(insight!.content) as Map<String, dynamic>;
    } catch (_) {
      return _ParseErrorState(onRegenerate: onRegenerate);
    }

    final fmt = NumberFormat.currency(symbol: '\$');
    final monthly = (data['monthly_trend'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
    final topCats = (data['top_expense_categories'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
    final insights = (data['insights'] as List<dynamic>?)?.cast<String>() ?? [];
    final projIncome = (data['projected_income'] as num?)?.toDouble() ?? 0;
    final projExpenses = (data['projected_expenses'] as num?)?.toDouble() ?? 0;
    final projNet = (data['projected_net'] as num?)?.toDouble() ?? 0;
    final confidence = data['confidence'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _InsightMeta(generatedAt: insight!.generatedAt),
              const Spacer(),
              if (confidence.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${confidence.toUpperCase()} CONFIDENCE',
                    style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Three key figures
          Row(children: [
            _FigureCard(
              label: 'Projected Income',
              value: fmt.format(projIncome),
              color: const Color(0xFF22C55E),
            ),
            const SizedBox(width: 12),
            _FigureCard(
              label: 'Projected Expenses',
              value: fmt.format(projExpenses),
              color: Colors.redAccent,
            ),
          ]),
          const SizedBox(height: 12),
          _FigureCard(
            label: 'Projected Net',
            value: fmt.format(projNet),
            color: projNet >= 0 ? const Color(0xFF22C55E) : Colors.redAccent,
            fullWidth: true,
          ),

          if (monthly != null && monthly.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Monthly Trend', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            SizedBox(height: 200, child: _MonthlyChart(monthly: monthly)),
          ],

          if (topCats != null && topCats.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Top Expense Categories', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            ...topCats.map((c) => _CategoryBar(
                  label: c['category'] as String? ?? '',
                  amount: (c['amount'] as num?)?.toDouble() ?? 0,
                  maxAmount: (topCats.first['amount'] as num?)?.toDouble() ?? 1,
                )),
          ],

          if (insights.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Key Insights', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            ...insights.map((i) => _InsightBullet(text: i)),
          ],

          if (data['recommendation'] != null) ...[
            const SizedBox(height: 20),
            _RecommendationCard(text: data['recommendation'] as String),
          ],

          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Regenerate'),
            style: TextButton.styleFrom(foregroundColor: Colors.white38),
          ),
        ],
      ),
    );
  }
}

// ── Anomaly Tab ───────────────────────────────────────────────────────────────

class _AnomalyTab extends StatelessWidget {
  const _AnomalyTab({
    required this.insight,
    required this.onGenerate,
    required this.onRegenerate,
  });

  final Insight? insight;
  final VoidCallback onGenerate;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    if (insight == null) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No anomaly report yet',
        subtitle: 'Generate AI analysis to detect unusual transactions.',
        action: ElevatedButton.icon(
          onPressed: onGenerate,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Generate'),
        ),
      );
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(insight!.content) as Map<String, dynamic>;
    } catch (_) {
      return _ParseErrorState(onRegenerate: onRegenerate);
    }

    final anomalies = (data['anomalies'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final patterns = (data['patterns'] as List<dynamic>?)?.cast<String>() ?? [];
    final riskLevel = data['risk_level'] as String? ?? 'low';
    final riskColor = riskLevel == 'high'
        ? Colors.redAccent
        : riskLevel == 'medium'
            ? Colors.orangeAccent
            : const Color(0xFF22C55E);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InsightMeta(generatedAt: insight!.generatedAt),
          const SizedBox(height: 16),

          // Risk badge
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: riskColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    riskLevel == 'high' ? Icons.warning_rounded
                        : riskLevel == 'medium' ? Icons.info_rounded
                        : Icons.check_circle_rounded,
                    color: riskColor, size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Risk: ${riskLevel.toUpperCase()}',
                    style: TextStyle(color: riskColor, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${anomalies.length} anomal${anomalies.length == 1 ? 'y' : 'ies'} found',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ]),

          if (anomalies.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Flagged Transactions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            ...anomalies.map((a) => _AnomalyCard(anomaly: a)),
          ],

          if (patterns.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Patterns Detected', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            ...patterns.map((p) => _InsightBullet(text: p)),
          ],

          if (data['recommendation'] != null) ...[
            const SizedBox(height: 20),
            _RecommendationCard(text: data['recommendation'] as String),
          ],

          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Regenerate'),
            style: TextButton.styleFrom(foregroundColor: Colors.white38),
          ),
        ],
      ),
    );
  }
}

// ── Briefing Tab ──────────────────────────────────────────────────────────────

class _BriefingTab extends StatelessWidget {
  const _BriefingTab({required this.insight, required this.onGenerate});
  final Insight? insight;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    if (insight == null) {
      return EmptyState(
        icon: Icons.article_outlined,
        title: 'No briefing yet',
        subtitle: 'Generate your weekly CFO briefing.',
        action: ElevatedButton.icon(
          onPressed: onGenerate,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Generate'),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InsightMeta(generatedAt: insight!.generatedAt),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: SelectableText(
              insight!.content,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.65),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat Tab ──────────────────────────────────────────────────────────────────

class _ChatMsg {
  final String role;
  final String text;
  _ChatMsg({required this.role, required this.text});
}

class _ChatTab extends StatefulWidget {
  const _ChatTab({required this.transactions});
  final List<Transaction> transactions;

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _messages = <_ChatMsg>[];
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();
    setState(() {
      _messages.add(_ChatMsg(role: 'user', text: text));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final historyStart = _messages.length > 11 ? _messages.length - 11 : 0;
      final history = _messages.sublist(historyStart, _messages.length - 1)
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();

      final response = await AiService().chat(
        transactions: widget.transactions,
        history: history,
        userMessage: text,
      );
      if (mounted) {
        setState(() => _messages.add(_ChatMsg(role: 'assistant', text: response)));
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _messages.add(_ChatMsg(
              role: 'assistant',
              text: 'Could not reach Ollama. Make sure it is running at localhost:11434 with the llama3 model.',
            )));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No transaction data',
        subtitle: 'Import transactions first so Fynn has financial context to answer questions.',
      );
    }
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chat_bubble_outline_rounded,
                              color: Color(0xFF3B82F6), size: 28),
                        ),
                        const SizedBox(height: 16),
                        const Text('Ask Fynn about your finances',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        const Text(
                          '"What is my biggest expense?"\n"Am I profitable this month?"\n"Where can I cut costs?"',
                          style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.7),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _ChatBubble(msg: _messages[i]),
                ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(children: [
              SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
              ),
              SizedBox(width: 8),
              Text('Fynn is thinking…', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            border: Border(top: BorderSide(color: Color(0xFF334155))),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ask about your finances…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: const Color(0xFF3B82F6),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _loading ? null : _send,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _ParseErrorState extends StatelessWidget {
  const _ParseErrorState({required this.onRegenerate});
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Could not parse the AI response.',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'The model may have returned an unexpected format. Regenerate to try again.',
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRegenerate,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Regenerate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.msg});
  final _ChatMsg msg;

  bool get _isUser => msg.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _isUser ? const Color(0xFF3B82F6) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(_isUser ? 18 : 4),
            bottomRight: Radius.circular(_isUser ? 4 : 18),
          ),
          border: _isUser ? null : Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: _isUser ? Colors.white : Colors.white.withValues(alpha: 0.85),
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _InsightMeta extends StatelessWidget {
  const _InsightMeta({required this.generatedAt});
  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Generated ${DateFormat('MMM d, yyyy HH:mm').format(generatedAt)}',
      style: const TextStyle(color: Colors.white38, fontSize: 12),
    );
  }
}

class _FigureCard extends StatelessWidget {
  const _FigureCard({
    required this.label,
    required this.value,
    required this.color,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 18)),
        ],
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: card) : Expanded(child: card);
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.label, required this.amount, required this.maxAmount});
  final String label;
  final double amount;
  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    final fraction = maxAmount > 0 ? (amount / maxAmount).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text(
                NumberFormat.currency(symbol: '\$').format(amount),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: const Color(0xFF334155),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightBullet extends StatelessWidget {
  const _InsightBullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: Color(0xFF3B82F6)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: Color(0xFF3B82F6), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5))),
        ],
      ),
    );
  }
}

class _AnomalyCard extends StatelessWidget {
  const _AnomalyCard({required this.anomaly});
  final Map<String, dynamic> anomaly;

  @override
  Widget build(BuildContext context) {
    final severity = anomaly['severity'] as String? ?? 'low';
    final color = severity == 'high'
        ? Colors.redAccent
        : severity == 'medium'
            ? Colors.orangeAccent
            : Colors.yellowAccent;
    final icon = severity == 'high'
        ? Icons.warning_rounded
        : severity == 'medium'
            ? Icons.info_rounded
            : Icons.circle_outlined;
    final fmt = NumberFormat.currency(symbol: '\$');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anomaly['description'] as String? ?? '',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  anomaly['reason'] as String? ?? '',
                  style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text(
                    anomaly['date'] as String? ?? '',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      severity.toUpperCase(),
                      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fmt.format((anomaly['amount'] as num?)?.toDouble() ?? 0),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.monthly});
  final List<Map<String, dynamic>> monthly;

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceEvenly,
        backgroundColor: Colors.transparent,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx < 0 || idx >= monthly.length) return const SizedBox.shrink();
                return Text(
                  monthly[idx]['month'] as String? ?? '',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: monthly.asMap().entries.map((e) {
          final income = (e.value['income'] as num?)?.toDouble() ?? 0;
          final expenses = (e.value['expenses'] as num?)?.toDouble() ?? 0;
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: income,
                color: const Color(0xFF22C55E),
                width: 8,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              BarChartRodData(
                toY: expenses,
                color: Colors.redAccent,
                width: 8,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Spending Pie Chart ────────────────────────────────────────────────────────

class _SpendingPieChart extends StatelessWidget {
  const _SpendingPieChart({required this.transactions});
  final List<Transaction> transactions;

  static const _colors = [
    Color(0xFF3B82F6),
    Color(0xFFEF4444),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFF97316),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF64748B),
    Color(0xFFA78BFA),
  ];

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, double>{};
    for (final tx in transactions) {
      if (!tx.isCredit) {
        byCategory[tx.category] = (byCategory[tx.category] ?? 0) + tx.amount;
      }
    }
    if (byCategory.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: const Text('No expense data yet.', style: TextStyle(color: Colors.white54)),
      );
    }

    final sorted = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold(0.0, (s, e) => s + e.value);
    final fmt = NumberFormat.currency(symbol: '\$');

    final sections = sorted.asMap().entries.map((entry) {
      final pct = total > 0 ? entry.value.value / total * 100 : 0.0;
      return PieChartSectionData(
        value: entry.value.value,
        color: _colors[entry.key % _colors.length],
        title: pct >= 5 ? '${pct.toStringAsFixed(0)}%' : '',
        radius: 60,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spending by Category',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 46,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ...sorted.asMap().entries.map((entry) {
            final pct = total > 0 ? entry.value.value / total * 100 : 0.0;
            final color = _colors[entry.key % _colors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(entry.value.key, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 10),
                Text(
                  fmt.format(entry.value.value),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

// ── Tax Card ──────────────────────────────────────────────────────────────────

class _TaxCard extends StatelessWidget {
  const _TaxCard({required this.transactions});
  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    final svc = TransactionService.instance;
    final income = svc.totalIncome(transactions);
    final expenses = svc.totalExpenses(transactions);
    final net = income - expenses;

    double months = 1;
    if (transactions.length > 1) {
      final sorted = transactions.toList()..sort((a, b) => a.date.compareTo(b.date));
      final days = sorted.last.date.difference(sorted.first.date).inDays;
      months = (days / 30).clamp(1.0, double.infinity);
    }

    final totalTax = net > 0 ? net * 0.25 : 0.0;
    final monthlyTax = totalTax / months;
    final fmt = NumberFormat.currency(symbol: '\$');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFF59E0B), size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Tax Estimator', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 18),
          if (net <= 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.check_circle_outline_rounded, color: Color(0xFF22C55E), size: 16),
                SizedBox(width: 8),
                Expanded(child: Text('No tax set-aside needed — no net profit this period.', style: TextStyle(color: Color(0xFF22C55E), fontSize: 13))),
              ]),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Set aside for taxes this month', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(fmt.format(monthlyTax),
                      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 28, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _taxRow('Net profit', fmt.format(net)),
            _taxRow('SE tax rate', '25%'),
            _taxRow('Period', '${months.toStringAsFixed(1)} month${months == 1 ? '' : 's'}'),
            _taxRow('Total tax estimate', fmt.format(totalTax)),
          ],
        ],
      ),
    );
  }

  Widget _taxRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Benchmark Card ────────────────────────────────────────────────────────────

class _BenchmarkCard extends StatelessWidget {
  const _BenchmarkCard({required this.transactions});
  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    final svc = TransactionService.instance;
    final revenue = svc.totalIncome(transactions);
    final fmt = NumberFormat.currency(symbol: '\$');

    final byCategory = <String, double>{};
    for (final tx in transactions) {
      if (!tx.isCredit) {
        byCategory[tx.category] = (byCategory[tx.category] ?? 0) + tx.amount;
      }
    }

    const benchmarks = [
      ('Rent', 'Rent', 0.10),
      ('Payroll', 'Payroll', 0.30),
      ('Software', 'Subscriptions', 0.10),
      ('Utilities', 'Utilities', 0.05),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.leaderboard_rounded, color: Color(0xFF3B82F6), size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Industry Benchmarks', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            revenue > 0 ? 'vs ${fmt.format(revenue)} revenue' : 'No revenue data yet',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (revenue <= 0)
            const Text('Import transactions with income to see benchmarks.', style: TextStyle(color: Colors.white54, fontSize: 13))
          else
            ...benchmarks.map((b) {
              final (name, category, threshold) = b;
              final spent = byCategory[category] ?? 0;
              final ratio = spent / revenue;
              final isOver = ratio > threshold;
              final overspend = revenue * (ratio - threshold);
              final pct = (ratio * 100).toStringAsFixed(1);
              final benchPct = (threshold * 100).toStringAsFixed(0);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isOver
                      ? Colors.redAccent.withValues(alpha: 0.05)
                      : const Color(0xFF22C55E).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isOver
                        ? Colors.redAccent.withValues(alpha: 0.25)
                        : const Color(0xFF22C55E).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isOver ? Icons.warning_rounded : Icons.check_circle_rounded,
                      color: isOver ? Colors.redAccent : const Color(0xFF22C55E),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(
                            isOver
                                ? 'Over by ${fmt.format(overspend)} ($pct% vs $benchPct% limit)'
                                : '$pct% of revenue (limit $benchPct%)',
                            style: TextStyle(
                              color: isOver ? Colors.redAccent : Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      fmt.format(spent),
                      style: TextStyle(
                        color: isOver ? Colors.redAccent : const Color(0xFF22C55E),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
