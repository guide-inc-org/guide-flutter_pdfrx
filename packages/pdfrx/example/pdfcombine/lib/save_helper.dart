import 'dart:typed_data';

import 'save_helper_stub.dart'
    if (dart.library.io) 'save_helper_io.dart'
    if (dart.library.js) 'save_helper_web.dart';

/// Save PDF bytes to a file at the given path
Future<void> savePdfToFile(String path, Uint8List bytes) {
  return savePdfToFileImpl(path, bytes);
}
