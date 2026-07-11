// ZTE SMS/USSD text is carried as UTF-16BE encoded into a hex string
// (4 hex chars per UTF-16 code unit). Verified on the OLAX M100: inbox
// `content` and USSD `ussd_data_info` are both this format.

/// Hex (UTF-16BE) → Dart String. Returns the input unchanged if it isn't
/// valid hex (some short status strings come through as plain text).
String decodeUcs2Hex(String hex) {
  final clean = hex.trim();
  if (clean.isEmpty) return '';
  if (clean.length % 4 != 0) return hex;
  final units = <int>[];
  for (var i = 0; i + 4 <= clean.length; i += 4) {
    final code = int.tryParse(clean.substring(i, i + 4), radix: 16);
    if (code == null) return hex;
    units.add(code);
  }
  return String.fromCharCodes(units);
}

/// Dart String → hex (UTF-16BE), the form SEND_SMS expects for MessageBody.
String encodeUcs2Hex(String text) {
  final b = StringBuffer();
  for (final unit in text.codeUnits) {
    b.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
  }
  return b.toString();
}
