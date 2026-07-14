import 'dart:convert';

class AppConfig {
  const AppConfig({
    required this.id,
    required this.vaultName,
    required this.vaultDirectory,
    required this.metadataFilePath,
    required this.biometricProfilePath,
    required this.saltBase64,
    required this.gestureLabel,
    required this.createdAtIso,
    this.lastOpenedIso,
    this.wallpaperAsset,
  });

  final String id;
  final String vaultName;
  final String vaultDirectory;
  final String metadataFilePath;
  final String biometricProfilePath;
  final String saltBase64;
  final String gestureLabel;
  final String createdAtIso;
  final String? lastOpenedIso;
  final String? wallpaperAsset;

  AppConfig copyWith({
    String? id,
    String? vaultName,
    String? vaultDirectory,
    String? metadataFilePath,
    String? biometricProfilePath,
    String? saltBase64,
    String? gestureLabel,
    String? createdAtIso,
    String? lastOpenedIso,
    String? wallpaperAsset,
    bool clearLastOpenedIso = false,
    bool clearWallpaperAsset = false,
  }) {
    return AppConfig(
      id: id ?? this.id,
      vaultName: vaultName ?? this.vaultName,
      vaultDirectory: vaultDirectory ?? this.vaultDirectory,
      metadataFilePath: metadataFilePath ?? this.metadataFilePath,
      biometricProfilePath: biometricProfilePath ?? this.biometricProfilePath,
      saltBase64: saltBase64 ?? this.saltBase64,
      gestureLabel: gestureLabel ?? this.gestureLabel,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      lastOpenedIso: clearLastOpenedIso ? null : (lastOpenedIso ?? this.lastOpenedIso),
      wallpaperAsset: clearWallpaperAsset ? null : (wallpaperAsset ?? this.wallpaperAsset),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'vaultName': vaultName,
      'vaultDirectory': vaultDirectory,
      'metadataFilePath': metadataFilePath,
      'biometricProfilePath': biometricProfilePath,
      'saltBase64': saltBase64,
      'gestureLabel': gestureLabel,
      'createdAtIso': createdAtIso,
      'lastOpenedIso': lastOpenedIso,
      'wallpaperAsset': wallpaperAsset,
    };
  }

  String encode() => jsonEncode(toJson());

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      id: json['id'] as String? ?? json['vaultDirectory'] as String,
      vaultName: json['vaultName'] as String? ?? 'Vault',
      vaultDirectory: json['vaultDirectory'] as String,
      metadataFilePath: json['metadataFilePath'] as String,
      biometricProfilePath: json['biometricProfilePath'] as String,
      saltBase64: json['saltBase64'] as String,
      gestureLabel: json['gestureLabel'] as String,
      createdAtIso: json['createdAtIso'] as String,
      lastOpenedIso: json['lastOpenedIso'] as String?,
      wallpaperAsset: json['wallpaperAsset'] as String?,
    );
  }

  factory AppConfig.decode(String source) {
    return AppConfig.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }
}
