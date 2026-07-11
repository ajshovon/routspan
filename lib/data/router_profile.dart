import 'dart:convert';

/// A saved router the user can connect to. Passwords are NOT stored here — they
/// live in secure storage (see `ProfileStore`), keyed by [id].
class RouterProfile {
  const RouterProfile({
    required this.id,
    required this.name,
    required this.host,
    this.reqproc = true,
  });

  /// Stable opaque id; also the secure-storage password key suffix.
  final String id;

  /// User-facing label, e.g. "Home OLAX".
  final String name;

  /// Admin IP/host, e.g. "192.168.8.1".
  final String host;

  /// Newer ZTE "reqproc" dialect (true for OLAX M100); false = legacy goform.
  final bool reqproc;

  RouterProfile copyWith({String? name, String? host, bool? reqproc}) =>
      RouterProfile(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        reqproc: reqproc ?? this.reqproc,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'host': host, 'reqproc': reqproc};

  factory RouterProfile.fromJson(Map<String, dynamic> j) => RouterProfile(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        host: (j['host'] ?? '').toString(),
        reqproc: j['reqproc'] == null ? true : j['reqproc'] == true,
      );

  static String encodeList(List<RouterProfile> list) =>
      jsonEncode([for (final p in list) p.toJson()]);

  static List<RouterProfile> decodeList(String? s) {
    if (s == null || s.isEmpty) return const [];
    try {
      final raw = jsonDecode(s);
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map) RouterProfile.fromJson(Map<String, dynamic>.from(e)),
      ];
    } on FormatException {
      return const [];
    }
  }
}
