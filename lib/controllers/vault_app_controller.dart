import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';
import '../models/preview_payload.dart';
import '../models/vault_entry.dart';
import '../models/vault_manifest.dart';
import '../models/vault_registry.dart';
import '../models/wallpaper_option.dart';
import '../services/config_service.dart';
import '../services/crypto_service.dart';
import '../services/python_biometric_service.dart';
import '../services/storage_service.dart';
import '../services/wallpaper_service.dart';
import '../services/windows_visibility_service.dart';

class VaultAppController extends ChangeNotifier {
  static const String defaultWallpaperAsset = 'assets/themes/zenetsu.webp';

  VaultAppController()
    : _cryptoService = CryptoService(),
      _configService = ConfigService(),
      _pythonBiometricService = PythonBiometricService(),
      _wallpaperService = WallpaperService(),
      _storageService = StorageService(
        cryptoService: CryptoService(),
        windowsVisibilityService: WindowsVisibilityService(),
      );

  final CryptoService _cryptoService;
  final ConfigService _configService;
  final PythonBiometricService _pythonBiometricService;
  final WallpaperService _wallpaperService;
  final StorageService _storageService;

  List<AppConfig> _vaults = const <AppConfig>[];
  final Set<String> _recoveredWorkspaceVaultIds = <String>{};
  String? _selectedVaultId;
  List<VaultEntry> _entries = const <VaultEntry>[];
  List<int>? _vaultKey;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _statusMessage;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  bool get hasVaults => _vaults.isNotEmpty;
  bool get hasSelectedVault => selectedVault != null;
  bool get isUnlocked => _vaultKey != null;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  List<AppConfig> get vaults => _vaults;
  List<VaultEntry> get entries => _entries;
  Set<String> get recoveredWorkspaceVaultIds => _recoveredWorkspaceVaultIds;
  AppConfig? get selectedVault {
    final selectedId = _selectedVaultId;
    if (selectedId == null) {
      return null;
    }
    for (final vault in _vaults) {
      if (vault.id == selectedId) {
        return vault;
      }
    }
    return null;
  }

  AppConfig? get config => selectedVault;
  String? get wallpaperAsset =>
      selectedVault?.wallpaperAsset ?? defaultWallpaperAsset;
  String? get workspaceDirectory => selectedVault == null
      ? null
      : _storageService.workspaceDirectoryPath(selectedVault!.vaultDirectory);

  Future<void> initialize() async {
    _setLoading(true, message: 'Loading local vault state...');
    try {
      final registry = await _configService.loadRegistry();
      _vaults = registry.vaults;
      _selectedVaultId = null;
      _recoveredWorkspaceVaultIds.clear();
      for (final vault in _vaults) {
        if (await _storageService.workspaceExists(vault.vaultDirectory)) {
          _recoveredWorkspaceVaultIds.add(vault.id);
        }
      }

      if (_vaults.isEmpty) {
        _statusMessage = 'Name your first vault and pick where it should live.';
      } else {
        _statusMessage =
            'Pick a vault to open. The app itself does not need your passphrase, only the vault does.';
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _setLoading(false);
    }
  }

  void selectVault(String vaultId) {
    _selectedVaultId = vaultId;
    _vaultKey = null;
    _entries = const <VaultEntry>[];
    _statusMessage = 'Vault selected. Passphrase and biometrics, please.';
    notifyListeners();
  }

  void backToVaultPicker() {
    _selectedVaultId = null;
    _vaultKey = null;
    _entries = const <VaultEntry>[];
    _statusMessage =
        'Pick a vault. No secret handshake required until you open one.';
    notifyListeners();
  }

  Future<void> createVaultWithNewSecurity({
    required String vaultName,
    required String parentDirectory,
    required String passphrase,
    required String gestureLabel,
  }) async {
    await _runBusy(
      'Opening webcam enrollment for face, blink, and hand gesture capture...',
      () async {
        final salt = _cryptoService.randomBytes(16);
        final userKey = await _cryptoService.deriveUserKey(
          passphrase: passphrase,
          salt: salt,
        );
        final bioKey = _cryptoService.randomBytes(_cryptoService.keyLength);
        final vaultKey = _cryptoService.xor(userKey, bioKey);
        final vaultDirectory = await _storageService.prepareVaultDirectory(
          parentDirectory,
        );
        final metadataFilePath = path.join(vaultDirectory, 'registry.bin');
        final profilePath = _storageService.profileFilePath(vaultDirectory);
        final now = DateTime.now().toIso8601String();

        final config = AppConfig(
          id: _newVaultId(),
          vaultName: vaultName.trim(),
          vaultDirectory: vaultDirectory,
          metadataFilePath: metadataFilePath,
          biometricProfilePath: profilePath,
          saltBase64: base64Encode(salt),
          gestureLabel: gestureLabel,
          createdAtIso: now,
          lastOpenedIso: now,
          wallpaperAsset: defaultWallpaperAsset,
        );

        final profile = await _pythonBiometricService.enroll(
          gestureLabel: gestureLabel,
          bioKeyBase64: base64Encode(bioKey),
          handMode: 'double',
        );
        await _storageService.writeEncryptedProfile(
          targetPath: profilePath,
          profile: profile,
          profileKey: userKey,
        );
        await _storageService.initializeMetadata(
          config: config,
          vaultKey: vaultKey,
        );
        await _storageService.writeVaultManifest(
          config: config,
          manifest: VaultManifest(
            vaultName: config.vaultName,
            saltBase64: config.saltBase64,
            gestureLabel: config.gestureLabel,
            createdAtIso: config.createdAtIso,
            vaultId: config.id,
            wallpaperAsset: config.wallpaperAsset,
          ),
        );

        _upsertVault(config);
        await _persistRegistry();

        _selectedVaultId = config.id;
        _vaultKey = vaultKey;
        _entries = await _storageService.unlockWorkspace(
          config: config,
          vaultKey: vaultKey,
        );
        _statusMessage =
            'Vault "${config.vaultName}" created successfully.';
      },
    );
  }

  Future<void> createVaultWithReusedSecurity({
    required String vaultName,
    required String parentDirectory,
    required String currentPassphrase,
  }) async {
    final currentVault = selectedVault;
    if (currentVault == null || _vaultKey == null) {
      return;
    }

    await _runBusy(
      'Confirming current passphrase and biometrics, then cloning that security for the new vault...',
      () async {
        final currentUserKey = await _cryptoService.deriveUserKey(
          passphrase: currentPassphrase,
          salt: base64Decode(currentVault.saltBase64),
        );
        final currentBioKey = await _verifyBiometrics(
          config: currentVault,
          profileKey: currentUserKey,
          gestureLabel: currentVault.gestureLabel,
        );
        final currentDerivedVaultKey = _cryptoService.xor(
          currentUserKey,
          currentBioKey,
        );

        // Prove the old credentials can decrypt the current vault before any mutation.
        await _storageService.loadEntries(
          config: currentVault,
          vaultKey: currentDerivedVaultKey,
        );
        await _storageService.syncWorkspaceToVault(
          config: currentVault,
          vaultKey: currentDerivedVaultKey,
        );
        _entries = await _storageService.unlockWorkspace(
          config: currentVault,
          vaultKey: currentDerivedVaultKey,
        );
        _vaultKey = currentDerivedVaultKey;

        final vaultDirectory = await _storageService.prepareVaultDirectory(
          parentDirectory,
        );
        final metadataFilePath = path.join(vaultDirectory, 'registry.bin');
        final profilePath = _storageService.profileFilePath(vaultDirectory);
        final now = DateTime.now().toIso8601String();
        final config = AppConfig(
          id: _newVaultId(),
          vaultName: vaultName.trim(),
          vaultDirectory: vaultDirectory,
          metadataFilePath: metadataFilePath,
          biometricProfilePath: profilePath,
          saltBase64: currentVault.saltBase64,
          gestureLabel: currentVault.gestureLabel,
          createdAtIso: now,
          lastOpenedIso: now,
          wallpaperAsset: currentVault.wallpaperAsset ?? defaultWallpaperAsset,
        );

        final currentProfile = await _storageService.readProfile(
          profilePath: currentVault.biometricProfilePath,
          profileKey: currentUserKey,
        );
        await _storageService.writeEncryptedProfile(
          targetPath: profilePath,
          profile: currentProfile,
          profileKey: currentUserKey,
        );
        await _storageService.initializeMetadata(
          config: config,
          vaultKey: currentDerivedVaultKey,
        );
        await _storageService.writeVaultManifest(
          config: config,
          manifest: VaultManifest(
            vaultName: config.vaultName,
            saltBase64: config.saltBase64,
            gestureLabel: config.gestureLabel,
            createdAtIso: config.createdAtIso,
            vaultId: config.id,
            wallpaperAsset: config.wallpaperAsset,
          ),
        );

        _upsertVault(config);
        await _persistRegistry();
        _selectedVaultId = config.id;
        _vaultKey = currentDerivedVaultKey;
        _entries = await _storageService.unlockWorkspace(
          config: config,
          vaultKey: currentDerivedVaultKey,
        );
        _statusMessage =
            'Vault "${config.vaultName}" created with the same security setup.';
      },
      onError: (error) {
        if (error is SecretBoxAuthenticationError) {
          return 'Current passphrase is incorrect for reusing this vault security.';
        }
        return null;
      },
    );
  }

  Future<List<WallpaperOption>> loadWallpapers() {
    return _wallpaperService.loadWallpapers();
  }

  Future<void> recoverVaultsFromLocation(String location) async {
    final normalizedLocation = location.trim();
    if (normalizedLocation.isEmpty) {
      return;
    }

    await _runBusy(
      'Scanning folders for vaults and rebuilding the registry...',
      () async {
        final discoveredVaults = await _storageService.discoverVaults(
          normalizedLocation,
        );
        if (discoveredVaults.isEmpty) {
          throw StateError(
            'No recoverable vaults were found in that location.',
          );
        }

        var added = 0;
        var alreadyKnown = 0;
        for (final discovered in discoveredVaults) {
          final exists = _vaults.any(
            (vault) =>
                path.normalize(vault.vaultDirectory) ==
                path.normalize(discovered.vaultDirectory),
          );
          if (exists) {
            alreadyKnown++;
            continue;
          }

          _upsertVault(
            discovered.copyWith(
              wallpaperAsset:
                  discovered.wallpaperAsset ?? defaultWallpaperAsset,
            ),
          );
          added++;
        }

        if (added > 0) {
          await _persistRegistry();
        }

        if (added > 0) {
          _statusMessage =
              'Recovered $added vault${added == 1 ? '' : 's'} from disk.';
        } else if (alreadyKnown > 0) {
          _statusMessage =
              'Found $alreadyKnown vault${alreadyKnown == 1 ? '' : 's'} there, but they were already known.';
        } else {
          _statusMessage = 'No new vaults were added from that location.';
        }
      },
    );
  }

  Future<void> exportRecoveryInfo({bool selectedOnly = false}) async {
    final sourceVaults = selectedOnly
        ? (selectedVault == null
              ? const <AppConfig>[]
              : <AppConfig>[selectedVault!])
        : _vaults;
    if (sourceVaults.isEmpty) {
      _errorMessage =
          'There are no vaults available to export recovery info for.';
      notifyListeners();
      return;
    }

    try {
      final location = await getSaveLocation(
        suggestedName:
            'vault_os_recovery_${DateTime.now().toIso8601String().split('T').first}.json',
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'JSON', extensions: <String>['json']),
        ],
        confirmButtonText: 'Save recovery info',
      );
      if (location == null) {
        return;
      }

      final payload = <String, dynamic>{
        'exportedAtIso': DateTime.now().toIso8601String(),
        'vaults': <Map<String, dynamic>>[],
      };

      for (final vault in sourceVaults) {
        final manifest = await _storageService.tryReadVaultManifest(
          vault.vaultDirectory,
        );
        (payload['vaults'] as List<Map<String, dynamic>>).add(<String, dynamic>{
          'id': vault.id,
          'vaultName': vault.vaultName,
          'vaultDirectory': vault.vaultDirectory,
          'metadataFilePath': vault.metadataFilePath,
          'biometricProfilePath': vault.biometricProfilePath,
          'saltBase64': vault.saltBase64,
          'gestureLabel': vault.gestureLabel,
          'createdAtIso': vault.createdAtIso,
          'lastOpenedIso': vault.lastOpenedIso,
          'wallpaperAsset': vault.wallpaperAsset,
          'manifest': manifest?.toJson(),
        });
      }

      final encoder = const JsonEncoder.withIndent('  ');
      await File(
        location.path,
      ).writeAsString(encoder.convert(payload), flush: true);
      _statusMessage =
          'Recovery info exported. Keep it somewhere safe.';
      notifyListeners();
    } on PlatformException catch (error) {
      _errorMessage =
          'The desktop save dialog is not attached to this running app instance yet. Do a full stop and run again.\n\n${error.message ?? error.code}';
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> importRecoveryInfo() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'JSON', extensions: <String>['json']),
        ],
        confirmButtonText: 'Import recovery info',
      );
      if (file == null) {
        return;
      }

      final source = await File(file.path).readAsString();
      final payload = jsonDecode(source);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid recovery file format.');
      }

      final rawVaults = payload['vaults'];
      if (rawVaults is! List) {
        throw const FormatException('Recovery file does not contain a vault list.');
      }

      var added = 0;
      var updated = 0;
      for (final rawVault in rawVaults) {
        if (rawVault is! Map<String, dynamic>) {
          continue;
        }

        final importedConfig = AppConfig.fromJson(rawVault).copyWith(
          wallpaperAsset:
              rawVault['wallpaperAsset'] as String? ?? defaultWallpaperAsset,
        );

        final existingIndex = _vaults.indexWhere(
          (vault) =>
              path.normalize(vault.vaultDirectory) ==
              path.normalize(importedConfig.vaultDirectory),
        );

        if (existingIndex >= 0) {
          _vaults = <AppConfig>[
            for (var i = 0; i < _vaults.length; i++)
              if (i == existingIndex) importedConfig else _vaults[i],
          ];
          updated++;
        } else {
          _upsertVault(importedConfig);
          added++;
        }
      }

      if (added == 0 && updated == 0) {
        _statusMessage = 'No vault records were imported from that file.';
        notifyListeners();
        return;
      }

      await _persistRegistry();
      _statusMessage =
          'Recovery info imported. Added $added vault${added == 1 ? '' : 's'} and updated $updated.';
      notifyListeners();
    } on PlatformException catch (error) {
      _errorMessage =
          'The desktop file picker is not attached to this running app instance yet. Do a full stop and run again.\n\n${error.message ?? error.code}';
      notifyListeners();
    } on FormatException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> applyWallpaper(String? assetPath) async {
    final config = selectedVault;
    if (config == null) {
      return;
    }

    final updated = assetPath == null
        ? config.copyWith(clearWallpaperAsset: true)
        : config.copyWith(wallpaperAsset: assetPath);
    _upsertVault(updated);
    await _storageService.writeVaultManifest(
      config: updated,
      manifest: VaultManifest(
        vaultName: updated.vaultName,
        saltBase64: updated.saltBase64,
        gestureLabel: updated.gestureLabel,
        createdAtIso: updated.createdAtIso,
        vaultId: updated.id,
        wallpaperAsset: updated.wallpaperAsset,
      ),
    );
    await _persistRegistry();
    _statusMessage = assetPath == null
        ? 'Wallpaper cleared.'
        : 'Wallpaper updated.';
    notifyListeners();
  }

  Future<void> unlock(String passphrase) async {
    final config = selectedVault;
    if (config == null) {
      _errorMessage = 'Pick a vault first.';
      notifyListeners();
      return;
    }

    await _runBusy(
      'Opening webcam verification for face, blink, and hand gesture checks...',
      () async {
        final userKey = await _cryptoService.deriveUserKey(
          passphrase: passphrase,
          salt: base64Decode(config.saltBase64),
        );
        final bioKey = await _verifyBiometrics(
          config: config,
          profileKey: userKey,
          gestureLabel: config.gestureLabel,
        );
        final vaultKey = _cryptoService.xor(userKey, bioKey);
        final entries = await _storageService.unlockWorkspace(
          config: config,
          vaultKey: vaultKey,
        );
        final updated = config.copyWith(
          lastOpenedIso: DateTime.now().toIso8601String(),
        );
        _upsertVault(updated);
        await _persistRegistry();

        _vaultKey = vaultKey;
        _entries = entries;
        _statusMessage =
            'Vault "${updated.vaultName}" unlocked.';
      },
      onError: (error) {
        if (error is SecretBoxAuthenticationError) {
          return 'Unlock failed. The passphrase is wrong, or the vault data has changed.';
        }
        return null;
      },
    );
  }

  Future<void> changePassphrase({
    required String oldPassphrase,
    required String newPassphrase,
  }) async {
    final config = selectedVault;
    if (config == null) {
      return;
    }

    await _runBusy(
      'Verifying current passphrase and biometrics before rotating the vault key...',
      () async {
        final currentUserKey = await _cryptoService.deriveUserKey(
          passphrase: oldPassphrase,
          salt: base64Decode(config.saltBase64),
        );
        final currentBioKey = await _verifyBiometrics(
          config: config,
          profileKey: currentUserKey,
          gestureLabel: config.gestureLabel,
        );
        final currentVaultKey = _cryptoService.xor(
          currentUserKey,
          currentBioKey,
        );
        // Validate the old passphrase + biometrics before rewriting anything.
        await _storageService.loadEntries(
          config: config,
          vaultKey: currentVaultKey,
        );
        await _storageService.syncWorkspaceToVault(
          config: config,
          vaultKey: currentVaultKey,
        );

        final newSalt = _cryptoService.randomBytes(16);
        final newUserKey = await _cryptoService.deriveUserKey(
          passphrase: newPassphrase,
          salt: newSalt,
        );
        final newVaultKey = _cryptoService.xor(newUserKey, currentBioKey);
        await _storageService.reencryptVault(
          config: config,
          oldVaultKey: currentVaultKey,
          newVaultKey: newVaultKey,
        );

        final migratedProfilePath = _storageService.profileFilePath(
          config.vaultDirectory,
        );
        final existingProfile = await _storageService.readProfile(
          profilePath: config.biometricProfilePath,
          profileKey: currentUserKey,
        );
        await _storageService.writeEncryptedProfile(
          targetPath: migratedProfilePath,
          profile: existingProfile,
          profileKey: newUserKey,
        );

        final updated = config.copyWith(
          saltBase64: base64Encode(newSalt),
          biometricProfilePath: migratedProfilePath,
        );
        await _storageService.writeVaultManifest(
          config: updated,
          manifest: VaultManifest(
            vaultName: updated.vaultName,
            saltBase64: updated.saltBase64,
            gestureLabel: updated.gestureLabel,
            createdAtIso: updated.createdAtIso,
            vaultId: updated.id,
            wallpaperAsset: updated.wallpaperAsset,
          ),
        );
        _upsertVault(updated);
        await _persistRegistry();
        _vaultKey = newVaultKey;
        _entries = await _storageService.unlockWorkspace(
          config: updated,
          vaultKey: newVaultKey,
        );
        _statusMessage = 'Passphrase updated and workspace reopened.';
      },
      onError: (error) {
        if (error is SecretBoxAuthenticationError) {
          return 'Current passphrase is incorrect for this vault.';
        }
        return null;
      },
    );
  }

  Future<void> reEnrollBiometrics({
    required String currentPassphrase,
    required String newGestureLabel,
  }) async {
    final config = selectedVault;
    if (config == null) {
      return;
    }

    await _runBusy(
      'Confirming the current vault, then opening fresh biometric enrollment...',
      () async {
        final currentUserKey = await _cryptoService.deriveUserKey(
          passphrase: currentPassphrase,
          salt: base64Decode(config.saltBase64),
        );
        final oldBioKey = await _verifyBiometrics(
          config: config,
          profileKey: currentUserKey,
          gestureLabel: config.gestureLabel,
        );
        final oldVaultKey = _cryptoService.xor(currentUserKey, oldBioKey);
        // Validate the current credentials before touching the encrypted vault.
        await _storageService.loadEntries(
          config: config,
          vaultKey: oldVaultKey,
        );
        await _storageService.syncWorkspaceToVault(
          config: config,
          vaultKey: oldVaultKey,
        );

        final newBioKey = _cryptoService.randomBytes(_cryptoService.keyLength);
        final updatedProfilePath = _storageService.profileFilePath(
          config.vaultDirectory,
        );

        final enrolledProfile = await _pythonBiometricService.enroll(
          gestureLabel: newGestureLabel,
          bioKeyBase64: base64Encode(newBioKey),
          handMode: 'double',
        );

        final newVaultKey = _cryptoService.xor(currentUserKey, newBioKey);
        await _storageService.reencryptVault(
          config: config,
          oldVaultKey: oldVaultKey,
          newVaultKey: newVaultKey,
        );

        await _storageService.writeEncryptedProfile(
          targetPath: updatedProfilePath,
          profile: enrolledProfile,
          profileKey: currentUserKey,
        );

        final updated = config.copyWith(
          gestureLabel: newGestureLabel,
          biometricProfilePath: updatedProfilePath,
        );
        await _storageService.writeVaultManifest(
          config: updated,
          manifest: VaultManifest(
            vaultName: updated.vaultName,
            saltBase64: updated.saltBase64,
            gestureLabel: updated.gestureLabel,
            createdAtIso: updated.createdAtIso,
            vaultId: updated.id,
            wallpaperAsset: updated.wallpaperAsset,
          ),
        );
        _upsertVault(updated);
        await _persistRegistry();
        _vaultKey = newVaultKey;
        _entries = await _storageService.unlockWorkspace(
          config: updated,
          vaultKey: newVaultKey,
        );
        _statusMessage = 'Biometric profile refreshed and workspace reopened.';
      },
      onError: (error) {
        if (error is SecretBoxAuthenticationError) {
          return 'Current passphrase is incorrect for this vault.';
        }
        return null;
      },
    );
  }

  Future<void> importFiles() async {
    try {
      final files = await openFiles();
      if (files.isEmpty) {
        return;
      }
      await importFilesFromPaths(files.map((file) => file.path));
    } on PlatformException catch (error) {
      _errorMessage =
          'The desktop file picker is not attached to this running app instance yet. Do a full stop and run again, or use drag and drop for now.\n\n${error.message ?? error.code}';
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<String?> pickDirectory({
    String? initialDirectory,
    String confirmButtonText = 'Choose folder',
  }) async {
    try {
      return await getDirectoryPath(
        initialDirectory: initialDirectory,
        confirmButtonText: confirmButtonText,
      );
    } on PlatformException catch (error) {
      _errorMessage =
          'The desktop folder picker is not attached to this running app instance yet. Do a full stop and run again.\n\n${error.message ?? error.code}';
      notifyListeners();
      return null;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> importFilesFromPaths(Iterable<String> paths) async {
    final config = selectedVault;
    if (config == null || _vaultKey == null) {
      return;
    }

    final normalizedPaths = paths
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedPaths.isEmpty) {
      return;
    }

    await _runBusy('Moving files into the unlocked workspace...', () async {
      final resolvedPaths = <String>[];
      for (final filePath in normalizedPaths) {
        final resolvedPath = _normalizeIncomingPath(filePath);
        final file = File(resolvedPath);
        final directory = Directory(resolvedPath);
        if (!await file.exists() && !await directory.exists()) {
          continue;
        }
        resolvedPaths.add(resolvedPath);
      }

      if (resolvedPaths.isEmpty) {
        _statusMessage = 'No valid files were moved into the workspace.';
        return;
      }

      await _storageService.moveSourceIntoWorkspace(
        workspaceDirectory: workspaceDirectory!,
        sourcePaths: resolvedPaths,
      );
      _entries = await _storageService.loadWorkspaceEntries(
        workspaceDirectory!,
      );
      _statusMessage =
          '${resolvedPaths.length} item${resolvedPaths.length == 1 ? '' : 's'} moved into "${config.vaultName}".';
    });
  }

  Future<void> refreshEntries() async {
    if (selectedVault == null || _vaultKey == null) {
      return;
    }

    await _runBusy('Refreshing unlocked workspace...', () async {
      _entries = await _storageService.loadWorkspaceEntries(
        workspaceDirectory!,
      );
      _statusMessage = 'Workspace file list refreshed.';
    });
  }

  Future<void> openPreviousVault({
    required String previousParentDirectory,
    required String previousPassphrase,
  }) async {
    final currentConfig = selectedVault;
    if (currentConfig == null || _vaultKey == null) {
      return;
    }

    final normalizedLocation = previousParentDirectory.trim();
    if (normalizedLocation.isEmpty) {
      return;
    }

    await _runBusy(
      'Opening previous vault and unlocking its own workspace...',
      () async {
        final previousConfig = await _storageService.externalConfigFromLocation(
          normalizedLocation,
        );
        if (path.normalize(previousConfig.vaultDirectory) ==
            path.normalize(currentConfig.vaultDirectory)) {
          throw StateError('That is already the current vault.');
        }
        final previousUserKey = await _cryptoService.deriveUserKey(
          passphrase: previousPassphrase,
          salt: base64Decode(previousConfig.saltBase64),
        );
        final previousBioKey = await _verifyBiometrics(
          config: previousConfig,
          profileKey: previousUserKey,
          gestureLabel: previousConfig.gestureLabel,
        );
        final previousVaultKey = _cryptoService.xor(
          previousUserKey,
          previousBioKey,
        );

        await _storageService.unlockWorkspace(
          config: previousConfig,
          vaultKey: previousVaultKey,
        );
        final previousWorkspace = _storageService.workspaceDirectoryPath(
          previousConfig.vaultDirectory,
        );

        if (Platform.isWindows) {
          await Process.run('explorer.exe', <String>[previousWorkspace]);
        } else {
          await Process.run('open', <String>[previousWorkspace]);
        }

        _statusMessage =
            'Previous vault "${previousConfig.vaultName}" unlocked in its own workspace.';
      },
      onError: (error) {
        if (error is SecretBoxAuthenticationError) {
          return 'Previous vault passphrase is incorrect.';
        }
        return null;
      },
    );
  }

  Future<void> revealVaultLocation() async {
    if (selectedVault == null || _vaultKey == null) {
      return;
    }
    final targetPath = workspaceDirectory!;
    if (Platform.isWindows) {
      await Process.run('explorer.exe', <String>[targetPath]);
      return;
    }
    final directory = Directory(targetPath);
    if (await directory.exists()) {
      await Process.run('open', <String>[directory.path]);
    }
  }

  Future<void> revealFile(VaultEntry entry) async {
    if (selectedVault == null || _vaultKey == null) {
      return;
    }
    final filePath = '${workspaceDirectory!}${Platform.pathSeparator}${entry.relativePath}';
    if (Platform.isWindows) {
      await Process.run('explorer.exe', <String>['/select,', filePath]);
      return;
    }
    final file = File(filePath);
    if (await file.exists()) {
      await Process.run('open', <String>['-R', filePath]);
    }
  }

  Future<void> deleteEntry(VaultEntry entry) async {
    if (selectedVault == null || _vaultKey == null) {
      return;
    }

    await _runBusy('Removing file from the unlocked workspace...', () async {
      await _storageService.deleteWorkspaceEntry(
        workspaceDirectory: workspaceDirectory!,
        entry: entry,
      );
      _entries = await _storageService.loadWorkspaceEntries(
        workspaceDirectory!,
      );
      _statusMessage = '${entry.displayName} removed from the workspace.';
    });
  }

  Future<PreviewPayload> previewEntry(VaultEntry entry) async {
    if (selectedVault == null || _vaultKey == null) {
      throw StateError('Vault is locked.');
    }

    return _storageService.readWorkspacePreview(
      workspaceDirectory: workspaceDirectory!,
      entry: entry,
    );
  }

  Future<String?> suggestedDocumentsDirectory() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final documents = Directory(path.join(userProfile, 'Documents'));
        if (await documents.exists()) {
          return documents.path;
        }
      }
    }

    final downloads = await getDownloadsDirectory();
    return downloads?.path;
  }

  Future<String?> suggestedDesktopDirectory() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final desktop = Directory(path.join(userProfile, 'Desktop'));
        if (await desktop.exists()) {
          return desktop.path;
        }
      }
    }

    return null;
  }

  Future<void> lock() async {
    final config = selectedVault;
    final vaultKey = _vaultKey;
    if (config == null || vaultKey == null) {
      return;
    }

    await _runBusy('Encrypting workspace back into the vault...', () async {
      final encryptedEntries = await _storageService.syncWorkspaceToVault(
        config: config,
        vaultKey: vaultKey,
      );
      _vaultKey = null;
      _entries = const <VaultEntry>[];
      _selectedVaultId = null;
      _statusMessage = encryptedEntries.isEmpty
          ? 'Vault locked. Workspace cleared.'
          : 'Vault locked. Workspace encrypted again.';
    });
  }

  Future<bool> autoLockIfNeeded() async {
    final config = selectedVault;
    final vaultKey = _vaultKey;
    if (config == null || vaultKey == null) {
      return true;
    }

    try {
      await _storageService.syncWorkspaceToVault(
        config: config,
        vaultKey: vaultKey,
      );
      _vaultKey = null;
      _entries = const <VaultEntry>[];
      _selectedVaultId = null;
      _statusMessage = 'Vault auto-locked during app exit.';
      notifyListeners();
      return true;
    } catch (error) {
      _errorMessage = 'Auto-lock failed during app exit: $error';
      notifyListeners();
      return false;
    }
  }

  Future<void> resetEnrollment({required String currentPassphrase}) async {
    final config = selectedVault;
    if (config == null) {
      return;
    }

    await _runBusy(
      'Confirming passphrase and biometrics before resetting the vault...',
      () async {
        final userKey = await _cryptoService.deriveUserKey(
          passphrase: currentPassphrase,
          salt: base64Decode(config.saltBase64),
        );
        final bioKey = await _verifyBiometrics(
          config: config,
          profileKey: userKey,
          gestureLabel: config.gestureLabel,
        );
        final vaultKey = _cryptoService.xor(userKey, bioKey);
        await _storageService.loadEntries(config: config, vaultKey: vaultKey);

        await _storageService.deleteVaultDirectory(config.vaultDirectory);
        _vaults = _vaults
            .where((vault) => vault.id != config.id)
            .toList(growable: false);
        _selectedVaultId = null;
        _vaultKey = null;
        _entries = const <VaultEntry>[];
        await _persistRegistry();
        _statusMessage = _vaults.isEmpty
            ? 'Vault reset complete. Time to name a fresh one.'
            : 'Vault removed. The rest of the vaults are still intact.';
      },
      onError: (error) {
        if (error is SecretBoxAuthenticationError) {
          return 'Reset failed. The current passphrase does not match this vault.';
        }
        return null;
      },
    );
  }

  Future<void> _persistRegistry() {
    return _configService.saveRegistry(
      VaultRegistry(vaults: _vaults, selectedVaultId: _selectedVaultId),
    );
  }

  void _upsertVault(AppConfig config) {
    final next = <AppConfig>[];
    var replaced = false;
    for (final vault in _vaults) {
      if (vault.id == config.id) {
        next.add(config);
        replaced = true;
      } else {
        next.add(vault);
      }
    }
    if (!replaced) {
      next.add(config);
    }
    _vaults = next;
  }

  String _newVaultId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<List<int>> _verifyBiometrics({
    required AppConfig config,
    required List<int> profileKey,
    required String gestureLabel,
  }) async {
    final runtimeProfilePath = await _storageService
        .materializeProfileForPython(
          profilePath: config.biometricProfilePath,
          profileKey: profileKey,
        );
    try {
      return await _pythonBiometricService.verify(
        profilePath: runtimeProfilePath,
        gestureLabel: gestureLabel,
      );
    } finally {
      await _storageService.deleteMaterializedProfile(runtimeProfilePath);
    }
  }

  Future<void> _runBusy(
    String message,
    Future<void> Function() operation, {
    String? Function(Object error)? onError,
  }) async {
    _setBusy(true, message: message);
    _errorMessage = null;
    try {
      await operation();
    } catch (error) {
      _errorMessage = onError?.call(error) ?? error.toString();
    } finally {
      _setBusy(false);
    }
  }

  String _normalizeIncomingPath(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('file://')) {
      return Uri.parse(trimmed).toFilePath(windows: Platform.isWindows);
    }
    return trimmed;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value, {String? message}) {
    _isLoading = value;
    if (message != null) {
      _statusMessage = message;
    }
    notifyListeners();
  }

  void _setBusy(bool value, {String? message}) {
    _isBusy = value;
    if (message != null) {
      _statusMessage = message;
    }
    notifyListeners();
  }
}
