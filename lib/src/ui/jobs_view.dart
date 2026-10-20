import 'package:flutter/material.dart';

import '../jobs/job_client.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class JobsView extends StatelessWidget {
  const JobsView({super.key, required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final board = desk.board;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const SectionLabel('Job plane'),
        const SizedBox(height: 8),
        const Text(
          'FastAPI accepts the request, PostgreSQL keeps the job, and a Celery worker runs it. Scores on this tab are fixture-scorer-v1.',
          style: TextStyle(color: DavidColors.muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        if (board == null)
          const EmptyNote(
            title: 'Reading the job service',
            body: 'Checking health, the catalog, and the latency snapshot.',
          )
        else if (!board.ok)
          EmptyNote(
            title: 'Job service unreachable',
            body:
                board.error ??
                'Start the API and worker, then open this tab again.',
          )
        else ...[
          _Metrics(board: board),
          const SizedBox(height: 16),
          const SectionLabel('Enqueue'),
          const SizedBox(height: 8),
          for (final item in board.items) ...[
            _CatalogCard(desk: desk, item: item),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          _Latest(job: desk.serviceJob),
        ],
        if (desk.serviceError != null) ...[
          const SizedBox(height: 12),
          Text(
            desk.serviceError!,
            style: const TextStyle(color: DavidColors.coral, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.board});

  final ServiceBoard board;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: [
          _Stat(label: 'In flight', value: '${board.depth}'),
          _Stat(label: 'Succeeded', value: '${board.succeeded}'),
          _Stat(label: 'Dead', value: '${board.dead}'),
          _Stat(
            label: 'Throughput',
            value: '${board.throughput.toStringAsFixed(2)} /s',
          ),
          _Stat(label: 'Queue wait p95', value: _ms(board.waitP95)),
          _Stat(label: 'E2E p95', value: _ms(board.e2eP95)),
          _Stat(label: 'E2E p99', value: _ms(board.e2eP99)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: DavidColors.faint,
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.desk, required this.item});

  final DeskController desk;
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.kind.toUpperCase(),
            style: const TextStyle(
              color: DavidColors.amber,
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            item.blurb,
            style: const TextStyle(color: DavidColors.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: ValueKey('enqueue-${item.title}'),
              onPressed: desk.enqueueing ? null : () => desk.enqueueJob(item),
              child: Text(desk.enqueueing ? 'Sending…' : 'Enqueue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Latest extends StatelessWidget {
  const _Latest({required this.job});

  final ServiceJob? job;

  @override
  Widget build(BuildContext context) {
    if (job == null) {
      return const EmptyNote(
        title: 'No job from this desk yet',
        body: 'Enqueue a case, the Cedar book, the ward cohort, or the Northwind accounts.',
      );
    }
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Latest job'),
          const SizedBox(height: 8),
          Text(
            job!.headline ?? job!.status,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${job!.kind} · ${job!.status} · attempt ${job!.attempts}',
            style: const TextStyle(color: DavidColors.muted),
          ),
          const SizedBox(height: 6),
          Text(
            'Queue wait ${_ms(job!.queueWaitMs)} · end to end ${_ms(job!.e2eMs)}',
            style: const TextStyle(color: DavidColors.muted),
          ),
          if (job!.detail != null) ...[
            const SizedBox(height: 8),
            Text(job!.detail!, style: const TextStyle(height: 1.4)),
          ],
          if (job!.error != null) ...[
            const SizedBox(height: 8),
            Text(
              job!.error!,
              style: const TextStyle(color: DavidColors.coral, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

String _ms(double? value) {
  if (value == null) {
    return 'n/a';
  }
  return '${value.round()} ms';
}
