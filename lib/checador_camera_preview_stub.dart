import 'package:flutter/material.dart';

class NativeCameraPreview extends StatelessWidget {
  final dynamic controller;

  const NativeCameraPreview({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(child: Text('Cámara no disponible')),
    );
  }
}
