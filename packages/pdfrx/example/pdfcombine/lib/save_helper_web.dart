import 'dart:typed_data';

// On Web, saving is handled by share_plus, so this is a no-op
Future<void> savePdfToFileImpl(String path, Uint8List bytes) async {
  // No-op on Web - file saving is handled by share_plus
}
