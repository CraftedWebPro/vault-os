import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  static const int _keyLength = 32;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  final AesGcm _aesGcm = AesGcm.with256bits();
  final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );

  List<int> randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  Future<List<int>> deriveUserKey({
    required String passphrase,
    required List<int> salt,
  }) async {
    final derived = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    return derived.extractBytes();
  }

  List<int> xor(List<int> left, List<int> right) {
    if (left.length != right.length) {
      throw ArgumentError('XOR inputs must be the same length.');
    }

    return List<int>.generate(
      left.length,
      (index) => left[index] ^ right[index],
      growable: false,
    );
  }

  Future<List<int>> encryptBytes({
    required List<int> clearBytes,
    required List<int> keyBytes,
  }) async {
    debugPrint('crypto.encryptBytes:start clear=${clearBytes.length}');
    final nonce = randomBytes(_nonceLength);
    final secretBox = await _aesGcm.encrypt(
      clearBytes,
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
    );
    debugPrint('crypto.encryptBytes:done cipher=${secretBox.cipherText.length}');
    return <int>[
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ];
  }

  Future<List<int>> decryptBytes({
    required List<int> sealedBytes,
    required List<int> keyBytes,
  }) async {
    if (sealedBytes.length < _nonceLength + _macLength) {
      throw StateError('Encrypted payload is incomplete.');
    }

    final nonce = sealedBytes.sublist(0, _nonceLength);
    final mac = Mac(sealedBytes.sublist(_nonceLength, _nonceLength + _macLength));
    final cipherText = sealedBytes.sublist(_nonceLength + _macLength);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    return _aesGcm.decrypt(secretBox, secretKey: SecretKey(keyBytes));
  }

  int get keyLength => _keyLength;
}
