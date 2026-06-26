import 'dart:convert';

enum InsightType { cashFlow, anomaly, briefing }

class Insight {
  final InsightType type;
  final String content;
  final DateTime generatedAt;

  const Insight({
    required this.type,
    required this.content,
    required this.generatedAt,
  });

  String get atKeyName => switch (type) {
        InsightType.cashFlow => 'insight_cashflow',
        InsightType.anomaly => 'insight_anomaly',
        InsightType.briefing => 'insight_briefing',
      };

  String get displayTitle => switch (type) {
        InsightType.cashFlow => '30-Day Cash Flow Forecast',
        InsightType.anomaly => 'Anomaly Report',
        InsightType.briefing => 'Weekly CFO Briefing',
      };

  factory Insight.fromJson(Map<String, dynamic> j) => Insight(
        type: InsightType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => InsightType.briefing,
        ),
        content: j['content'] as String,
        generatedAt: DateTime.parse(j['generatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'content': content,
        'generatedAt': generatedAt.toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());

  static Insight fromJsonString(String s) =>
      Insight.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
