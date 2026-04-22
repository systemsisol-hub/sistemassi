import 'package:flutter/material.dart';

class WebIframeWidget extends StatelessWidget {
  final String url;
  final double height;
  final double width;

  const WebIframeWidget({
    super.key,
    required this.url,
    required this.height,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      color: Colors.grey[200],
      child: Center(
        child: Text('Iframe no disponible en esta plataforma'),
      ),
    );
  }
}
