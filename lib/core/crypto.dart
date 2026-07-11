import 'dart:convert';

import 'package:crypto/crypto.dart';

/// ZTE-lineage authentication helpers.
///
/// IMPORTANT: the exact recipe (hex vs base64, upper vs lower case, whether the
/// raw password is pre-hashed) VARIES BY FIRMWARE BUILD. These are the most
/// commonly documented defaults. Confirm against your own capture — see
/// `docs/olax-m100-api.md` §2/§3 — and adjust here if needed.

String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

String md5Hex(String input) => md5.convert(utf8.encode(input)).toString();

String sha256HexUpper(String input) => sha256Hex(input).toUpperCase();

/// Base64 of the raw password — the fallback recipe some firmware uses when no
/// LD token is issued.
String base64Password(String password) => base64.encode(utf8.encode(password));

/// Default ZTE login digest:
///   SHA256_HEX_UPPER( SHA256_HEX_UPPER(password) + LD )
/// If your capture shows a plain base64 password, use [base64Password] instead
/// (the transport falls back to it automatically when LD is empty).
String zteLoginDigest(String password, String ld) =>
    sha256HexUpper(sha256HexUpper(password) + ld);

/// Default ZTE `AD` anti-CSRF token:
///   MD5_HEX( MD5_HEX(cr_version + wa_inner_version) + RD )
/// Some builds upper-case the MD5 output — flip [upper] if writes are rejected.
String zteAd(
  String crVersion,
  String waInnerVersion,
  String rd, {
  bool upper = false,
}) {
  final inner = md5Hex(crVersion + waInnerVersion);
  final ad = md5Hex(inner + rd);
  return upper ? ad.toUpperCase() : ad;
}
