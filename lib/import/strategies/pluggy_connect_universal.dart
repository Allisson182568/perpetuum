import 'dart:async';
import 'dart:convert'; // Adicionado para garantir decodificação se necessário
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'dart:ui_web' as ui;
import 'dart:html' as html;

class PluggyConnectUniversal extends StatefulWidget {
  final String token;
  final bool withSandbox;

  const PluggyConnectUniversal({
    required this.token,
    this.withSandbox = false,
    Key? key
  }) : super(key: key);

  @override
  State<PluggyConnectUniversal> createState() => _PluggyConnectUniversalState();
}

class _PluggyConnectUniversalState extends State<PluggyConnectUniversal> {
  late final WebViewController? _mobileController;
  final String _viewId = 'pluggy-iframe';

  @override
  void initState() {
    super.initState();
    final url = 'https://connect.pluggy.ai/?connect_token=${widget.token}&with_sandbox=${widget.withSandbox}';

    if (kIsWeb) {
      // --- LÓGICA WEB ---
      ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        final iframe = html.IFrameElement()
          ..src = url
          ..style.border = 'none'
          ..width = '100%'
          ..height = '100%';

        html.window.onMessage.listen((event) {
          // Garante que é um dado válido
          var data = event.data;

          // Se vier como string JSON, converte para Map
          if (data is String) {
            try {
              data = jsonDecode(data);
            } catch (e) {
              return; // Ignora se não for JSON
            }
          }

          if (data is Map && data['type'] == 'connect_success') {
            final item = data['item'];
            if (item != null && item['id'] != null) {
              final itemId = item['id'];
              Navigator.pop(context, itemId);
            }
          }
        });

        return iframe;
      });
      _mobileController = null;
    } else {
      // --- LÓGICA MOBILE ---
      _mobileController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onUrlChange: (UrlChange change) {
              final newUrl = change.url;
              if (newUrl != null) {
                _checkMobileUrl(newUrl);
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(url));
    }
  }

  void _checkMobileUrl(String url) {
    final uri = Uri.parse(url);
    final itemId = uri.queryParameters['item_id'];
    if (itemId != null) {
      Navigator.pop(context, itemId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return HtmlElementView(viewType: _viewId);
    } else {
      return WebViewWidget(controller: _mobileController!);
    }
  }
}