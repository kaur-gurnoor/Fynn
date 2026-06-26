# Fynn — Private AI CFO

A Flutter app that gives small business owners a personal AI financial advisor. All data is end-to-end encrypted and stored exclusively on your own [Atsign](https://atsign.com) atServer — no third party ever holds your financials.

## Features

| Feature | Description |
|---|---|
| **Encrypted storage** | Transactions stored on your personal atServer via the atProtocol |
| **CSV import** | Auto-detects columns, date formats, and categorises transactions |
| **Spending chart** | Donut pie chart breaking down expenses by category |
| **AI Cash Flow** | 30-day forecast with monthly trend chart and top categories |
| **AI Anomaly Report** | Flags unusual transactions as severity-coded alert cards |
| **CFO Briefing** | Plain-English weekly summary with actionable recommendations |
| **Ask Fynn** | Chat interface — ask any financial question, answered with your data as context |
| **Tax Estimator** | Calculates 25% self-employment tax set-aside per month |
| **Benchmarks** | Compares Rent / Payroll / Software / Utilities against industry thresholds |
| **PDF Export** | One-click professional report with transactions, summaries, and AI insights |

## Requirements

- Flutter 3.24+
- An [Atsign @sign](https://atsign.com) (free tier available)
- [Ollama](https://ollama.com) running locally with the `llama3` model for AI features

## Setup

```bash
# 1. Install dependencies
flutter pub get

# 2. Start Ollama with llama3 (required for AI features)
ollama pull llama3
ollama serve

# 3. Run the app
flutter run
```

## AI Features

All AI runs **locally** via Ollama — no API keys, no data leaves your machine.

```
Endpoint: http://localhost:11434/api/generate
Model:    llama3
```

If Ollama is not running, the app works normally for everything except the AI Insights and Ask Fynn chat tabs.

## Project Structure

```
lib/
  models/           transaction.dart, insight.dart
  services/         at_service.dart, transaction_service.dart,
                    ai_service.dart, pdf_service.dart
  screens/          home, dashboard, transactions, insights, settings
  widgets/          transaction_tile.dart, empty_state.dart
```

## Auth Methods

The app supports four ways to sign in with your @sign:

1. **Keychain** — previously authenticated devices
2. **New @sign** — register via the Atsign registrar
3. **APKAM** — enroll a new device from an already-authenticated one
4. **.atKeys file** — restore from a backup keys file

---

Built with Flutter · [Atsign Platform](https://atsign.com) · Ollama
