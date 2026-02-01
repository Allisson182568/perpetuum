import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// 🔴 IMPORTANTE: Adicione a importação correta do arquivo que criamos
import 'package:perpetuum/import/strategies/pluggy_connect_universal.dart';

class PluggyService {
  final _supabase = Supabase.instance.client;

  Future<void> handleB3Connection(BuildContext context) async {
    try {
      _showLoading(context);

      final user = _supabase.auth.currentUser;
      if (user == null) throw "Usuário não logado";

      // 1. Chama sua função no Supabase para pegar o token
      final response = await _supabase.functions.invoke(
        'connect-b3',
        body: {'clientUserId': user.id},
      );

      // Fecha o loading
      if (Navigator.canPop(context)) Navigator.pop(context);

      final token = response.data['accessToken'];
      if (token == null) throw "Token vazio";

      // 2. EM VEZ DE abrir link externo, abre o nosso Widget Universal
      // Isso mantém o usuário dentro do perpetuum.grupodantass.com.br
      final String? itemId = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PluggyConnectUniversal(
            token: token,
            withSandbox: true, // Deixe true para testar com dados fakes
          ),
        ),
      );

      // 3. Se o itemId voltou, a conexão foi concluída com sucesso!
      if (itemId != null) {
        _handleConnectionSuccess(context, itemId);
      }

    } catch (e) {
      // Garante que o loading feche em caso de erro
      if (Navigator.canPop(context)) Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro: $e")),
      );
    }
  }

  // Função para lidar com o sucesso (substituindo o antigo _updateDashboard)
  void _handleConnectionSuccess(BuildContext context, String itemId) {
    debugPrint("B3 Conectada com sucesso! Item ID: $itemId");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Conta B3 conectada com sucesso!")),
    );
    // Aqui você pode disparar uma atualização de tela ou recarregar os dados
  }

  void _showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }
}