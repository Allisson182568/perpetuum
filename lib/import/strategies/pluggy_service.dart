import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PluggyService {
  final _supabase = Supabase.instance.client;

  Future<void> handleB3Connection(BuildContext context) async {
    try {
      _showLoading(context);

      final user = _supabase.auth.currentUser;
      if (user == null) throw "Usuário não logado";

      final response = await _supabase.functions.invoke(
        'connect-b3',
        body: {
          'clientUserId': user.id,
        },
      );

      Navigator.pop(context);

      debugPrint("FUNCTION RESPONSE: ${response.data}");
      debugPrint("STATUS: ${response.status}");

      final token = response.data['accessToken'];

      if (token == null) throw "Token vazio";

      // 🔴 IMPORTANTE: NÃO use Uri.https
      final url =
          "https://connect.pluggy.ai/?connectorId=2&accessToken=$token&clientUserId=${user.id}";
      debugPrint("TOKEN SIZE: ${token.length}");
      debugPrint("URL FINAL: $url");

      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro: $e")),
      );
    }
  }

  void _showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }
}