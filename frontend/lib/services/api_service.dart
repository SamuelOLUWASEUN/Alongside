import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  // Set to localhost since we're running as Windows/Chrome desktop, not an
  // Android emulator (10.0.2.2 is Android-emulator-only).
  static const baseUrl = 'http://localhost:8080/api';
  static const _storage = FlutterSecureStorage();

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

  static Future<dynamic> post(String path, Map<String, dynamic> body, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.post(uri, headers: await _headers(auth: auth), body: jsonEncode(body));
    if (response.statusCode == 200 || response.statusCode == 201) {
      return _decodeOrNull(response.body);
    } else {
      throw Exception('Request failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<dynamic> get(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.get(uri, headers: await _headers(auth: auth));
    if (response.statusCode == 200) {
      return _decodeOrNull(response.body);
    } else {
      throw Exception('Request failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<void> delete(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.delete(uri, headers: await _headers(auth: auth));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Request failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<String?> getToken() => _storage.read(key: 'access_token');

  // The active chat conversation ID, persisted so refreshing the page (or
  // relaunching the app) continues the same thread instead of always
  // starting fresh. Cleared explicitly when the user starts a new chat.
  static Future<String?> getConversationId() => _storage.read(key: 'conversation_id');
  static Future<void> setConversationId(String id) => _storage.write(key: 'conversation_id', value: id);
  static Future<void> clearConversationId() => _storage.delete(key: 'conversation_id');
}

