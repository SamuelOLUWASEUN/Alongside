import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

class AuthService with ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  String? _accessToken;
  String? _email;
  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;
  String? get email => _email;

  Future<void> register(String email, String password) async {
    await ApiService.post('/auth/register', {'email': email, 'password': password}, auth: false);
  }

  Future<void> login(String email, String password) async {
    final data = await ApiService.post('/auth/login', {'email': email, 'password': password}, auth: false);
    _accessToken = data['access_token'];
    await _storage.write(key: 'access_token', value: _accessToken);
    await _storage.write(key: 'refresh_token', value: data['refresh_token']);
    await _storage.write(key: 'email', value: email);
    _email = email;
    _isLoggedIn = true;
    notifyListeners();
  }

  Future<void> tryAutoLogin() async {
    _accessToken = await _storage.read(key: 'access_token');
    if (_accessToken != null) {
      _email = await _storage.read(key: 'email');
      _isLoggedIn = true;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    _accessToken = null;
    _email = null;
    _isLoggedIn = false;
    notifyListeners();
  }
}
