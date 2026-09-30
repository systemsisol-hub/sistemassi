import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileSaverUtil {
  static Future<void> saveAndShare(
    Uint8List bytes,
    String fileName, {
    String? text,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/$fileName').create();
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
        sharePositionOrigin: _origenDelMenu(),
      );
    } catch (e) {
      debugPrint('Error saving/sharing on native: $e');
      rethrow;
    }
  }

  // iOS reciente presenta el menu de compartir como popover tambien en iPhone, y share_plus
  // falla sin mostrar nada si no recibe desde donde abrirlo. Se usa el centro de la pantalla.
  static Rect? _origenDelMenu() {
    final vistas = WidgetsBinding.instance.platformDispatcher.views;
    if (vistas.isEmpty) return null;
    final vista = vistas.first;
    final tamano = vista.physicalSize / vista.devicePixelRatio;
    return Rect.fromCenter(
      center: Offset(tamano.width / 2, tamano.height / 2),
      width: 1,
      height: 1,
    );
  }
}
