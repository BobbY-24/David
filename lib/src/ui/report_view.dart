import 'package:flutter/material.dart';

import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class ReportView extends StatelessWidget {
  const ReportView({super.key, required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final run = desk.run;
    if (run == null || run.caseId != desk.current.id) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: const [
          EmptyNote(
            title: 'No memo yet',
            body: 'Run diligence to draft a decision memo. Findings will cite evidence ids from this run, and the recommended action follows the lead risk only when the margin clears.',
          ),
        ],
      );
    }

    final report = run.report;
    final engagement = desk.current;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (run.control.approvalRequired)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: EmptyNote(
              title: 'Approval hold',
              body: 'This run cannot pay, sign, place an order, or contact the counterparty. A person has to approve the memo before any of those actions.',
            ),
          ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SelectionArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DavidColors.memo,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DECISION MEMO',
                        style: TextStyle(
                          color: DavidColors.memoMuted,
                          letterSpacing: 1.4,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        engagement.title,
                        style: const TextStyle(
                          color: DavidColors.memoInk,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        engagement.subject,
                        style: const TextStyle(
                          color: DavidColors.memoMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(height: 1, color: DavidColors.memoRule),
                      const SizedBox(height: 14),
                      Text(
                        report.headline,
                        style: const TextStyle(
                          color: DavidColors.memoInk,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${report.resolved ? 'Resolved' : 'Unresolved'} · confidence ${(report.confidence * 100).round()}% · ${run.policyId}',
                        style: const TextStyle(
                          color: DavidColors.memoMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        report.decisionNote,
                        style: const TextStyle(
                          color: DavidColors.memoInk,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _MemoLabel('Recommended action'),
                      const SizedBox(height: 6),
                      Text(
                        report.recommendedAction,
                        style: const TextStyle(
                          color: DavidColors.memoInk,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _MemoLabel('Findings'),
                      const SizedBox(height: 6),
                      for (final finding in report.findings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            finding,
                            style: const TextStyle(
                              color: DavidColors.memoInk,
                              height: 1.45,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const _MemoLabel('Competing risks'),
                      const SizedBox(height: 6),
                      for (final line in report.competitors)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            line,
                            style: const TextStyle(
                              color: DavidColors.memoInk,
                              height: 1.45,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const _MemoLabel('Gaps'),
                      const SizedBox(height: 6),
                      for (final gap in report.gaps)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            gap,
                            style: const TextStyle(
                              color: DavidColors.memoInk,
                              height: 1.4,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const _MemoLabel('Next collection'),
                      const SizedBox(height: 6),
                      for (final item in report.nextCollections)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            item,
                            style: const TextStyle(
                              color: DavidColors.memoInk,
                              height: 1.4,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      const _MemoLabel('Citations in this run'),
                      const SizedBox(height: 8),
                      Wrap(
                        children: [
                          for (final id in report.citedEvidenceIds)
                            EvidenceChip(
                              label: id,
                              selected: desk.selectedEvidenceId == id,
                              onTap: () => desk.selectEvidence(id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        run.usedModel
                            ? 'Decision support only, not legal, credit, or investment advice. ${run.modelId} weighed the evidence on your key (${run.inputTokens} tokens in, ${run.outputTokens} out). Every citation was checked against what this run retrieved, and David computed the decision from the weights.'
                            : 'Decision support only, not legal, credit, or investment advice. The demo provider ranks sealed fixture evidence and did not call a live model.',
                        style: const TextStyle(
                          color: DavidColors.memoMuted,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MemoLabel extends StatelessWidget {
  const _MemoLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: DavidColors.memoMuted,
        fontSize: 11,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
