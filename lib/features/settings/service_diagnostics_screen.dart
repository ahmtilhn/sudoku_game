import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/app_strings.dart';
import '../../services/service_diagnostics_service.dart';
import '../../widgets/in_page_header.dart';

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
  int _page = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _page = 0;
    });
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_loading && report == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final entries = report?.entries ?? const <ServiceDiagnosticEntry>[];
            final compact = constraints.maxHeight < 650;
            final pageSize = compact ? 3 : 5;
            final pageCount = entries.isEmpty
                ? 1
                : (entries.length / pageSize).ceil();
            final page = _page.clamp(0, pageCount - 1);
            final start = page * pageSize;
            final end = (start + pageSize).clamp(0, entries.length);
            final visible = entries.sublist(start, end);

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    constraints.maxWidth < 360 ? 10 : 16,
                    compact ? 4 : 10,
                    constraints.maxWidth < 360 ? 10 : 16,
                    compact ? 6 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InPageHeader(
                        title: context.tr('service_diagnostics'),
                        padding: EdgeInsets.only(bottom: compact ? 4 : 8),
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
                      if (_loading) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 5),
                      ],
                      if (report != null) ...[
                        _SummaryCard(report: report),
                        SizedBox(height: compact ? 5 : 8),
                      ],
                      Expanded(
                        child: Column(
                          children: [
                            for (var index = 0; index < visible.length; index++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == visible.length - 1 ? 0 : 5,
                                  ),
                                  child: _DiagnosticTile(
                                    entry: visible[index],
                                    compact: compact,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (pageCount > 1)
                        _DiagnosticsPager(
                          page: page,
                          pageCount: pageCount,
                          onPrevious: page > 0
                              ? () => setState(() => _page = page - 1)
                              : null,
                          onNext: page < pageCount - 1
                              ? () => setState(() => _page = page + 1)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DiagnosticsPager extends StatelessWidget {
  const _DiagnosticsPager({
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              '${page + 1} / $pageCount',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
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
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          report.generatedAt.toLocal().toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  const _DiagnosticTile({required this.entry, required this.compact});

  final ServiceDiagnosticEntry entry;
  final bool compact;

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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 12,
          vertical: compact ? 5 : 8,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: compact ? 19 : 23),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    entry.detail,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              entry.status,
              maxLines: 1,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}
