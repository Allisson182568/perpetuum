import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Importações condicionais para evitar erros de compilação entre plataformas
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
  bool _launchedInNewTab = false;

  @override
  void initState() {
    super.initState();
    final url = 'https://connect.pluggy.ai/?connect_token=${widget.token}&with_sandbox=${widget.withSandbox}';

    if (kIsWeb) {
      // --- LÓGICA WEB: NOVA ABA ---
      _openInNewTab(url);

      // Escuta quando o usuário volta para a aba do App
      html.window.onFocus.listen((_) {
        if (_launchedInNewTab && mounted) {
          // Quando ele volta, fechamos esta tela de "redirecionamento"
          // e avisamos a Home para sincronizar os dados.
          Navigator.pop(context, 'check_sync');
        }
      });
    } else {
      // --- LÓGICA MOBILE: WEBVIEW ---
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

  Future<void> _openInNewTab(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        webOnlyWindowName: '_blank', // Abre em nova aba
      );
      setState(() => _launchedInNewTab = true);
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
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.cyanAccent),
              const SizedBox(height: 24),
              const Text(
                "Conectando com a Pluggy...",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Conclua a conexão na aba que se abriu.",
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                onPressed: () => Navigator.pop(context),
                child: const Text("Voltar para o App", style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      );
    } else {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
        body: WebViewWidget(controller: _mobileController!),
      );
    }
  }
}