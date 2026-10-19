import '../domain/models.dart';

DateTime utc(int year, int month, int day, int hour, [int minute = 0]) {
  return DateTime.utc(year, month, day, hour, minute);
}

class Reading {
  const Reading(this.at, this.value, {this.claim});

  final DateTime at;
  final double value;
  final String? claim;
}

List<ProvenanceStep> seal({
  required String collector,
  required DateTime at,
  required String id,
  String? note,
}) {
  return [
    ProvenanceStep(
      actor: collector,
      action: 'collect',
      at: at,
      note: note ?? 'Captured at the source clock and handed to ingest.',
    ),
    ProvenanceStep(
      actor: 'fieldline-ingest',
      action: 'seal',
      at: at.add(const Duration(minutes: 6)),
      note: 'Synthetic fixture seal $id. Not a field hash of a live site.',
    ),
  ];
}

List<EvidenceUnit> readingSeries({
  required String caseId,
  required String idPrefix,
  required String seriesId,
  required String title,
  required String modality,
  required String source,
  required String site,
  required String unit,
  required String collector,
  required List<Reading> readings,
}) {
  return [
    for (var i = 0; i < readings.length; i++)
      EvidenceUnit(
        id: '$idPrefix-$i',
        caseId: caseId,
        sourceKind: SourceKind.sensorObservation,
        title: title,
        text: _readingText(readings[i], unit),
        observedAt: readings[i].at,
        site: site,
        modality: modality,
        source: source,
        seriesId: seriesId,
        numericValue: readings[i].value,
        unit: unit,
        metadata: {
          'series': seriesId,
          'value': readings[i].value.toString(),
          'unit': unit,
        },
        provenance: seal(
          collector: collector,
          at: readings[i].at,
          id: '$idPrefix-$i',
        ),
      ),
  ];
}

String _readingText(Reading reading, String unit) {
  final base = 'Recorded ${reading.value} $unit.';
  final claim = reading.claim;
  if (claim == null || claim.isEmpty) {
    return base;
  }
  return '$base $claim';
}

EvidenceUnit record({
  required String id,
  required String caseId,
  required String title,
  required String text,
  required DateTime observedAt,
  required String site,
  required String modality,
  required String source,
  required String collector,
  Map<String, String> metadata = const {},
}) {
  return EvidenceUnit(
    id: id,
    caseId: caseId,
    sourceKind: SourceKind.record,
    title: title,
    text: text,
    observedAt: observedAt,
    site: site,
    modality: modality,
    source: source,
    metadata: metadata,
    provenance: seal(collector: collector, at: observedAt, id: id),
  );
}
