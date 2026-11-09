import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Reads the text in an image file, one entry per line, on this device.
typedef ReadText = Future<List<String>> Function(String imagePath);

class OcrUnavailable implements Exception {
  const OcrUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Android uses Google's on-device text recognizer, bundled with the app. On
/// Windows and Linux, Vastra uses Tesseract when it is installed. No image
/// is sent anywhere.
Future<List<String>> readText(String imagePath) async {
  if (Platform.isAndroid) {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return [
        for (final block in result.blocks)
          for (final line in block.lines) line.text,
      ];
    } finally {
      await recognizer.close();
    }
  }
  final tesseract = _tesseract();
  if (tesseract == null) {
    throw OcrUnavailable(
      Platform.isWindows
          ? 'Reading screenshots on Windows needs Tesseract. Install it from github.com/UB-Mannheim/tesseract, then try again.'
          : 'Reading screenshots needs Tesseract. Install the "tesseract" and English language packages, then try again.',
    );
  }
  final result = await Process.run(tesseract, [
    imagePath,
    'stdout',
    '-l',
    'eng',
  ]).timeout(const Duration(seconds: 60));
  if (result.exitCode != 0) throw const OcrUnavailable('Tesseract could not read that image.');
  return (result.stdout as String).split('\n');
}

String? _tesseract() {
  final candidates = [
    if (Platform.isWindows) ...[
      r'C:\Program Files\Tesseract-OCR\tesseract.exe',
      r'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe',
    ],
    for (final dir in (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':'))
      if (dir.isNotEmpty) '$dir${Platform.pathSeparator}tesseract${Platform.isWindows ? '.exe' : ''}',
  ];
  return candidates.where((c) => File(c).existsSync()).firstOrNull;
}
