import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/transaction.dart';
import '../models/insight.dart';
import 'transaction_service.dart';

class PdfService {
  static const _blue = PdfColor(0.231, 0.510, 0.965);
  static const _green = PdfColor(0.133, 0.773, 0.369);
  static const _red = PdfColor(0.937, 0.267, 0.267);
  static const _dark = PdfColor(0.059, 0.090, 0.165);
  static const _grey = PdfColor(0.620, 0.620, 0.620);
  static const _lightGrey = PdfColor(0.94, 0.94, 0.96);

  static Future<void> generateAndShare({
    required List<Transaction> transactions,
    required String atsign,
    Insight? cashFlow,
    Insight? briefing,
  }) async {
    final svc = TransactionService.instance;
    final income = svc.totalIncome(transactions);
    final expenses = svc.totalExpenses(transactions);
    final net = income - expenses;
    final taxEstimate = net > 0 ? net * 0.25 : 0.0;

    final categoryTotals = <String, double>{};
    for (final tx in transactions) {
      if (!tx.isCredit) {
        categoryTotals[tx.category] =
            (categoryTotals[tx.category] ?? 0) + tx.amount;
      }
    }
    final sortedCats = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final now = DateTime.now();
    final fmt = NumberFormat.currency(symbol: '\$');
    final dateFmt = DateFormat('dd MMM yyyy');

    final doc = pw.Document();

    // ── Cover + Summary page ──────────────────────────────────────────────────
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header band
            pw.Container(
              width: double.infinity,
              color: _blue,
              padding: const pw.EdgeInsets.fromLTRB(40, 36, 40, 32),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'FYNN',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Financial Report — $atsign',
                    style: const pw.TextStyle(
                        color: PdfColors.white, fontSize: 13),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Generated ${dateFmt.format(now)}',
                    style: pw.TextStyle(
                        color: PdfColors.grey200, fontSize: 11),
                  ),
                ],
              ),
            ),

            pw.Padding(
              padding: const pw.EdgeInsets.all(40),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'EXECUTIVE SUMMARY',
                    style: pw.TextStyle(
                      color: _dark,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Three key metrics
                  pw.Row(children: [
                    _summaryBox(
                        'Total Income', fmt.format(income), _green, ctx),
                    pw.SizedBox(width: 12),
                    _summaryBox(
                        'Total Expenses', fmt.format(expenses), _red, ctx),
                    pw.SizedBox(width: 12),
                    _summaryBox(
                        'Net Profit',
                        fmt.format(net),
                        net >= 0 ? _green : _red,
                        ctx),
                  ]),

                  pw.SizedBox(height: 12),
                  pw.Row(children: [
                    _summaryBox(
                        'Tax Set-Aside (25%)', fmt.format(taxEstimate), _blue,
                        ctx),
                    pw.SizedBox(width: 12),
                    _summaryBox(
                        'Total Transactions',
                        '${transactions.length}',
                        _grey,
                        ctx),
                    pw.SizedBox(width: 12),
                    pw.Expanded(child: pw.SizedBox()),
                  ]),

                  pw.SizedBox(height: 32),

                  // Category breakdown
                  pw.Text(
                    'SPENDING BY CATEGORY',
                    style: pw.TextStyle(
                      color: _dark,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border:
                        pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(3),
                      1: pw.FlexColumnWidth(2),
                      2: pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.blueGrey800),
                        children: [
                          _th('Category'),
                          _th('Amount'),
                          _th('% of Revenue'),
                        ],
                      ),
                      ...sortedCats.map((e) {
                        final pct = income > 0
                            ? (e.value / income * 100).toStringAsFixed(1)
                            : '—';
                        return pw.TableRow(children: [
                          _td(e.key),
                          _td(fmt.format(e.value)),
                          _td('$pct%'),
                        ]);
                      }),
                    ],
                  ),

                  if (briefing != null) ...[
                    pw.SizedBox(height: 32),
                    pw.Text(
                      'CFO BRIEFING',
                      style: pw.TextStyle(
                        color: _dark,
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(14),
                      decoration: pw.BoxDecoration(
                        color: _lightGrey,
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Text(
                        briefing.content,
                        style: const pw.TextStyle(fontSize: 10, lineSpacing: 4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // ── Transactions page ─────────────────────────────────────────────────────
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'FYNN — Transaction History',
                  style: pw.TextStyle(
                      color: _blue,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  dateFmt.format(now),
                  style: pw.TextStyle(color: _grey, fontSize: 9),
                ),
              ],
            ),
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (ctx) => [
          pw.Table(
            border:
                pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(70),
              1: pw.FlexColumnWidth(4),
              2: pw.FlexColumnWidth(2),
              3: pw.FixedColumnWidth(70),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.blueGrey800),
                children: [
                  _th('Date'),
                  _th('Description'),
                  _th('Category'),
                  _th('Amount'),
                ],
              ),
              ...transactions.map((tx) => pw.TableRow(children: [
                    _td(DateFormat('dd MMM yy').format(tx.date)),
                    _td(tx.description, maxLines: 2),
                    _td(tx.category),
                    _tdColored(
                      '${tx.isCredit ? '+' : '-'}${fmt.format(tx.amount)}',
                      tx.isCredit ? _green : _red,
                    ),
                  ])),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'fynn_financial_report.pdf',
    );
  }

  static pw.Widget _summaryBox(
      String label, String value, PdfColor color, pw.Context ctx) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: color.shade(0.92),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(color: _grey, fontSize: 9)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _th(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(text,
            style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _td(String text, {int? maxLines}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(text,
            style: const pw.TextStyle(fontSize: 9),
            maxLines: maxLines),
      );

  static pw.Widget _tdColored(String text, PdfColor color) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: pw.FontWeight.bold)),
      );
}
