import 'dart:convert';

class VaultManifest {
  const VaultManifest({
    required this.vaultName,
    required this.saltBase64,
    required this.gestureLabel,
    required this.createdAtIso,
    this.vaultId,
    this.wallpaperAsset,
  });

  final String vaultName;
  final String saltBase64;
  final String gestureLabel;
  final String createdAtIso;
  final String? vaultId;
  final String? wallpaperAsset;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'vaultName': vaultName,
      'saltBase64': saltBase64,
      'gestureLabel': gestureLabel,
      'createdAtIso': createdAtIso,
      'vaultId': vaultId,
      'wallpaperAsset': wallpaperAsset,
    };
  }

  String encode() => jsonEncode(toJson());

  factory VaultManifest.fromJson(Map<String, dynamic> json) {
    return VaultManifest(
      vaultName: json['vaultName'] as String? ?? 'Vault',
      saltBase64: json['saltBase64'] as String,
      gestureLabel: json['gestureLabel'] as String,
      createdAtIso: json['createdAtIso'] as String,
      vaultId: json['vaultId'] as String?,
      wallpaperAsset: json['wallpaperAsset'] as String?,
    );
  }

  factory VaultManifest.decode(String source) {
    return VaultManifest.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }
}
