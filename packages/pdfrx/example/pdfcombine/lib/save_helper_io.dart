import 'dart:io';
import 'dart:typed_data';

Future<void> savePdfToFileImpl(String path, Uint8List bytes) async {
  final file = File(path);
  await file.writeAsBytes(bytes);
}
