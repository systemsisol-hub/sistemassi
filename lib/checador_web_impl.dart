import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;

String createCameraViewId() {
  return 'camera-preview-${DateTime.now().millisecondsSinceEpoch}';
}

class CameraController {
  final String viewId;
  dynamic _cameraStream;
  bool _isReady = false;

  CameraController() : viewId = createCameraViewId();

  bool get isReady => _isReady;
  dynamic get cameraStream => _cameraStream;
  dynamic get controller => null;

  Future<void> initCamera() async {
    try {
      final stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {'facingMode': 'user'},
        'audio': false
      });
      _cameraStream = stream;

      ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
        final video = html.VideoElement()
          ..srcObject = stream
          ..autoplay = true
          ..muted = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.transform = 'scaleX(-1)';
        return video;
      });

      _isReady = true;
    } catch (e) {
      print('Error iniciando cámara web: $e');
    }
  }

  void dispose() {
    if (_cameraStream != null) {
      for (final track in _cameraStream.getTracks()) {
        track.stop();
      }
      _cameraStream = null;
    }
  }

  Future<Uint8List?> captureFrame() async {
    final videos = html.document.querySelectorAll('video');
    html.VideoElement? videoEl;
    for (final el in videos) {
      if (el is html.VideoElement && el.srcObject != null) {
        videoEl = el;
        break;
      }
    }
    if (videoEl == null) return null;

    final w = videoEl.videoWidth > 0 ? videoEl.videoWidth : 640;
    final h = videoEl.videoHeight > 0 ? videoEl.videoHeight : 480;
    final canvas = html.CanvasElement()
      ..width = w.toInt()
      ..height = h.toInt();
    final ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D;
    ctx.translate(w.toDouble(), 0);
    ctx.scale(-1, 1);
    ctx.drawImage(videoEl, 0, 0);

    final blob = await canvas.toBlob('image/jpeg', 0.85);
    final reader = html.FileReader()..readAsArrayBuffer(blob);
    await reader.onLoad.first;
    return reader.result as Uint8List?;
  }
}

typedef NativeCameraController = CameraController;

class WebCameraController {
  final String viewId;
  dynamic _cameraStream;
  bool _isReady = false;

  WebCameraController() : viewId = createCameraViewId();

  bool get isReady => _isReady;
  dynamic get cameraStream => _cameraStream;

  Future<void> initCamera() async {
    try {
      final stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {'facingMode': 'user'},
        'audio': false
      });
      _cameraStream = stream;

      ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
        final video = html.VideoElement()
          ..srcObject = stream
          ..autoplay = true
          ..muted = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.transform = 'scaleX(-1)';
        return video;
      });

      _isReady = true;
    } catch (e) {
      print('Error iniciando cámara web: $e');
    }
  }

  void dispose() {
    if (_cameraStream != null) {
      for (final track in _cameraStream.getTracks()) {
        track.stop();
      }
      _cameraStream = null;
    }
  }

  Future<Uint8List?> captureFrame() async {
    final videos = html.document.querySelectorAll('video');
    html.VideoElement? videoEl;
    for (final el in videos) {
      if (el is html.VideoElement && el.srcObject != null) {
        videoEl = el;
        break;
      }
    }
    if (videoEl == null) return null;

    final w = videoEl.videoWidth > 0 ? videoEl.videoWidth : 640;
    final h = videoEl.videoHeight > 0 ? videoEl.videoHeight : 480;
    final canvas = html.CanvasElement()
      ..width = w.toInt()
      ..height = h.toInt();
    final ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D;
    ctx.translate(w.toDouble(), 0);
    ctx.scale(-1, 1);
    ctx.drawImage(videoEl, 0, 0);

    final blob = await canvas.toBlob('image/jpeg', 0.85);
    final reader = html.FileReader()..readAsArrayBuffer(blob);
    await reader.onLoad.first;
    return reader.result as Uint8List?;
  }
}
