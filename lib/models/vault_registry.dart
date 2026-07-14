import 'dart:convert';

import 'app_config.dart';

class VaultRegistry {
  const VaultRegistry({
    required this.vaults,
    this.selectedVaultId,
  });

  final List<AppConfig> vaults;
  final String? selectedVaultId;

  VaultRegistry copyWith({
    List<AppConfig>? vaults,
    String? selectedVaultId,
    bool clearSelectedVaultId = false,
  }) {
    return VaultRegistry(
      vaults: vaults ?? this.vaults,
      selectedVaultId: clearSelectedVaultId ? null : (selectedVaultId ?? this.selectedVaultId),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'vaults': vaults.map((vault) => vault.toJson()).toList(growable: false),
      'selectedVaultId': selectedVaultId,
    };
  }

  String encode() => jsonEncode(toJson());

  factory VaultRegistry.fromJson(Map<String, dynamic> json) {
    final rawVaults = (json['vaults'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    return VaultRegistry(
      vaults: rawVaults.map(AppConfig.fromJson).toList(growable: false),
      selectedVaultId: json['selectedVaultId'] as String?,
    );
  }

  factory VaultRegistry.decode(String source) {
    return VaultRegistry.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }
}
