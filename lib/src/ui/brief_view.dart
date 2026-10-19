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
    final caseFile = desk.current;
    final sensors = caseFile.evidence
        .where((unit) => unit.sourceKind == SourceKind.sensorObservation)
        .length;
    final records = caseFile.evidence.length - sensors;
    final series = caseFile.evidence
        .map((unit) => unit.seriesId)
        .whereType<String>()
        .toSet();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          caseFile.summary,
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Stat('$sensors sensor readings'),
            _Stat('$records records'),
            _Stat('${series.length} series'),
            _Stat(caseFile.site),
          ],
        ),
        const SizedBox(height: 22),
        const SectionLabel('Decision criteria'),
        const SizedBox(height: 8),
        for (final criterion in caseFile.decisionCriteria)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7, right: 8),
                  child: Icon(
                    Icons.circle,
                    size: 6,
                    color: FieldlineColors.amber,
                  ),
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
        for (final pass in caseFile.plan)
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
                      color: FieldlineColors.sage,
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
                          color: FieldlineColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        const SectionLabel('Competing explanations on the book'),
        const SizedBox(height: 8),
        for (final hypothesis in caseFile.hypotheses)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(hypothesis.title, style: const TextStyle(height: 1.4)),
          ),
        const SizedBox(height: 8),
        Text(
          'Required modalities: ${caseFile.expectedModalities.map(formatModality).join(', ')}.',
          style: const TextStyle(color: FieldlineColors.muted, height: 1.4),
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
        color: FieldlineColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FieldlineColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
