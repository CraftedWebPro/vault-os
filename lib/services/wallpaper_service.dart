import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/wallpaper_option.dart';

class WallpaperService {
  Future<List<WallpaperOption>> loadWallpapers() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();

    final wallpapers = assets
        .where((asset) => asset.startsWith('assets/themes/'))
        .where(_isSupportedImage)
        .map(
          (asset) => WallpaperOption(
            assetPath: asset,
            label: _labelize(path.basenameWithoutExtension(asset)),
          ),
        )
        .toList(growable: false)
      ..sort((left, right) => left.label.compareTo(right.label));

    return wallpapers;
  }

  bool _isSupportedImage(String asset) {
    final extension = path.extension(asset).toLowerCase();
    return extension == '.png' || extension == '.jpg' || extension == '.jpeg' || extension == '.webp';
  }

  String _labelize(String source) {
    return source
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}
