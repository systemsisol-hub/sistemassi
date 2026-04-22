import 'dart:typed_data';

abstract class WebCameraService {
  dynamic get cameraStream;
  String get viewId;
  bool get isReady;
  Future<void> initCamera();
  void dispose();
  Future<Uint8List?> captureFrame();
}
