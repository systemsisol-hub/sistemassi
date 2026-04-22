import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

class WebIframeWidget extends StatefulWidget {
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
  State<WebIframeWidget> createState() => _WebIframeWidgetState();
}

class _WebIframeWidgetState extends State<WebIframeWidget> {
  late String _viewType;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'iframe-${DateTime.now().millisecondsSinceEpoch}';
    _registerViewFactory();
  }

  void _registerViewFactory() {
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = widget.url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'fullscreen';

      _isInitialized = true;
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: widget.width,
      child: HtmlElementView(
        viewType: _viewType,
      ),
    );
  }
}
