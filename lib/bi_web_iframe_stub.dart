import 'package:flutter/material.dart';

class WebIframe extends StatelessWidget {
  final String url;
  final double height;
  final double width;

  const WebIframe({super.key, required this.url, required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('El visor de reportes solo está disponible en la versión Web.'),
    );
  }
}
