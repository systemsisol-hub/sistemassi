import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';

class WebIframe extends StatefulWidget {
  final String url;
  final double height;
  final double width;

  const WebIframe({super.key, required this.url, required this.height, required this.width});

  @override
  State<WebIframe> createState() => _WebIframeState();
}

class _WebIframeState extends State<WebIframe> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'bi-iframe-${DateTime.now().millisecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      return web.HTMLIFrameElement()
        ..src = widget.url
        ..allow = 'fullscreen'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: widget.width,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
