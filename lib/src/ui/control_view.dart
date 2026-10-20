import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class ControlView extends StatelessWidget {
  const ControlView({super.key, required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final run = desk.run;
    if (run == null || run.caseId != desk.current.id) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: const [
          EmptyNote(
            title: 'No control record yet',
            body: 'Run diligence. The router will pick plan-and-execute, ReAct, or a panel vote, and the gateway will audit every search.',
          ),
        ],
      );
    }
    final control = run.control;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          control.loopLabel,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(control.reason, style: const TextStyle(height: 1.45)),
        const SizedBox(height: 8),
        Text(
          control.standard,
          style: const TextStyle(color: DavidColors.muted, height: 1.45),
        ),
        if (control.escalated) ...[
          const SizedBox(height: 8),
          const Text(
            'Escalated after the first loop.',
            style: TextStyle(
              color: DavidColors.amber,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Stat('${control.toolCalls} / ${control.toolBudget} tool calls'),
            _Stat(
              control.batched ? 'Searches batched' : 'Searches interleaved',
            ),
            _Stat(
              control.approvalRequired
                  ? 'Approval required'
                  : 'No approval hold',
            ),
            _Stat('${control.restrictedEvidenceIds.length} restricted'),
            _Stat('${control.quarantinedEvidenceIds.length} quarantined'),
          ],
        ),
        const SizedBox(height: 18),
        const SectionLabel('Guardrails'),
        const SizedBox(height: 8),
        for (final rail in control.guardrails)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${switch (rail.verdict) {
                      RailVerdict.pass => 'Pass',
                      RailVerdict.flag => 'Flag',
                      RailVerdict.block => 'Block',
                    }} · ${rail.rail} · ${rail.name}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: switch (rail.verdict) {
                        RailVerdict.pass => DavidColors.sage,
                        RailVerdict.flag => DavidColors.amber,
                        RailVerdict.block => DavidColors.coral,
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rail.detail,
                    style: const TextStyle(
                      height: 1.4,
                      color: DavidColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (control.votes.isNotEmpty) ...[
          const SizedBox(height: 8),
          const SectionLabel('Seats'),
          const SizedBox(height: 8),
          for (final vote in control.votes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PanelCard(
                child: Text(
                  '${vote.seatTitle}: ${vote.riskTitle} · net ${vote.net.toStringAsFixed(2)}',
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        const SectionLabel('Tool audit'),
        const SizedBox(height: 8),
        Text(
          'Principal ${control.principalId}. ${control.approvalNote}',
          style: const TextStyle(color: DavidColors.muted, height: 1.4),
        ),
        const SizedBox(height: 8),
        if (control.audit.isEmpty)
          const EmptyNote(
            title: 'No tool calls',
            body: 'The input rail stopped the run before a search.',
          )
        else
          for (final event in control.audit)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${event.seq.toString().padLeft(2, '0')} · ${event.decision} · ${event.tool}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.redactedQuery,
                      style: const TextStyle(height: 1.35),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.hash.substring(0, 12),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: DavidColors.faint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
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
