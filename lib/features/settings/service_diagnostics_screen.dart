import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/app_strings.dart';
import '../../services/service_diagnostics_service.dart';

class ServiceDiagnosticsScreen extends StatefulWidget {
  const ServiceDiagnosticsScreen({super.key});

  @override
  State<ServiceDiagnosticsScreen> createState() =>
      _ServiceDiagnosticsScreenState();
}

class _ServiceDiagnosticsScreenState extends State<ServiceDiagnosticsScreen> {
  final ServiceDiagnosticsService _service = ServiceDiagnosticsService();

  ServiceDiagnosticsReport? _report;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    final report = await _service.run();
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  Future<void> _copy() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.asText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('service_diagnostics_copied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('service_diagnostics')),
        actions: [
          IconButton(
            tooltip: context.tr('copy_diagnostics'),
            onPressed: report == null ? null : _copy,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: context.tr('refresh'),
            onPressed: _loading ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _loading && report == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      if (_loading) const LinearProgressIndicator(),
                      if (_loading) const SizedBox(height: 12),
                      if (report != null) ...[
                        _SummaryCard(report: report),
                        const SizedBox(height: 12),
                        for (final entry in report.entries)
                          _DiagnosticTile(entry: entry),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final ServiceDiagnosticsReport report;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          report.passed ? Icons.check_circle_rounded : Icons.error_rounded,
          color: report.passed
              ? const Color(0xFF29D398)
              : Theme.of(context).colorScheme.error,
        ),
        title: Text(
          report.passed
              ? context.tr('service_diagnostics_ready')
              : context.tr('service_diagnostics_needs_attention'),
        ),
        subtitle: Text(report.generatedAt.toLocal().toString()),
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  const _DiagnosticTile({required this.entry});

  final ServiceDiagnosticEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.status) {
      'PASS' => const Color(0xFF29D398),
      'WARN' => const Color(0xFFFFC73D),
      _ => Theme.of(context).colorScheme.error,
    };
    final icon = switch (entry.status) {
      'PASS' => Icons.check_circle_outline_rounded,
      'WARN' => Icons.warning_amber_rounded,
      _ => Icons.cancel_outlined,
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(entry.name),
        subtitle: SelectableText(entry.detail),
        trailing: Text(
          entry.status,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
