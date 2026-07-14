import 'dart:convert';

class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.displayName,
    required this.relativePath,
    required this.storedName,
    required this.originalSize,
    required this.createdAtIso,
  });

  final String id;
  final String displayName;
  final String relativePath;
  final String storedName;
  final int originalSize;
  final String createdAtIso;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'relativePath': relativePath,
      'storedName': storedName,
      'originalSize': originalSize,
      'createdAtIso': createdAtIso,
    };
  }

  factory VaultEntry.fromJson(Map<String, dynamic> json) {
    return VaultEntry(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      relativePath: (json['relativePath'] as String?) ?? (json['displayName'] as String),
      storedName: json['storedName'] as String,
      originalSize: json['originalSize'] as int,
      createdAtIso: json['createdAtIso'] as String,
    );
  }

  static List<VaultEntry> decodeList(String source) {
    final raw = jsonDecode(source) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(VaultEntry.fromJson)
        .toList(growable: false);
  }

  static String encodeList(List<VaultEntry> entries) {
    return jsonEncode(entries.map((entry) => entry.toJson()).toList());
  }
}
