import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';
import '../models/vault_registry.dart';
import 'crypto_service.dart';

class ConfigService {
  static const String _primaryConfigFileName = 'state.dat';
  static const String _legacyConfigFileName = 'config.json';
  static const String _stateKeySeed = 'vault_os_local_state_v1';
  static const String _internalVendorDirectory = 'VTSys';
  static const String _internalStateDirectory = 'runtime_cache';

  ConfigService() : _cryptoService = CryptoService();

  final CryptoService _cryptoService;

  Future<Directory> _configDirectory() async {
    final appDir = await _primaryConfigDirectory();
    await appDir.create(recursive: true);
    return appDir;
  }

  Future<Directory> _primaryConfigDirectory() async {
    if (Platform.isWindows) {
      final localAppData =
          Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return Directory(
          path.join(
            localAppData,
            _internalVendorDirectory,
            _internalStateDirectory,
          ),
        );
      }
    }

    final directory = await getApplicationSupportDirectory();
    return Directory(
      path.join(directory.path, _internalVendorDirectory, _internalStateDirectory),
    );
  }

  Future<List<Directory>> _legacyConfigDirectories() async {
    final directories = <Directory>[];

    if (Platform.isWindows) {
      final localAppData =
          Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        directories.add(
          Directory(path.join(localAppData, 'com.example', 'vault_os', 'VaultOS')),
        );
        directories.add(
          Directory(path.join(localAppData, 'vault_os', 'VaultOS')),
        );
      }
    }

    final supportDirectory = await getApplicationSupportDirectory();
    directories.add(Directory(path.join(supportDirectory.path, 'VaultOS')));

    return directories;
  }

  Future<File> _configFile() async {
    final directory = await _configDirectory();
    return File(path.join(directory.path, _primaryConfigFileName));
  }

  Future<File> _legacyConfigFile() async {
    final directory = await _configDirectory();
    return File(path.join(directory.path, _legacyConfigFileName));
  }

  Future<VaultRegistry> loadRegistry() async {
    final file = await _configFile();
    File sourceFile;
    if (await file.exists()) {
      sourceFile = file;
    } else {
      sourceFile = await _findExistingLegacyConfigFile() ?? await _legacyConfigFile();
    }
    if (!await sourceFile.exists()) {
      return const VaultRegistry(vaults: <AppConfig>[]);
    }

    if (sourceFile.path.endsWith(_primaryConfigFileName)) {
      final sealed = await sourceFile.readAsBytes();
      if (sealed.isEmpty) {
        return const VaultRegistry(vaults: <AppConfig>[]);
      }
      final source = await _decryptState(sealed);
      return _decodeRegistrySource(source);
    }

    final source = await sourceFile.readAsString();
    if (source.trim().isEmpty) {
      return const VaultRegistry(vaults: <AppConfig>[]);
    }

    return _decodeRegistrySource(source);
  }

  VaultRegistry _decodeRegistrySource(String source) {
    try {
      return VaultRegistry.decode(source);
    } catch (_) {
      final legacy = AppConfig.decode(source);
      return VaultRegistry(vaults: <AppConfig>[legacy]);
    }
  }

  Future<void> saveRegistry(VaultRegistry registry) async {
    final file = await _configFile();
    final sealed = await _encryptState(registry.encode());
    await file.writeAsBytes(sealed, flush: true);
    await _cleanupLegacyConfigFiles();
  }

  Future<File?> _findExistingLegacyConfigFile() async {
    for (final directory in await _legacyConfigDirectories()) {
      final primary = File(path.join(directory.path, _primaryConfigFileName));
      if (await primary.exists()) {
        return primary;
      }
      final legacy = File(path.join(directory.path, _legacyConfigFileName));
      if (await legacy.exists()) {
        return legacy;
      }
    }
    return null;
  }

  Future<void> _cleanupLegacyConfigFiles() async {
    final seen = <String>{};
    final currentDirectory = await _configDirectory();
    seen.add(path.normalize(currentDirectory.path).toLowerCase());

    for (final directory in await _legacyConfigDirectories()) {
      final normalized = path.normalize(directory.path).toLowerCase();
      if (!seen.add(normalized)) {
        continue;
      }

      final primary = File(path.join(directory.path, _primaryConfigFileName));
      if (await primary.exists()) {
        await primary.delete();
      }

      final legacy = File(path.join(directory.path, _legacyConfigFileName));
      if (await legacy.exists()) {
        await legacy.delete();
      }

      if (await directory.exists()) {
        final remaining = await directory.list().isEmpty;
        if (remaining) {
          await directory.delete();
        }
      }
    }
  }

  Future<void> clearConfig() async {
    final file = await _configFile();
    if (await file.exists()) {
      await file.delete();
    }
    await _cleanupLegacyConfigFiles();
  }

  Future<List<int>> _encryptState(String source) {
    return _cryptoService.encryptBytes(
      clearBytes: utf8.encode(source),
      keyBytes: _stateKeyBytes(),
    );
  }

  Future<String> _decryptState(List<int> sealed) async {
    final clear = await _cryptoService.decryptBytes(
      sealedBytes: sealed,
      keyBytes: _stateKeyBytes(),
    );
    return utf8.decode(clear);
  }

  List<int> _stateKeyBytes() {
    final seed = utf8.encode(_stateKeySeed);
    if (seed.length >= _cryptoService.keyLength) {
      return seed.sublist(0, _cryptoService.keyLength);
    }
    return <int>[
      ...seed,
      ...List<int>.filled(_cryptoService.keyLength - seed.length, 0),
    ];
  }
}
