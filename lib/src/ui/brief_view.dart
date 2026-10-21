import 'package:flutter/material.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class BriefView extends StatelessWidget {
  const BriefView({super.key, required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final engagement = desk.current;
    final metrics = engagement.evidence
        .where((unit) => unit.sourceKind == SourceKind.metric)
        .length;
    final records = engagement.evidence.length - metrics;
    final series = engagement.evidence
        .map((unit) => unit.seriesId)
        .whereType<String>()
        .toSet();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          engagement.summary,
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Stat('$metrics metric points'),
            _Stat('$records records'),
            _Stat('${series.length} series'),
            _Stat(engagement.site),
          ],
        ),
        const SizedBox(height: 22),
        const SectionLabel('Decision criteria'),
        const SizedBox(height: 8),
        for (final criterion in engagement.decisionCriteria)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7, right: 8),
                  child: Icon(Icons.circle, size: 6, color: DavidColors.brass),
                ),
                Expanded(
                  child: Text(criterion, style: const TextStyle(height: 1.4)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const SectionLabel('Retrieval plan the agent will run'),
        const SizedBox(height: 8),
        for (final pass in engagement.plan)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pass.purpose,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pass.text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: DavidColors.positive,
                      fontSize: 13,
                    ),
                  ),
                  if (pass.modality != null || pass.sourceKind != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        [
                          if (pass.modality != null)
                            'modality ${pass.modality}',
                          if (pass.sourceKind != null)
                            'source ${formatSourceKind(pass.sourceKind!)}',
                        ].join(' · '),
                        style: const TextStyle(
                          color: DavidColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        const SectionLabel('Risk questions on the table'),
        const SizedBox(height: 8),
        for (final risk in engagement.riskQuestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(risk.title, style: const TextStyle(height: 1.4)),
          ),
        const SizedBox(height: 8),
        Text(
          'Required modalities: ${engagement.expectedModalities.map(formatModality).join(', ')}.',
          style: const TextStyle(color: DavidColors.muted, height: 1.4),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DavidColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DavidColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
