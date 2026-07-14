import 'dart:io';

class WindowsVisibilityService {
  Future<void> hide(String targetPath) async {
    if (!Platform.isWindows) {
      return;
    }

    await Process.run(
      'attrib',
      <String>[
        '+h',
        targetPath,
      ],
      runInShell: true,
    );
  }

  Future<void> unhide(String targetPath) async {
    if (!Platform.isWindows) {
      return;
    }

    await Process.run(
      'attrib',
      <String>[
        '-h',
        targetPath,
      ],
      runInShell: true,
    );
  }
}
