import 'package:flutter/material.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../state/desk_controller.dart';
import '../jobs/job_client.dart';
import 'agent_view.dart';
import 'brief_view.dart';
import 'control_view.dart';
import 'risks_view.dart';
import 'jobs_view.dart';
import 'evidence_view.dart';
import 'report_view.dart';
import 'retrieval_view.dart';
import 'theme.dart';
import 'widgets.dart';

class DeskPage extends StatefulWidget {
  const DeskPage({super.key, this.jobClient});

  final JobClient? jobClient;

  @override
  State<DeskPage> createState() => _DeskPageState();
}

class _DeskPageState extends State<DeskPage> {
  late final DeskController desk;

  @override
  void initState() {
    super.initState();
    desk = DeskController(jobClient: widget.jobClient);
  }

  @override
  void dispose() {
    desk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: desk,
      builder: (context, _) {
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final showSide =
                  constraints.maxWidth >= 1180 && desk.selected != null;
              return Column(
                children: [
                  const _TopBar(),
                  if (desk.error != null) _ErrorBanner(message: desk.error!),
                  Expanded(
                    child: Row(
                      children: [
                        if (wide)
                          SizedBox(
                            width: 280,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                border: Border(
                                  right: BorderSide(color: DavidColors.line),
                                ),
                              ),
                              child: CaseRail(desk: desk),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!wide)
                                SizedBox(
                                  height: 118,
                                  child: CaseRail(desk: desk, compact: true),
                                ),
                              _CaseHeader(desk: desk),
                              _TabStrip(desk: desk),
                              Expanded(child: _tabBody(desk)),
                              if (!showSide && desk.selected != null)
                                SizedBox(
                                  height: 230,
                                  child: EvidencePanel(
                                    unit: desk.selected!,
                                    onClose: () => desk.selectEvidence(null),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (showSide)
                          SizedBox(
                            width: 340,
                            child: EvidencePanel(
                              unit: desk.selected!,
                              onClose: () => desk.selectEvidence(null),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _tabBody(DeskController desk) {
    return switch (desk.tab) {
      DeskTab.brief => BriefView(desk: desk),
      DeskTab.evidence => EvidenceView(desk: desk),
      DeskTab.retrieve => RetrievalView(desk: desk),
      DeskTab.agent => AgentView(desk: desk),
      DeskTab.risks => RisksView(desk: desk),
      DeskTab.report => ReportView(desk: desk),
      DeskTab.control => ControlView(desk: desk),
      DeskTab.jobs => JobsView(desk: desk),
    };
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DavidColors.panel,
        border: Border(bottom: BorderSide(color: DavidColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showTagline = constraints.maxWidth >= 760;
            return Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: DavidColors.amber,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'DAVID',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    fontSize: 16,
                  ),
                ),
                if (showTagline) ...[
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Due diligence for one-person companies',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: DavidColors.muted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Synthetic fixtures',
                    style: TextStyle(color: DavidColors.faint, fontSize: 12),
                  ),
                ] else
                  const Spacer(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF3A221C),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(message, style: const TextStyle(color: DavidColors.coral)),
      ),
    );
  }
}

class CaseRail extends StatelessWidget {
  const CaseRail({super.key, required this.desk, this.compact = false});

  final DeskController desk;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: desk.cases.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 240,
            child: _CaseTile(
              engagement: desk.cases[index],
              selected: index == desk.caseIndex,
              onTap: () => desk.selectCase(index),
            ),
          );
        },
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(6, 4, 6, 10),
          child: SectionLabel('Engagements'),
        ),
        for (var index = 0; index < desk.cases.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CaseTile(
              engagement: desk.cases[index],
              selected: index == desk.caseIndex,
              onTap: () => desk.selectCase(index),
            ),
          ),
      ],
    );
  }
}

class _CaseTile extends StatelessWidget {
  const _CaseTile({
    required this.engagement,
    required this.selected,
    required this.onTap,
  });

  final Engagement engagement;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kindColor = engagement.dealType == DealType.acquisition
        ? DavidColors.mist
        : DavidColors.amber;
    return Material(
      color: selected ? DavidColors.panelRaised : DavidColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? kindColor : DavidColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatDealType(engagement.dealType).toUpperCase(),
                style: TextStyle(
                  color: kindColor,
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                engagement.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                engagement.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: DavidColors.muted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaseHeader extends StatelessWidget {
  const _CaseHeader({required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final engagement = desk.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 720;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${formatDealType(engagement.dealType)} · opened ${formatStamp(engagement.openedAt)}',
                style: const TextStyle(color: DavidColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                engagement.title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(engagement.question, style: const TextStyle(height: 1.4)),
            ],
          );
          final button = FilledButton(
            key: runDiligenceKey,
            onPressed: desk.running ? null : desk.runDiligence,
            child: Text(desk.running ? 'Running…' : 'Run diligence'),
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 12), button],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: copy),
              const SizedBox(width: 16),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (DeskTab.brief, 'Brief'),
      (DeskTab.evidence, 'Evidence'),
      (DeskTab.retrieve, 'Retrieve'),
      (DeskTab.agent, 'Agent'),
      (DeskTab.risks, 'Risks'),
      (DeskTab.report, 'Report'),
      (DeskTab.control, 'Control'),
      (DeskTab.jobs, 'Jobs'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DavidColors.line)),
      ),
      child: SingleChildScrollView(
        key: tabStripKey,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final tab in tabs)
              _TabButton(
                label: tab.$2,
                selected: desk.tab == tab.$1,
                onTap: () => desk.selectTab(tab.$1),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? DavidColors.amber : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? DavidColors.ink : DavidColors.muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
