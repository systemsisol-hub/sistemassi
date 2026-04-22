import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class NativeCameraPreview extends StatelessWidget {
  final CameraController? controller;

  const NativeCameraPreview({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateZ(-3.14159 / 2),
      child: Transform.scale(
        scaleX: -1,
        child: CameraPreview(controller!),
      ),
    );
  }
}
