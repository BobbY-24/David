import 'models.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatStamp(DateTime value) {
  final date = value.toUtc();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_months[date.month - 1]} ${date.day}, ${date.year} $hour:$minute UTC';
}

String formatDealType(DealType type) {
  return switch (type) {
    DealType.customer => 'New customer',
    DealType.vendor => 'Vendor',
    DealType.partner => 'Partner',
    DealType.contractor => 'Contractor',
    DealType.acquisition => 'Acquisition',
    DealType.lease => 'Lease',
  };
}

String formatSourceKind(SourceKind kind) {
  return switch (kind) {
    SourceKind.metric => 'Metric',
    SourceKind.record => 'Record',
  };
}

String formatModality(String modality) {
  return modality
      .split('-')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String excerpt(String text, [int max = 220]) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= max) {
    return flat;
  }
  return '${flat.substring(0, max - 1).trim()}…';
}

String formatValue(double? value, String? unit) {
  if (value == null) {
    return '';
  }
  final rounded = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  if (unit == null || unit.isEmpty) {
    return rounded;
  }
  return '$rounded $unit';
}
