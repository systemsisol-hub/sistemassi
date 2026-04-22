import 'dart:typed_data';

abstract class FileSaverUtil {
  static Future<void> saveAndShare(Uint8List bytes, String fileName) async {
    throw UnimplementedError('FileSaverUtil is not implemented on this platform.');
  }
}
