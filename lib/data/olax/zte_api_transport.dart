import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'package:routspan/core/crypto.dart';
import 'package:routspan/core/errors.dart';

/// Which ZTE API dialect the firmware speaks. Determined once during Phase 0
/// capture (see docs/olax-m100-api.md §0) — this is the single config point.
class ZteConfig {
  const ZteConfig({
    required this.getPath,
    required this.setPath,
    this.useAd = true,
    this.adUpper = false,
  });

  final String getPath;
  final String setPath;

  /// Whether write commands require the `AD` anti-CSRF token.
  final bool useAd;

  /// Some builds upper-case the AD/MD5 output.
  final bool adUpper;

  /// Older ZTE firmware: /goform/goform_get_cmd_process + goform_set_cmd_process
  static const goform = ZteConfig(
    getPath: '/goform/goform_get_cmd_process',
    setPath: '/goform/goform_set_cmd_process',
  );

  /// Newer ZTE firmware: /reqproc/proc_get + proc_post.
  /// The OLAX M100 (Server: Demo-Webs) builds POSTs as plain {goformId,...}
  /// with NO `AD` anti-CSRF token — verified by reading its firmware JS — so
  /// useAd is false here.
  static const reqproc = ZteConfig(
    getPath: '/reqproc/proc_get',
    setPath: '/reqproc/proc_post',
    useAd: false,
  );
}

/// Low-level ZTE HTTP transport. Handles the session cookie, the required
/// `Referer` header, the LD-based login digest and the RD/AD write token.
/// Knows nothing about "SMS" or "WiFi" — that mapping lives in [OlaxM100Client].
class ZteApiTransport {
  ZteApiTransport({required String host, ZteConfig? config})
      : _config = config ?? ZteConfig.goform,
        _origin = 'http://$host' {
    _dio = Dio(
      BaseOptions(
        baseUrl: _origin,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        // The API rejects requests whose Referer doesn't match the admin origin.
        headers: {
          'Referer': '$_origin/index.html',
          'X-Requested-With': 'XMLHttpRequest',
        },
        // The device returns JSON but sometimes with a text/html content-type.
        responseType: ResponseType.json,
      ),
    );
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  final ZteConfig _config;
  final String _origin;
  final CookieJar _cookieJar = CookieJar();
  late final Dio _dio;

  // Cached firmware versions for AD derivation (fetched once).
  Map<String, dynamic>? _version;
  String? _password; // kept in-memory for transparent re-login

  ZteConfig get config => _config;

  /// GET a single `cmd` value.
  Future<Map<String, dynamic>> get(String cmd) => getMulti([cmd]);

  /// GET several `cmd` values in one call (`multi_data=1`).
  Future<Map<String, dynamic>> getMulti(List<String> cmds) async {
    try {
      final res = await _dio.get<dynamic>(
        _config.getPath,
        queryParameters: {
          'isTest': 'false',
          'cmd': cmds.join(','),
          if (cmds.length > 1) 'multi_data': '1',
        },
      );
      return _asMap(res.data);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// GET with arbitrary query parameters (e.g. the SMS list needs `page`,
  /// `data_per_page`, `mem_store`, `tags`, `order_by` alongside `cmd`).
  Future<Map<String, dynamic>> getWithParams(Map<String, String> params) async {
    try {
      final res = await _dio.get<dynamic>(
        _config.getPath,
        queryParameters: {'isTest': 'false', ...params},
      );
      return _asMap(res.data);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// POST a write command. Adds `isTest`, and the `AD` token when required.
  /// [withAd] is false for LOGIN — verified that this firmware accepts login
  /// without an AD token (see docs/olax-m100-api.md §2).
  Future<Map<String, dynamic>> set(
    Map<String, String> form, {
    bool withAd = true,
  }) async {
    try {
      final body = <String, String>{'isTest': 'false', ...form};
      if (_config.useAd && withAd) {
        body['AD'] = await _computeAd();
      }
      final res = await _dio.post<dynamic>(
        _config.setPath,
        data: body,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return _asMap(res.data);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Full ZTE login handshake. See docs/olax-m100-api.md §2 — CONFIRM the recipe
  /// against your capture and adjust `core/crypto.dart` if it differs.
  Future<void> login(String password) async {
    _password = password;
    final ld = (await get('LD'))['LD']?.toString() ?? '';
    final digest =
        ld.isEmpty ? base64Password(password) : zteLoginDigest(password, ld);

    final res =
        await set({'goformId': 'LOGIN', 'password': digest}, withAd: false);
    final result = res['result']?.toString();
    // Success is commonly "0"; some builds return "success". CONFIRM in §2.
    if (result != '0' && result != 'success') {
      throw AuthException('Login rejected by device (result=$result)');
    }
  }

  /// Best-effort session check. The exact "logged in" field varies by firmware
  /// (e.g. `loginfo == "ok"`), so treat this as a heuristic — CONFIRM in §2.
  Future<bool> isLoggedIn() async {
    try {
      final res = await get('loginfo');
      final info = res['loginfo']?.toString();
      return info == 'ok' || info == '1';
    } on RouterException {
      return false;
    }
  }

  /// Re-login using the cached password, then run [action] again once.
  Future<T> withReloginRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException {
      final pw = _password;
      if (pw == null) rethrow;
      await login(pw);
      return action();
    }
  }

  Future<String> _computeAd() async {
    _version ??= await getMulti(['cr_version', 'wa_inner_version']);
    final rd = (await get('RD'))['RD']?.toString() ?? '';
    return zteAd(
      _version!['cr_version']?.toString() ?? '',
      _version!['wa_inner_version']?.toString() ?? '',
      rd,
      upper: _config.adUpper,
    );
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    // This firmware returns JSON with a text/html content-type, so Dio hands
    // it back as a raw String rather than auto-decoding it — parse it here.
    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) return const {};
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        // Fall through to the error below (e.g. an HTML error page).
      }
      throw const CommandFailedException('Non-JSON response from device');
    }
    if (data == null) return const {};
    throw CommandFailedException('Unexpected response: $data');
  }

  RouterException _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return UnreachableException(
          'Could not reach the router at $_origin. Are you on its WiFi?',
          cause: e,
        );
      default:
        return RouterException('Request failed: ${e.message}', cause: e);
    }
  }

  void dispose() => _dio.close(force: true);
}
