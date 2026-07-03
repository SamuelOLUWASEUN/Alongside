import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:convert/convert.dart';

/// Client-side end-to-end encryption for vault items.
///
/// The server only ever stores the JSON payload produced by [encrypt] —
/// ciphertext, iv, tag, and salt, all opaque. It never sees the passphrase
/// or the plaintext. Decryption happens entirely on-device in [decrypt].
class EncryptionService {
  // AES-256 GCM parameters
  static const int keySize = 32; // 256 bits
  static const int ivSize = 12; // 96 bits, standard for GCM
  static const int tagSize = 16; // 128 bits
  static const int saltSize = 16;
  // PBKDF2 rounds. 100,000 is a common secure default, but PointyCastle
  // running as unoptimized JS (Flutter web debug builds) can take tens of
  // seconds to minutes to churn through that on a single thread, freezing
  // the UI since Flutter web has no background isolate to offload it to.
  // 20,000 is a reasonable interactive-app compromise; for a real deployment
  // you'd want this work off the main thread (native isolate, or a Web
  // Worker on web) rather than lowering the round count further.
  static const int iterations = 20000;
  // Notes saved before this file recorded its own iteration count in the
  // payload were all encrypted with this value (the original hardcoded
  // default). Anything missing an "iterations" field is assumed to be one
  // of those.
  static const int _legacyIterations = 100000;

  /// Derive a 256-bit key from a passphrase using PBKDF2 (HMAC-SHA256).
  static Uint8List deriveKey(String passphrase, Uint8List salt, {int rounds = iterations}) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, rounds, keySize));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  static Uint8List generateSalt() => _secureRandomBytes(saltSize);
  static Uint8List generateIV() => _secureRandomBytes(ivSize);

  /// Encrypt [plaintext] with a key derived from [passphrase].
  /// Returns a JSON string: {"ciphertext","iv","tag","salt","iterations"}
  /// (all hex except "iterations"). Recording the iteration count in the
  /// payload itself means we can safely change [iterations] in the future
  /// without breaking previously-saved items.
  static String encrypt(String plaintext, String passphrase) {
    final salt = generateSalt();
    final iv = generateIV();
    final key = deriveKey(passphrase, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), tagSize * 8, iv, Uint8List(0)));

    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = cipher.process(plainBytes);

    final payload = {
      'ciphertext': hex.encode(encrypted.sublist(0, encrypted.length - tagSize)),
      'iv': hex.encode(iv),
      'tag': hex.encode(encrypted.sublist(encrypted.length - tagSize)),
      'salt': hex.encode(salt),
      'iterations': iterations,
    };
    return jsonEncode(payload);
  }

  /// Decrypt a JSON payload (produced by [encrypt]) back to plaintext.
  /// Throws if the passphrase is wrong or the payload is malformed/tampered
  /// (GCM's auth tag check will fail).
  static String decrypt(String encryptedPayload, String passphrase) {
    final payload = jsonDecode(encryptedPayload) as Map<String, dynamic>;
    final ciphertext = hex.decode(payload['ciphertext'] as String);
    final iv = hex.decode(payload['iv'] as String);
    final tag = hex.decode(payload['tag'] as String);
    final salt = hex.decode(payload['salt'] as String);
    final rounds = payload['iterations'] as int? ?? _legacyIterations;

    final key = deriveKey(passphrase, Uint8List.fromList(salt), rounds: rounds);

    final combined = Uint8List(ciphertext.length + tag.length)
      ..setAll(0, ciphertext)
      ..setAll(ciphertext.length, tag);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), tagSize * 8, Uint8List.fromList(iv), Uint8List(0)));

    final decrypted = cipher.process(combined);
    return utf8.decode(decrypted);
  }

  /// Cryptographically secure random bytes, seeded from the platform CSPRNG
  /// (dart:math's Random.secure(), backed by /dev/urandom or the OS
  /// equivalent) rather than anything time-based or otherwise predictable.
  static Uint8List _secureRandomBytes(int length) {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seed = Uint8List(32);
    for (int i = 0; i < seed.length; i++) {
      seed[i] = seedSource.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seed));
    return secureRandom.nextBytes(length);
  }
}
