import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'dispatch_constants.dart';

/// Thrown for any non-2xx response from the dispatch backend, plus network
/// failures (statusCode == 0). Surfaces the user-facing message extracted
/// per the contract: `errors[0].message` first, then `message`.
class DispatchApiException implements Exception {
  DispatchApiException({
    required this.statusCode,
    required this.message,
    this.fieldErrors,
    this.rawBody,
  });

  final int statusCode;
  final String message;
  final Map<String, List<String>>? fieldErrors;
  final String? rawBody;

  /// 401 — bearer token rejected. Caller wipes auth state.
  bool get isUnauthorized => statusCode == 401;

  /// 403 with a disabled-account message. Different copy than 401.
  bool get isAccountDisabled =>
      statusCode == 403 && message.toLowerCase().contains('disabled');

  /// 409 — job already in target state, or duplicate in-flight request.
  bool get isConflict => statusCode == 409;

  /// 429 — login/activate throttle.
  bool get isThrottled => statusCode == 429;

  /// 0 — no network / DNS failure / connection refused.
  bool get isNetwork => statusCode == 0;

  @override
  String toString() => 'DispatchApiException($statusCode): $message';
}

/// Stateless HTTP client for the dispatch surface.
/// Reads the bearer token from SharedPreferences on every call so changes
/// (login, logout, 401-wipe) are picked up without instance refresh.
class DispatchApiClient {
  DispatchApiClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(DispatchConstants.prefToken);
  }

  Future<Map<String, String>> _headers({
    bool requireAuth = true,
    String? idempotencyKey,
    bool isJson = true,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (isJson) headers['Content-Type'] = 'application/json';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    if (requireAuth) {
      final token = await _readToken();
      if (token == null || token.isEmpty) {
        throw DispatchApiException(
          statusCode: 401,
          message: 'Not signed in.',
        );
      }
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> getJson(
    String url, {
    bool requireAuth = true,
  }) async {
    try {
      final res = await _http.get(
        Uri.parse(url),
        headers: await _headers(requireAuth: requireAuth),
      );
      return _parseJson(res);
    } on SocketException {
      throw DispatchApiException(
        statusCode: 0,
        message: 'No internet connection. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>> postJson(
    String url, {
    Map<String, dynamic>? body,
    bool requireAuth = true,
    String? idempotencyKey,
  }) async {
    try {
      final res = await _http.post(
        Uri.parse(url),
        headers: await _headers(
          requireAuth: requireAuth,
          idempotencyKey: idempotencyKey,
        ),
        body: jsonEncode(body ?? const <String, dynamic>{}),
      );
      return _parseJson(res);
    } on SocketException {
      throw DispatchApiException(
        statusCode: 0,
        message: 'No internet connection. Please try again.',
      );
    }
  }

  /// Multipart POST. `fields` are string form fields. `fileFields` is a list
  /// of `(fieldName, file)` pairs — same fieldName repeated for `photos[]`.
  Future<Map<String, dynamic>> postMultipart(
    String url, {
    required Map<String, String> fields,
    required List<MapEntry<String, File>> fileFields,
    String? idempotencyKey,
  }) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse(url));
      req.headers.addAll(
        await _headers(idempotencyKey: idempotencyKey, isJson: false),
      );
      req.fields.addAll(fields);
      for (final entry in fileFields) {
        req.files.add(
          await http.MultipartFile.fromPath(entry.key, entry.value.path),
        );
      }
      final streamed = await _http.send(req);
      final res = await http.Response.fromStream(streamed);
      return _parseJson(res);
    } on SocketException {
      throw DispatchApiException(
        statusCode: 0,
        message: 'No internet connection. Please try again.',
      );
    }
  }

  Map<String, dynamic> _parseJson(http.Response res) {
    final code = res.statusCode;
    Map<String, dynamic> body = const {};
    try {
      if (res.body.isNotEmpty) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      }
    } catch (_) {
      // leave body empty
    }

    if (code >= 200 && code < 300) return body;

    final message = _extractMessage(body) ?? 'Request failed ($code).';
    Map<String, List<String>>? fieldErrors;
    final errs = body['errors'];
    if (errs is Map) {
      fieldErrors = <String, List<String>>{};
      errs.forEach((k, v) {
        if (v is List) {
          fieldErrors![k.toString()] =
              v.map((e) => e.toString()).toList(growable: false);
        }
      });
    }

    throw DispatchApiException(
      statusCode: code,
      message: message,
      fieldErrors: fieldErrors,
      rawBody: res.body,
    );
  }

  String? _extractMessage(Map<String, dynamic> body) {
    final errs = body['errors'];
    if (errs is List && errs.isNotEmpty) {
      final first = errs.first;
      if (first is Map && first['message'] is String) {
        return first['message'] as String;
      }
    }
    if (body['message'] is String) return body['message'] as String;
    return null;
  }
}
