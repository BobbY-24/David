import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class ExplanationsView extends StatelessWidget {
  const ExplanationsView({super.key, required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final run = desk.run;
    if (run == null || run.caseId != desk.current.id) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: const [
          EmptyNote(
            title: 'Explanations are not scored yet',
            body: 'The case already lists the competing explanations. Run the investigation to score each one against retrieved evidence only. A negated mention does not count as support.',
          ),
        ],
      );
    }

    final maxAbs = run.judgments.fold<double>(1, (max, judgment) {
      final abs = judgment.net.abs();
      return abs > max ? abs : max;
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const Text(
          'Ranked by support minus falsifiers. Evidence chips open the sealed unit.',
          style: TextStyle(color: DavidColors.muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < run.judgments.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _JudgmentCard(
              rank: i + 1,
              judgment: run.judgments[i],
              maxAbs: maxAbs,
              lead:
                  run.report.resolved &&
                  run.report.leadHypothesisId == run.judgments[i].hypothesisId,
              selectedId: desk.selectedEvidenceId,
              onSelect: desk.selectEvidence,
            ),
          ),
      ],
    );
  }
}

class _JudgmentCard extends StatelessWidget {
  const _JudgmentCard({
    required this.rank,
    required this.judgment,
    required this.maxAbs,
    required this.lead,
    required this.selectedId,
    required this.onSelect,
  });

  final int rank;
  final HypothesisJudgment judgment;
  final double maxAbs;
  final bool lead;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final fraction = (judgment.net / maxAbs).clamp(-1.0, 1.0).toDouble();
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                rank.toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: DavidColors.faint,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  judgment.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (lead) const _LeadMark(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            judgment.statement,
            style: const TextStyle(height: 1.4, color: DavidColors.muted),
          ),
          const SizedBox(height: 10),
          _NetBar(fraction: fraction),
          const SizedBox(height: 6),
          Text(
            'support ${judgment.supportScore.toStringAsFixed(2)} · falsifiers ${judgment.contradictScore.toStringAsFixed(2)} · net ${judgment.net.toStringAsFixed(2)}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: DavidColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 640;
              final support = _PhraseColumn(
                title: 'Supported by',
                phrases: judgment.matchedSupport,
                empty: 'No support phrase in the retrieved set.',
                hits: judgment.supporting,
                selectedId: selectedId,
                onSelect: onSelect,
                color: DavidColors.sage,
              );
              final against = _PhraseColumn(
                title: 'Challenged by',
                phrases: judgment.matchedContradict,
                empty: 'No falsifier in the retrieved set.',
                hits: judgment.contradicting,
                selectedId: selectedId,
                onSelect: onSelect,
                color: DavidColors.coral,
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [support, const SizedBox(height: 12), against],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: support),
                  const SizedBox(width: 16),
                  Expanded(child: against),
                ],
              );
            },
          ),
          if (judgment.missingSupport.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Still missing: ${judgment.missingSupport.join('; ')}.',
              style: const TextStyle(
                color: DavidColors.faint,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeadMark extends StatelessWidget {
  const _LeadMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DavidColors.amber,
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'Lead',
          style: TextStyle(
            color: DavidColors.amberInk,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _NetBar extends StatelessWidget {
  const _NetBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: CustomPaint(painter: _NetPainter(fraction)),
    );
  }
}

class _NetPainter extends CustomPainter {
  _NetPainter(this.fraction);

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()..color = DavidColors.line;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(99)),
      track,
    );
    final mid = size.width / 2;
    final color = fraction >= 0 ? DavidColors.sage : DavidColors.coral;
    final width = (size.width / 2) * fraction.abs();
    final rect = fraction >= 0
        ? Rect.fromLTWH(mid, 0, width, size.height)
        : Rect.fromLTWH(mid - width, 0, width, size.height);
    canvas.drawRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _NetPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

class _PhraseColumn extends StatelessWidget {
  const _PhraseColumn({
    required this.title,
    required this.phrases,
    required this.empty,
    required this.hits,
    required this.selectedId,
    required this.onSelect,
    required this.color,
  });

  final String title;
  final List<String> phrases;
  final String empty;
  final List<RetrievalHit> hits;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          phrases.isEmpty ? empty : phrases.join(' · '),
          style: const TextStyle(fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 6),
        Wrap(
          children: [
            for (final hit in hits)
              EvidenceChip(
                label: hit.unit.id,
                selected: selectedId == hit.unit.id,
                onTap: () => onSelect(hit.unit.id),
              ),
          ],
        ),
      ],
    );
  }
}
