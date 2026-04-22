import 'dart:typed_data';
import 'package:camera/camera.dart' as cam;

class NativeCameraController {
  cam.CameraController? _controller;
  List<cam.CameraDescription>? _cameras;
  bool _isInitialized = false;
  int _currentCameraIndex = 0;

  bool get isReady => _isInitialized;
  cam.CameraController? get controller => _controller;
  String get viewId => 'native-camera-preview';

  Future<void> initCamera() async {
    try {
      _cameras = await cam.availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        return;
      }

      final frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == cam.CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _currentCameraIndex = _cameras!.indexOf(frontCamera);

      _controller = cam.CameraController(
        frontCamera,
        cam.ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  Future<void> switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;

    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras!.length;
    await _controller?.dispose();

    _controller = cam.CameraController(
      _cameras![_currentCameraIndex],
      cam.ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }

  Future<Uint8List?> captureFrame() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return null;
    }

    try {
      final cam.XFile file = await _controller!.takePicture();
      return await file.readAsBytes();
    } catch (e) {
      return null;
    }
  }
}
