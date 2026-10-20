import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class AgentView extends StatelessWidget {
  const AgentView({super.key, required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final run = desk.run;
    if (desk.running) {
      return const Center(
        child: Text(
          'Running the grounded policy…',
          style: TextStyle(color: DavidColors.amber),
        ),
      );
    }
    if (run == null || run.caseId != desk.current.id) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: const [
          EmptyNote(
            title: 'The agent has not run this case',
            body: 'Run investigation to scope the question, search the sealed corpus, probe each competing explanation, and write a memo. The trace below will show every search, including the falsifier probes.',
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          '${run.control.loopLabel} · ${run.steps.length} steps · ${run.retrieved.length} evidence units · ${run.policyId}',
          style: const TextStyle(color: DavidColors.muted),
        ),
        const SizedBox(height: 4),
        Text(run.control.reason, style: const TextStyle(height: 1.4)),
        const SizedBox(height: 12),
        for (var i = 0; i < run.steps.length; i++)
          _StepTile(
            index: i + 1,
            step: run.steps[i],
            selectedId: desk.selectedEvidenceId,
            onSelect: desk.selectEvidence,
            isLast: i == run.steps.length - 1,
          ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.step,
    required this.selectedId,
    required this.onSelect,
    required this.isLast,
  });

  final int index;
  final AgentStep step;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = switch (step.stage) {
      AgentStage.scope => DavidColors.mist,
      AgentStage.retrieve => DavidColors.sage,
      AgentStage.gap => DavidColors.amber,
      AgentStage.adjudicate => DavidColors.coral,
      AgentStage.report => DavidColors.ink,
    };
    final shown = step.evidenceIds.take(8).toList();
    final extra = step.evidenceIds.length - shown.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: isLast ? color : DavidColors.line, width: 2),
        ),
      ),
      child: PanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${step.stage.name.toUpperCase()} · $index'
              '${step.hypothesisProbe ? ' · PROBE' : ''}',
              style: TextStyle(
                color: color,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              step.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (step.query != null) ...[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: DavidColors.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    step.query!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: DavidColors.sage,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              step.detail,
              style: const TextStyle(height: 1.4, color: DavidColors.muted),
            ),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                children: [
                  for (final id in shown)
                    EvidenceChip(
                      label: id,
                      selected: selectedId == id,
                      onTap: () => onSelect(id),
                    ),
                  if (extra > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '+$extra',
                        style: const TextStyle(
                          color: DavidColors.faint,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
