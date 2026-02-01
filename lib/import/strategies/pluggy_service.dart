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
            withSandbox: false, // Deixe true para testar com dados fakes
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
// ... resto do código anterior ...

  Future<void> _handleConnectionSuccess(BuildContext context, String itemId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // 1. Salva o ID da conexão no Supabase para não perder
      await _supabase.from('user_connections').insert({
        'user_id': user.id,
        'item_id': itemId,
        'institution_name': 'MeuPluggy/B3',
      });

      debugPrint("Conexão Salva no Banco! ID: $itemId");

      // Segurança: Verifica se a tela ainda existe antes de mostrar o SnackBar
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("B3 conectada e salva com sucesso!")),
      );

      // 2. AGORA SIM: Chama a função para buscar os investimentos
      await _fetchInvestments(itemId);

    } catch (e) {
      debugPrint("Erro ao salvar conexão: $e");

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao salvar: $e")),
        );
      }
    }
  }
  // Função que busca os dados REAIS da B3
  Future<void> _fetchInvestments(String itemId) async {
    try {
      debugPrint("Buscando investimentos na Pluggy...");

      final response = await _supabase.functions.invoke(
        'get-investments',
        body: {'itemId': itemId},
      );

      final data = response.data;

      // Aqui vemos se veio alguma coisa!
      debugPrint("DADOS RECEBIDOS: $data");

      if (data != null && data['results'] != null) {
        final List investments = data['results'];
        debugPrint("Você tem ${investments.length} ativos nesta conta!");

        // Exemplo: Mostrar o primeiro ativo encontrado
        if (investments.isNotEmpty) {
          final primeiroAtivo = investments[0];
          debugPrint("Ativo: ${primeiroAtivo['name']} | Saldo: ${primeiroAtivo['balance']}");
        }
      }

    } catch (e) {
      debugPrint("Erro ao buscar investimentos: $e");
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