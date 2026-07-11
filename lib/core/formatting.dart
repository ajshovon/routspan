/// Human-readable byte formatting for data-usage counters.
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final fixed =
      unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(decimals);
  return '$fixed ${units[unit]}';
}

/// Parse an int that the ZTE API may return as a String, num, or null.
int parseIntSafe(Object? value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim()) ?? fallback;
}

/// Like [parseIntSafe] but returns null for null/empty/unparseable values.
/// The ZTE API returns "" for fields a given model doesn't populate (e.g. the
/// M100 leaves `battery_value` empty), which should render as "unknown".
int? parseIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return int.tryParse(s);
}
