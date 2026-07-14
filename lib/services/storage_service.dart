import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../models/app_config.dart';
import '../models/preview_payload.dart';
import '../models/vault_entry.dart';
import '../models/vault_manifest.dart';
import 'crypto_service.dart';
import 'windows_visibility_service.dart';

class StorageService {
  static const String warningFileName = 'system_notice.txt';
  static const String indexFileName = 'index.dat';
  static const String legacyManifestFileName = 'vault_manifest.json';
  static const String profileFileName = 'profile.dat';
  static const String legacyProfileFileName = 'bio_profile.json';

  StorageService({
    required CryptoService cryptoService,
    required WindowsVisibilityService windowsVisibilityService,
  }) : _cryptoService = cryptoService,
       _windowsVisibilityService = windowsVisibilityService;

  final CryptoService _cryptoService;
  final WindowsVisibilityService _windowsVisibilityService;

  String workspaceDirectoryPath(String vaultDirectory) {
    final vaultFolderName = path.basename(vaultDirectory);
    return path.join(
      path.dirname(vaultDirectory),
      '${vaultFolderName}_unlocked',
    );
  }

  String manifestFilePath(String vaultDirectory) {
    return path.join(vaultDirectory, indexFileName);
  }

  String legacyManifestFilePath(String vaultDirectory) {
    return path.join(vaultDirectory, legacyManifestFileName);
  }

  String profileFilePath(String vaultDirectory) {
    return path.join(vaultDirectory, profileFileName);
  }

  String legacyProfileFilePath(String vaultDirectory) {
    return path.join(vaultDirectory, legacyProfileFileName);
  }

  String warningFilePath(String vaultDirectory) {
    return path.join(vaultDirectory, warningFileName);
  }

  Future<bool> workspaceExists(String vaultDirectory) async {
    return Directory(workspaceDirectoryPath(vaultDirectory)).exists();
  }

  Future<void> deleteVaultDirectory(String vaultDirectoryPath) async {
    final vaultDirectory = Directory(vaultDirectoryPath);
    if (await vaultDirectory.exists()) {
      await _windowsVisibilityService.unhide(vaultDirectory.absolute.path);
      await vaultDirectory.delete(recursive: true);
    }

    final workspaceDirectory = Directory(
      workspaceDirectoryPath(vaultDirectory.absolute.path),
    );
    if (await workspaceDirectory.exists()) {
      await workspaceDirectory.delete(recursive: true);
    }
  }

  Future<String> prepareVaultDirectory(String parentDirectory) async {
    final parent = Directory(parentDirectory);
    await parent.create(recursive: true);

    while (true) {
      final folderToken = sha256
          .convert(
            utf8.encode(
              '${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch}-${parentDirectory.length}',
            ),
          )
          .toString()
          .substring(0, 12);
      final vaultDirectory = Directory(
        path.join(parent.path, '.vx_$folderToken'),
      );
      if (await vaultDirectory.exists()) {
        continue;
      }

      await vaultDirectory.create(recursive: true);
      await File(
        warningFilePath(vaultDirectory.path),
      ).writeAsString(_warningFileContents, flush: true);
      await _windowsVisibilityService.hide(vaultDirectory.path);
      return vaultDirectory.path;
    }
  }

  Future<void> initializeMetadata({
    required AppConfig config,
    required List<int> vaultKey,
  }) async {
    await _writeMetadata(
      config: config,
      vaultKey: vaultKey,
      entries: const <VaultEntry>[],
    );
  }

  Future<List<VaultEntry>> reencryptVault({
    required AppConfig config,
    required List<int> oldVaultKey,
    required List<int> newVaultKey,
  }) async {
    final entries = await loadEntries(config: config, vaultKey: oldVaultKey);
    final storedNames = entries.map((entry) => entry.storedName).toSet();

    for (final storedName in storedNames) {
      final blob = File(path.join(config.vaultDirectory, storedName));
      if (!await blob.exists()) {
        continue;
      }

      final sealed = await blob.readAsBytes();
      final clearBytes = await _cryptoService.decryptBytes(
        sealedBytes: sealed,
        keyBytes: oldVaultKey,
      );
      final resealed = await _cryptoService.encryptBytes(
        clearBytes: clearBytes,
        keyBytes: newVaultKey,
      );
      await blob.writeAsBytes(resealed, flush: true);
    }

    await _writeMetadata(
      config: config,
      vaultKey: newVaultKey,
      entries: entries,
    );

    return entries;
  }

  Future<List<VaultEntry>> loadEntries({
    required AppConfig config,
    required List<int> vaultKey,
  }) async {
    final file = File(config.metadataFilePath);
    if (!await file.exists()) {
      return const <VaultEntry>[];
    }

    final sealed = await file.readAsBytes();
    final clearBytes = await _cryptoService.decryptBytes(
      sealedBytes: sealed,
      keyBytes: vaultKey,
    );
    final source = utf8.decode(clearBytes);
    return VaultEntry.decodeList(source);
  }

  Future<List<VaultEntry>> unlockWorkspace({
    required AppConfig config,
    required List<int> vaultKey,
  }) async {
    final workspaceDirectory = workspaceDirectoryPath(config.vaultDirectory);
    final workspace = Directory(workspaceDirectory);
    if (await workspace.exists()) {
      final existing = await loadWorkspaceEntries(workspaceDirectory);
      if (existing.isNotEmpty) {
        return existing;
      }
      await workspace.delete(recursive: true);
    }

    await workspace.create(recursive: true);
    final encryptedEntries = await loadEntries(
      config: config,
      vaultKey: vaultKey,
    );

    for (final entry in encryptedEntries) {
      final blob = File(path.join(config.vaultDirectory, entry.storedName));
      if (!await blob.exists()) {
        continue;
      }

      final sealed = await blob.readAsBytes();
      final clearBytes = await _cryptoService.decryptBytes(
        sealedBytes: sealed,
        keyBytes: vaultKey,
      );
      final targetPath = path.join(workspaceDirectory, entry.relativePath);
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(clearBytes, flush: true);
    }

    return loadWorkspaceEntries(workspaceDirectory);
  }

  Future<List<VaultEntry>> loadWorkspaceEntries(
    String workspaceDirectory,
  ) async {
    final workspace = Directory(workspaceDirectory);
    if (!await workspace.exists()) {
      return const <VaultEntry>[];
    }

    final entities = await workspace
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    entities.sort((left, right) => left.path.compareTo(right.path));

    return Future.wait(
      entities.map((file) async {
        final stat = await file.stat();
        final relative = path.relative(file.path, from: workspaceDirectory);
        return VaultEntry(
          id: relative,
          displayName: path.basename(file.path),
          relativePath: relative,
          storedName: relative,
          originalSize: stat.size,
          createdAtIso: stat.modified.toIso8601String(),
        );
      }),
    );
  }

  Future<void> moveSourceIntoWorkspace({
    required String workspaceDirectory,
    required Iterable<String> sourcePaths,
  }) async {
    final workspace = Directory(workspaceDirectory);
    await workspace.create(recursive: true);

    for (final sourcePath in sourcePaths) {
      final file = File(sourcePath);
      if (await file.exists()) {
        await _moveFileToWorkspace(
          file: file,
          workspaceDirectory: workspaceDirectory,
        );
        continue;
      }

      final directory = Directory(sourcePath);
      if (await directory.exists()) {
        await _moveDirectoryToWorkspace(
          directory: directory,
          workspaceDirectory: workspaceDirectory,
        );
      }
    }
  }

  Future<List<VaultEntry>> syncWorkspaceToVault({
    required AppConfig config,
    required List<int> vaultKey,
  }) async {
    final workspaceDirectory = workspaceDirectoryPath(config.vaultDirectory);
    final workspaceEntries = await loadWorkspaceEntries(workspaceDirectory);
    final vaultDirectory = Directory(config.vaultDirectory);
    final keepNames = <String>{
      path.basename(config.metadataFilePath),
      path.basename(config.biometricProfilePath),
      path.basename(manifestFilePath(config.vaultDirectory)),
      warningFileName,
      '${path.basename(config.metadataFilePath)}.next',
    };

    await for (final entity in vaultDirectory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = path.basename(entity.path);
      if (keepNames.contains(name)) {
        continue;
      }
      await entity.delete();
    }

    final entries = <VaultEntry>[];
    final writtenBlobs = <String>{};

    for (final workspaceEntry in workspaceEntries) {
      final clearBytes = await File(
        path.join(workspaceDirectory, workspaceEntry.relativePath),
      ).readAsBytes();
      final storedName = sha256.convert(clearBytes).toString();
      if (!writtenBlobs.contains(storedName)) {
        final sealedBytes = await _cryptoService.encryptBytes(
          clearBytes: clearBytes,
          keyBytes: vaultKey,
        );
        await File(
          path.join(config.vaultDirectory, storedName),
        ).writeAsBytes(sealedBytes, flush: true);
        writtenBlobs.add(storedName);
      }

      entries.add(
        VaultEntry(
          id: '${DateTime.now().microsecondsSinceEpoch}-$storedName-${workspaceEntry.relativePath}',
          displayName: workspaceEntry.displayName,
          relativePath: workspaceEntry.relativePath,
          storedName: storedName,
          originalSize: workspaceEntry.originalSize,
          createdAtIso: workspaceEntry.createdAtIso,
        ),
      );
    }

    await _writeMetadata(config: config, vaultKey: vaultKey, entries: entries);

    await clearWorkspace(workspaceDirectory);
    return entries;
  }

  Future<void> clearWorkspace(String workspaceDirectory) async {
    final directory = Directory(workspaceDirectory);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> writeVaultManifest({
    required AppConfig config,
    required VaultManifest manifest,
  }) async {
    final file = File(manifestFilePath(config.vaultDirectory));
    final legacyFile = File(legacyManifestFilePath(config.vaultDirectory));
    final tempFile = File('${file.path}.next');
    if (await file.exists()) {
      await _windowsVisibilityService.unhide(file.path);
    }
    await tempFile.writeAsString(manifest.encode(), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
    if (await legacyFile.exists()) {
      await _windowsVisibilityService.unhide(legacyFile.path);
      await legacyFile.delete();
    }
    await _windowsVisibilityService.hide(file.path);
  }

  Future<VaultManifest?> tryReadVaultManifest(String vaultDirectory) async {
    final file = File(manifestFilePath(vaultDirectory));
    if (await file.exists()) {
      return VaultManifest.decode(await file.readAsString());
    }
    final legacyFile = File(legacyManifestFilePath(vaultDirectory));
    if (await legacyFile.exists()) {
      return VaultManifest.decode(await legacyFile.readAsString());
    }
    return null;
  }

  Future<void> writeEncryptedProfile({
    required String targetPath,
    required Map<String, dynamic> profile,
    required List<int> profileKey,
  }) async {
    final sealed = await _cryptoService.encryptBytes(
      clearBytes: utf8.encode(jsonEncode(profile)),
      keyBytes: profileKey,
    );
    final file = File(targetPath);
    final tempFile = File('$targetPath.next');
    if (await file.exists()) {
      await _windowsVisibilityService.unhide(file.path);
    }
    await tempFile.writeAsBytes(sealed, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
    await _windowsVisibilityService.hide(file.path);

    final legacyFile = File(legacyProfileFilePath(path.dirname(targetPath)));
    if (path.normalize(legacyFile.path) != path.normalize(file.path) &&
        await legacyFile.exists()) {
      await _windowsVisibilityService.unhide(legacyFile.path);
      await legacyFile.delete();
    }
  }

  Future<Map<String, dynamic>> readProfile({
    required String profilePath,
    required List<int> profileKey,
  }) async {
    final file = File(profilePath);
    if (!await file.exists()) {
      throw StateError('Biometric profile is missing.');
    }

    if (path.extension(profilePath).toLowerCase() == '.json') {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }

    final sealed = await file.readAsBytes();
    final clear = await _cryptoService.decryptBytes(
      sealedBytes: sealed,
      keyBytes: profileKey,
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  Future<String> materializeProfileForPython({
    required String profilePath,
    required List<int> profileKey,
  }) async {
    final profile = await readProfile(
      profilePath: profilePath,
      profileKey: profileKey,
    );
    final tempPath = '$profilePath.runtime.json';
    await File(tempPath).writeAsString(jsonEncode(profile), flush: true);
    return tempPath;
  }

  Future<void> deleteMaterializedProfile(String tempPath) async {
    final file = File(tempPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<AppConfig> externalConfigFromLocation(String location) async {
    final resolvedVaultDirectory = await resolveVaultDirectory(location);
    final manifest = await tryReadVaultManifest(resolvedVaultDirectory);
    if (manifest == null) {
      throw StateError(
        'That vault was created before portable manifests were added. It cannot be reopened from location alone yet.',
      );
    }
    return externalConfigFromVaultDirectory(
      vaultDirectory: resolvedVaultDirectory,
      manifest: manifest,
    );
  }

  AppConfig externalConfigFromVaultDirectory({
    required String vaultDirectory,
    required VaultManifest manifest,
  }) {
    return AppConfig(
      id: manifest.vaultId ?? vaultDirectory,
      vaultName: manifest.vaultName,
      vaultDirectory: vaultDirectory,
      metadataFilePath: path.join(vaultDirectory, 'registry.bin'),
      biometricProfilePath: File(profileFilePath(vaultDirectory)).existsSync()
          ? profileFilePath(vaultDirectory)
          : legacyProfileFilePath(vaultDirectory),
      saltBase64: manifest.saltBase64,
      gestureLabel: manifest.gestureLabel,
      createdAtIso: manifest.createdAtIso,
      wallpaperAsset: manifest.wallpaperAsset,
    );
  }

  Future<List<AppConfig>> discoverVaults(String location) async {
    final normalizedLocation = path.normalize(location);
    final discovered = <AppConfig>[];
    final seenVaultDirectories = <String>{};

    Future<void> addIfManifestExists(String vaultDirectory) async {
      final manifest = await tryReadVaultManifest(vaultDirectory);
      if (manifest == null) {
        return;
      }
      final normalizedVaultDirectory = path.normalize(vaultDirectory);
      if (!seenVaultDirectories.add(normalizedVaultDirectory)) {
        return;
      }
      discovered.add(
        externalConfigFromVaultDirectory(
          vaultDirectory: vaultDirectory,
          manifest: manifest,
        ),
      );
    }

    await addIfManifestExists(normalizedLocation);
    await addIfManifestExists(path.join(normalizedLocation, '.vaultos'));

    final locationDirectory = Directory(normalizedLocation);
    if (await locationDirectory.exists()) {
      await for (final entity in locationDirectory.list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        await addIfManifestExists(entity.path);
      }
    }

    return discovered;
  }

  Future<String> resolveVaultDirectory(String location) async {
    final normalizedLocation = path.normalize(location);
    final exactDirectory = Directory(normalizedLocation);
    if (await exactDirectory.exists()) {
      final exactManifest = File(manifestFilePath(exactDirectory.path));
      final legacyExactManifest = File(
        legacyManifestFilePath(exactDirectory.path),
      );
      if (await exactManifest.exists() || await legacyExactManifest.exists()) {
        return exactDirectory.path;
      }
    }

    final legacyVaultDirectory = path.join(normalizedLocation, '.vaultos');
    if (await File(manifestFilePath(legacyVaultDirectory)).exists() ||
        await File(legacyManifestFilePath(legacyVaultDirectory)).exists()) {
      return legacyVaultDirectory;
    }

    final candidates = (await discoverVaults(
      normalizedLocation,
    )).map((config) => config.vaultDirectory).toList(growable: false);

    if (candidates.isEmpty) {
      throw StateError('No vault was found in that location.');
    }

    if (candidates.length > 1) {
      throw StateError(
        'Multiple vaults were found in that location. Please choose the exact vault folder.',
      );
    }

    return candidates.single;
  }

  Future<void> moveWorkspaceContents({
    required String sourceWorkspaceDirectory,
    required String targetWorkspaceDirectory,
  }) async {
    final source = Directory(sourceWorkspaceDirectory);
    if (!await source.exists()) {
      return;
    }

    final entities = await source.list(followLinks: false).toList();
    await moveSourceIntoWorkspace(
      workspaceDirectory: targetWorkspaceDirectory,
      sourcePaths: entities.map((entity) => entity.path),
    );
  }

  Future<void> deleteWorkspaceEntry({
    required String workspaceDirectory,
    required VaultEntry entry,
  }) async {
    final file = File(path.join(workspaceDirectory, entry.relativePath));
    if (await file.exists()) {
      await file.delete();
    }

    await _deleteEmptyAncestors(
      Directory(path.dirname(file.path)),
      stopAt: Directory(workspaceDirectory).absolute.path,
    );
  }

  Future<PreviewPayload> readWorkspacePreview({
    required String workspaceDirectory,
    required VaultEntry entry,
  }) async {
    final clearBytes = await File(
      path.join(workspaceDirectory, entry.relativePath),
    ).readAsBytes();
    final extension = path.extension(entry.displayName).toLowerCase();

    if (_imageExtensions.contains(extension)) {
      return PreviewPayload(
        name: entry.relativePath,
        bytes: clearBytes,
        kind: PreviewKind.image,
      );
    }

    if (_textExtensions.contains(extension)) {
      return PreviewPayload(
        name: entry.relativePath,
        bytes: clearBytes,
        kind: PreviewKind.text,
        text: utf8.decode(clearBytes, allowMalformed: true),
      );
    }

    return PreviewPayload(
      name: entry.relativePath,
      bytes: clearBytes,
      kind: PreviewKind.binary,
    );
  }

  Future<void> _moveFileToWorkspace({
    required File file,
    required String workspaceDirectory,
  }) async {
    final targetFile = await _uniqueTargetFile(
      workspaceDirectory: workspaceDirectory,
      relativePath: path.basename(file.path),
    );
    try {
      await file.rename(targetFile.path);
    } on FileSystemException {
      await targetFile.writeAsBytes(await file.readAsBytes(), flush: true);
      await file.delete();
    }
  }

  Future<void> _moveDirectoryToWorkspace({
    required Directory directory,
    required String workspaceDirectory,
  }) async {
    final targetDirectory = await _uniqueTargetDirectory(
      workspaceDirectory: workspaceDirectory,
      relativePath: path.basename(directory.path),
    );
    await targetDirectory.create(recursive: true);

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final relative = path.relative(entity.path, from: directory.path);
      final targetFile = File(path.join(targetDirectory.path, relative));
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(await entity.readAsBytes(), flush: true);
    }

    await directory.delete(recursive: true);
  }

  Future<File> _uniqueTargetFile({
    required String workspaceDirectory,
    required String relativePath,
  }) async {
    final originalExtension = path.extension(relativePath);
    final baseName = path.basenameWithoutExtension(relativePath);
    final parentRelative = path.dirname(relativePath) == '.'
        ? ''
        : path.dirname(relativePath);
    var candidate = relativePath;
    var index = 2;

    while (await File(path.join(workspaceDirectory, candidate)).exists()) {
      final renamed = '$baseName ($index)$originalExtension';
      candidate = parentRelative.isEmpty
          ? renamed
          : path.join(parentRelative, renamed);
      index++;
    }

    final file = File(path.join(workspaceDirectory, candidate));
    await file.parent.create(recursive: true);
    return file;
  }

  Future<Directory> _uniqueTargetDirectory({
    required String workspaceDirectory,
    required String relativePath,
  }) async {
    final parentRelative = path.dirname(relativePath) == '.'
        ? ''
        : path.dirname(relativePath);
    final baseName = path.basename(relativePath);
    var candidate = relativePath;
    var index = 2;

    while (await Directory(path.join(workspaceDirectory, candidate)).exists()) {
      final renamed = '$baseName ($index)';
      candidate = parentRelative.isEmpty
          ? renamed
          : path.join(parentRelative, renamed);
      index++;
    }

    return Directory(path.join(workspaceDirectory, candidate));
  }

  Future<void> _deleteEmptyAncestors(
    Directory directory, {
    required String stopAt,
  }) async {
    var current = directory;
    while (true) {
      final normalized = current.absolute.path;
      if (normalized == stopAt) {
        return;
      }
      if (!await current.exists()) {
        current = current.parent;
        continue;
      }
      if (await current.list(followLinks: false).isEmpty) {
        await current.delete();
        current = current.parent;
        continue;
      }
      return;
    }
  }

  Future<void> _writeMetadata({
    required AppConfig config,
    required List<int> vaultKey,
    required List<VaultEntry> entries,
  }) async {
    debugPrint('storage.writeMetadata:start entries=${entries.length}');
    final source = VaultEntry.encodeList(entries);
    debugPrint('storage.writeMetadata:encoded chars=${source.length}');
    final sealed = await _cryptoService.encryptBytes(
      clearBytes: utf8.encode(source),
      keyBytes: vaultKey,
    );
    debugPrint('storage.writeMetadata:encrypted bytes=${sealed.length}');
    final file = File(config.metadataFilePath);
    final tempFile = File('${config.metadataFilePath}.next');
    await tempFile.writeAsBytes(sealed, flush: true);
    debugPrint('storage.writeMetadata:wrote temp=${tempFile.path}');
    if (await file.exists()) {
      await file.delete();
      debugPrint('storage.writeMetadata:deleted old=${file.path}');
    }
    await tempFile.rename(file.path);
    debugPrint('storage.writeMetadata:renamed temp to final=${file.path}');
    debugPrint('storage.writeMetadata:done path=${file.path}');
  }

  static const Set<String> _imageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.bmp',
    '.gif',
    '.webp',
  };

  static const Set<String> _textExtensions = <String>{
    '.txt',
    '.md',
    '.json',
    '.yaml',
    '.yml',
    '.log',
    '.csv',
  };

  static const String _warningFileContents =
      'System Notice\n'
      '\n'
      'This directory contains application-managed files.\n'
      '\n'
      'To avoid sync issues or unexpected behavior, do not rename, move,\n'
      'edit, or delete items in this location manually.\n'
      '\n'
      'If changes are needed, use the associated application workflow.\n';
}
