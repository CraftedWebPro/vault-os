import 'dart:convert';
import 'dart:io';

class PythonBiometricService {
  Future<Map<String, dynamic>> enroll({
    required String gestureLabel,
    required String bioKeyBase64,
    String handMode = 'double',
  }) async {
    final response = await _run(<String>[
      '--mode',
      'enroll',
      '--gesture',
      gestureLabel,
      '--bio-key',
      bioKeyBase64,
      '--hands',
      handMode,
    ]);

    if (response['ok'] != true) {
      throw StateError(
        response['message'] as String? ?? 'Biometric enrollment failed.',
      );
    }

    final profile = response['profile'];
    if (profile is! Map<String, dynamic>) {
      throw StateError('Biometric enrollment did not return a valid profile.');
    }
    return profile;
  }

  Future<List<int>> verify({
    required String profilePath,
    required String gestureLabel,
  }) async {
    final response = await _run(<String>[
      '--mode',
      'verify',
      '--profile',
      profilePath,
      '--gesture',
      gestureLabel,
    ]);

    if (response['ok'] != true) {
      throw StateError(
        response['message'] as String? ?? 'Biometric verification failed.',
      );
    }

    final bioKey = response['bio_key'] as String?;
    if (bioKey == null || bioKey.isEmpty) {
      throw StateError('Biometric service did not return a key fragment.');
    }

    return base64Decode(bioKey);
  }

  Future<Map<String, dynamic>> _run(List<String> arguments) async {
    final scriptPath = _resolveScriptPath();
    final result = await Process.run('python', <String>[
      scriptPath,
      ...arguments,
    ], runInShell: true);

    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String).trim();

    Map<String, dynamic>? parsedStdout;
    if (stdout.isNotEmpty) {
      try {
        parsedStdout = jsonDecode(stdout) as Map<String, dynamic>;
      } catch (_) {
        parsedStdout = null;
      }
    }

    if (result.exitCode != 0) {
      if (parsedStdout != null && parsedStdout['message'] is String) {
        throw StateError(parsedStdout['message'] as String);
      }

      throw StateError(_cleanPythonError(stderr.isNotEmpty ? stderr : stdout));
    }

    if (stdout.isEmpty) {
      throw StateError('Python biometric process returned no data.');
    }

    if (parsedStdout != null) {
      return parsedStdout;
    }

    throw StateError('Python biometric process returned invalid JSON.');
  }

  String _cleanPythonError(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where(
          (line) =>
              !line.startsWith('INFO:') &&
              !line.startsWith('W0000') &&
              !line.contains('face_landmarker_graph.cc') &&
              !line.contains('inference_feedback_manager.cc'),
        )
        .toList(growable: false);

    if (lines.isEmpty) {
      return 'Python biometric process failed.';
    }

    return lines.last;
  }

  String _resolveScriptPath() {
    final candidates = <String>[
      '${Directory.current.path}${Platform.pathSeparator}python_service${Platform.pathSeparator}biometric_service.py',
      '${Directory.current.path}${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}python_service${Platform.pathSeparator}biometric_service.py',
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    throw StateError('Unable to locate python_service/biometric_service.py.');
  }
}
