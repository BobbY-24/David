import 'package:flutter/material.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class ObservationsView extends StatelessWidget {
  const ObservationsView({super.key, required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final caseFile = desk.current;
    final modalities =
        caseFile.evidence.map((unit) => unit.modality).toSet().toList()..sort();
    final visible = caseFile.evidence.where((unit) {
      return desk.observationModality == 'all' ||
          unit.modality == desk.observationModality;
    }).toList();
    final seriesIds =
        visible
            .map((unit) => unit.seriesId)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final records = visible.where((unit) => unit.seriesId == null).toList()
      ..sort((a, b) => a.observedAt.compareTo(b.observedAt));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const Text(
          'Sensor readings stay attached to the instrument, the clock, and the ingest seal. Open a point to read provenance.',
          style: TextStyle(color: DavidColors.muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _FilterChip(
              label: 'All',
              selected: desk.observationModality == 'all',
              onTap: () => desk.setObservationModality('all'),
            ),
            for (final modality in modalities)
              _FilterChip(
                label: formatModality(modality),
                selected: desk.observationModality == modality,
                onTap: () => desk.setObservationModality(modality),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (seriesIds.isEmpty && records.isEmpty)
          const EmptyNote(
            title: 'No sealed observations',
            body: 'This filter has no sensor series and no records.',
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final seriesId in seriesIds)
                  SizedBox(
                    width: width,
                    child: _SeriesCard(
                      units:
                          visible
                              .where((unit) => unit.seriesId == seriesId)
                              .toList()
                            ..sort(
                              (a, b) => a.observedAt.compareTo(b.observedAt),
                            ),
                      selectedId: desk.selectedEvidenceId,
                      onSelect: desk.selectEvidence,
                    ),
                  ),
              ],
            );
          },
        ),
        if (records.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionLabel('Records'),
          const SizedBox(height: 8),
          for (final unit in records)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecordTile(
                unit: unit,
                selected: desk.selectedEvidenceId == unit.id,
                onTap: () => desk.selectEvidence(unit.id),
              ),
            ),
        ],
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DavidColors.amber : DavidColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(99),
        side: BorderSide(
          color: selected ? DavidColors.amber : DavidColors.line,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? DavidColors.amberInk : DavidColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.units,
    required this.selectedId,
    required this.onSelect,
  });

  final List<EvidenceUnit> units;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final latest = units.last;
    final first = units.first.numericValue;
    final last = latest.numericValue;
    final delta = first == null || last == null ? null : last - first;
    final rising = delta != null && delta.abs() > 0.0001;
    final color = rising && delta > 0 ? DavidColors.amber : DavidColors.sage;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            latest.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            '${latest.source} · ${formatModality(latest.modality)}',
            style: const TextStyle(color: DavidColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                formatValue(last, latest.unit),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (delta != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} from first',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Sparkline(
            values: [
              for (final unit in units)
                if (unit.numericValue != null) unit.numericValue!,
            ],
            color: color,
          ),
          const SizedBox(height: 8),
          for (final unit in units)
            InkWell(
              onTap: () => onSelect(unit.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatStamp(unit.observedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: selectedId == unit.id
                              ? DavidColors.amber
                              : DavidColors.muted,
                        ),
                      ),
                    ),
                    Text(
                      formatValue(unit.numericValue, unit.unit),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.unit,
    required this.selected,
    required this.onTap,
  });

  final EvidenceUnit unit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DavidColors.panelRaised : DavidColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? DavidColors.amber : DavidColors.line,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unit.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${unit.source} · ${formatStamp(unit.observedAt)}',
                style: const TextStyle(color: DavidColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                excerpt(unit.text, 180),
                style: const TextStyle(height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
