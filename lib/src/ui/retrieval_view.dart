import 'package:flutter/material.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class RetrievalView extends StatefulWidget {
  const RetrievalView({super.key, required this.desk});

  final DeskController desk;

  @override
  State<RetrievalView> createState() => _RetrievalViewState();
}

class _RetrievalViewState extends State<RetrievalView> {
  late final TextEditingController _query;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.desk.queryText);
  }

  @override
  void didUpdateWidget(RetrievalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_query.text != widget.desk.queryText) {
      _query.value = TextEditingValue(
        text: widget.desk.queryText,
        selection: TextSelection.collapsed(
          offset: widget.desk.queryText.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desk = widget.desk;
    final caseFile = desk.current;
    final modalities =
        caseFile.evidence.map((unit) => unit.modality).toSet().toList()..sort();
    final maxScore = desk.manualHits.fold<double>(
      0,
      (max, hit) => hit.score > max ? hit.score : max,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const Text(
          'Same index the agent searches. Filters run before BM25. A blank query browses the newest sealed units and does not pretend to be a text match.',
          style: TextStyle(color: DavidColors.muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final example in caseFile.exampleQueries)
              ActionChip(
                label: Text(example),
                backgroundColor: DavidColors.panel,
                side: const BorderSide(color: DavidColors.line),
                labelStyle: const TextStyle(
                  color: DavidColors.ink,
                  fontSize: 12,
                ),
                onPressed: () => desk.useExample(example),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: retrievalQueryKey,
          controller: _query,
          onChanged: desk.setQueryText,
          onSubmitted: (_) => desk.searchManual(),
          style: const TextStyle(color: DavidColors.ink),
          decoration: const InputDecoration(
            hintText: 'Search observations, records, sensors, sites',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Dropdown<String?>(
              value: desk.modalityFilter,
              hint: 'Any modality',
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Any modality'),
                ),
                for (final modality in modalities)
                  DropdownMenuItem(
                    value: modality,
                    child: Text(formatModality(modality)),
                  ),
              ],
              onChanged: desk.setModalityFilter,
            ),
            _Dropdown<SourceKind?>(
              value: desk.kindFilter,
              hint: 'Any source',
              items: const [
                DropdownMenuItem<SourceKind?>(
                  value: null,
                  child: Text('Any source'),
                ),
                DropdownMenuItem(
                  value: SourceKind.sensorObservation,
                  child: Text('Sensor'),
                ),
                DropdownMenuItem(
                  value: SourceKind.record,
                  child: Text('Record'),
                ),
              ],
              onChanged: desk.setKindFilter,
            ),
            FilledButton(
              key: retrievalSearchKey,
              onPressed: desk.searchManual,
              child: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!desk.manualSearched)
          const EmptyNote(
            title: 'Index is ready',
            body: 'Try a phrase from the brief, or one of the example chips. Hits keep the evidence id and the seal.',
          )
        else if (desk.manualHits.isEmpty)
          const EmptyNote(
            title: 'No evidence matched',
            body: 'Nothing sealed in this case survived the query and filters. Try a modality chip or a shorter phrase.',
          )
        else ...[
          Text(
            desk.queryText.trim().isEmpty
                ? '${desk.manualHits.length} newest units in this filter. Scores are zero because there was no query text.'
                : '${desk.manualHits.length} hits, highest score first.',
            style: const TextStyle(color: DavidColors.muted),
          ),
          const SizedBox(height: 10),
          for (final hit in desk.manualHits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _HitCard(
                hit: hit,
                maxScore: maxScore,
                selected: desk.selectedEvidenceId == hit.unit.id,
                onTap: () => desk.selectEvidence(hit.unit.id),
              ),
            ),
        ],
      ],
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DavidColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DavidColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint),
          dropdownColor: DavidColors.panelRaised,
          underline: const SizedBox.shrink(),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({
    required this.hit,
    required this.maxScore,
    required this.selected,
    required this.onTap,
  });

  final RetrievalHit hit;
  final double maxScore;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fraction = maxScore <= 0
        ? 0.0
        : (hit.score / maxScore).clamp(0.0, 1.0);
    return Material(
      color: DavidColors.panel,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hit.unit.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    hit.score.toStringAsFixed(2),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: DavidColors.amber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${hit.unit.id} · ${formatModality(hit.unit.modality)} · ${hit.unit.source}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: DavidColors.muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  value: fraction.toDouble(),
                  backgroundColor: DavidColors.line,
                  color: DavidColors.sage,
                ),
              ),
              const SizedBox(height: 8),
              Text(excerpt(hit.unit.text), style: const TextStyle(height: 1.4)),
              if (hit.matchedTerms.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Matched ${hit.matchedTerms.join(', ')}',
                  style: const TextStyle(
                    color: DavidColors.sage,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
