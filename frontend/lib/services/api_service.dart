import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';

class ApiService {
  // Set via --dart-define at build time (see config.dart) - defaults to
  // localhost for local dev, points at the real backend in production
  // builds without needing any code changes.
  static String get baseUrl => AppConfig.apiBaseUrl;
  static const _storage = FlutterSecureStorage();

  /// Set by AuthService at startup so ApiService can trigger a full sign-out
  /// when token refresh definitively fails (e.g. the refresh token itself
  /// has also expired) - avoids a circular import between the two services.
  static void Function()? onAuthExpired;

  static bool _refreshing = false;

  // Access tokens expire after 15 minutes by design. Rather than every
  // screen needing to know about that and handle a 401 itself, every
  // request here transparently tries one silent refresh-and-retry first -
  // the rest of the app just sees a normal successful response (or a
  // genuine failure if the refresh token has also expired).
  static Future<bool> _tryRefresh() async {
    if (_refreshing) {
      // A refresh triggered by a concurrent request is already in flight -
      // wait for it rather than firing a redundant second refresh call.
      while (_refreshing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return await _storage.read(key: 'access_token') != null;
    }
    _refreshing = true;
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      await _storage.write(key: 'access_token', value: data['access_token']);
      await _storage.write(key: 'refresh_token', value: data['refresh_token']);
      return true;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  static Future<http.Response> _sendWithRefresh(
      Future<http.Response> Function() send) async {
    var response = await send();
    if (response.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        response = await send();
      } else {
        onAuthExpired?.call();
      }
    }
    return response;
  }

  static Future<Map<String, String>> _headers({bool auth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await _storage.read(key: 'access_token');
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Some backend endpoints (e.g. mood/log) return a 200/201 with an empty
  // body rather than a JSON object. jsonDecode('') throws a FormatException,
  // so we only attempt to parse when there's actually a body to parse.
  static dynamic _decodeOrNull(String body) {
    if (body.isEmpty) return null;
    return jsonDecode(body);
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _sendWithRefresh(
      () async => http.post(uri,
          headers: await _headers(auth: auth), body: jsonEncode(body)),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return _decodeOrNull(response.body);
    } else {
      throw Exception(
          'Request failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<dynamic> get(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _sendWithRefresh(
      () async => http.get(uri, headers: await _headers(auth: auth)),
    );
    if (response.statusCode == 200) {
      return _decodeOrNull(response.body);
    } else {
      throw Exception(
          'Request failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<void> delete(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _sendWithRefresh(
      () async => http.delete(uri, headers: await _headers(auth: auth)),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Request failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<String?> getToken() => _storage.read(key: 'access_token');

  // The active chat conversation ID, persisted so refreshing the page (or
  // relaunching the app) continues the same thread instead of always
  // starting fresh. Cleared explicitly when the user starts a new chat.
  static Future<String?> getConversationId() =>
      _storage.read(key: 'conversation_id');
  static Future<void> setConversationId(String id) =>
      _storage.write(key: 'conversation_id', value: id);
  static Future<void> clearConversationId() =>
      _storage.delete(key: 'conversation_id');
}
