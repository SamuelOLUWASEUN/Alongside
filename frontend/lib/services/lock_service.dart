import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// App-lock: a PIN that works identically everywhere (including web),
/// with real device biometrics (Face ID / fingerprint) automatically
/// offered as a faster alternative wherever the platform actually
/// supports it. local_auth simply has no implementation on web, so
/// [canUseBiometrics] safely returns false there rather than the lock
/// ever depending on it - the PIN is always the reliable fallback.
class LockService {
  static const _storage = FlutterSecureStorage();
  static final _bioAuth = LocalAuthentication();

  static Future<bool> isEnabled() async {
    final hash = await _storage.read(key: 'lock_pin_hash');
    return hash != null;
  }

  static String _hash(String pin) =>
      sha256.convert(utf8.encode(pin)).toString();

  static Future<void> setPin(String pin) async {
    await _storage.write(key: 'lock_pin_hash', value: _hash(pin));
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: 'lock_pin_hash');
    if (stored == null) return false;
    return stored == _hash(pin);
  }

  static Future<void> disable() async {
    await _storage.delete(key: 'lock_pin_hash');
  }

  /// True only where local_auth has a working platform implementation
  /// with biometrics actually enrolled right now - false on web, and
  /// false on native devices with no Face ID/fingerprint set up.
  static Future<bool> canUseBiometrics() async {
    if (kIsWeb) return false;
    try {
      final supported = await _bioAuth.isDeviceSupported();
      final canCheck = await _bioAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateWithBiometrics() async {
    try {
      return await _bioAuth.authenticate(
        localizedReason: 'Unlock Alongside',
        options:
            const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
