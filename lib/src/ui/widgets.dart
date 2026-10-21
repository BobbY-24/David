import 'package:flutter/material.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import 'theme.dart';

const runDiligenceKey = ValueKey<String>('run-diligence');
const retrievalQueryKey = ValueKey<String>('retrieval-query');
const retrievalSearchKey = ValueKey<String>('retrieval-search');
const tabStripKey = ValueKey<String>('tab-strip');

class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(values: values, color: color),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final dot = Paint()..color = color;

    var minValue = values.first;
    var maxValue = values.first;
    for (final value in values) {
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
    final span = (maxValue - minValue).abs() < 0.0001
        ? 1.0
        : maxValue - minValue;
    final count = values.length;
    Offset pointAt(int index) {
      final x = count == 1 ? size.width / 2 : size.width * index / (count - 1);
      final y =
          size.height -
          6 -
          ((values[index] - minValue) / span) * (size.height - 12);
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < count; i++) {
      path.lineTo(pointAt(i).dx, pointAt(i).dy);
    }
    final area = Path.from(path)
      ..lineTo(pointAt(count - 1).dx, size.height)
      ..lineTo(pointAt(0).dx, size.height)
      ..close();
    canvas.drawPath(area, fill);
    canvas.drawPath(path, line);
    canvas.drawCircle(pointAt(count - 1), 3.2, dot);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: DavidColors.faint,
        fontSize: 11,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class EvidenceChip extends StatelessWidget {
  const EvidenceChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: Material(
        color: selected ? DavidColors.brass : DavidColors.panelRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(99),
          side: BorderSide(
            color: selected ? DavidColors.brass : DavidColors.line,
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
                color: selected ? DavidColors.brassInk : DavidColors.ink,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DavidColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DavidColors.line),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class EvidencePanel extends StatelessWidget {
  const EvidencePanel({super.key, required this.unit, required this.onClose});

  final EvidenceUnit unit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final value = formatValue(unit.numericValue, unit.unit);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DavidColors.panel,
        border: Border(left: BorderSide(color: DavidColors.line)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Row(
            children: [
              const Expanded(child: SectionLabel('Sealed evidence')),
              IconButton(
                tooltip: 'Close evidence',
                onPressed: onClose,
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: DavidColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            unit.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            unit.id,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: DavidColors.brass,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Meta(formatSourceKind(unit.sourceKind)),
              _Meta(formatModality(unit.modality)),
              _Meta(unit.source),
              if (value.isNotEmpty) _Meta(value),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatStamp(unit.observedAt),
            style: const TextStyle(color: DavidColors.muted),
          ),
          Text(unit.site, style: const TextStyle(color: DavidColors.muted)),
          const SizedBox(height: 14),
          Text(unit.text, style: const TextStyle(height: 1.45)),
          const SizedBox(height: 16),
          const SectionLabel('Provenance'),
          const SizedBox(height: 8),
          for (final step in unit.provenance) ...[
            Text(
              '${step.action} · ${step.actor}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              formatStamp(step.at),
              style: const TextStyle(color: DavidColors.faint, fontSize: 12),
            ),
            Text(
              step.note,
              style: const TextStyle(color: DavidColors.muted, height: 1.4),
            ),
            const SizedBox(height: 10),
          ],
          if (unit.metadata.isNotEmpty) ...[
            const SectionLabel('Metadata'),
            const SizedBox(height: 8),
            for (final entry in unit.metadata.entries)
              Text(
                '${entry.key}: ${entry.value}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DavidColors.panelRaised,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: DavidColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: DavidColors.ink),
        ),
      ),
    );
  }
}

class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: DavidColors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}
