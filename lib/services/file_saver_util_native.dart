import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileSaverUtil {
  static Future<void> saveAndShare(Uint8List bytes, String fileName) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/$fileName').create();
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Mi firma profesional');
    } catch (e) {
      print('Error saving/sharing on native: $e');
    }
  }
}
