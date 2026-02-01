import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MovimentacoesPage extends StatefulWidget {
  const MovimentacoesPage({super.key});

  @override
  State<MovimentacoesPage> createState() => _MovimentacoesPageState();
}


class _MovimentacoesPageState extends State<MovimentacoesPage> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _conexoes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Inicia a sincronização que já busca os dados ao final
    _sincronizarEBuscar();
  }

  Future<void> _sincronizarEBuscar() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase.functions.invoke(
        'sync-user-connections',
        body: {'clientUserId': user.id},
      );

      print("DEBUG PLUGGY: ${response.data}");

      // 🛡️ VERIFICAÇÃO DE SEGURANÇA:
      // Verifica se o dado é realmente uma lista antes de tentar usar
      final dynamic data = response.data;
      List cloudItems = [];

      if (data is List) {
        cloudItems = data;
      } else {
        debugPrint("Aviso: A API não retornou uma lista. Recebido: $data");
      }

      if (cloudItems.isNotEmpty) {
        for (var item in cloudItems) {
          await _supabase.from('user_connections').upsert({
            'user_id': user.id,
            'item_id': item['id'],
            'institution_name': item['connector']['name'],
          }, onConflict: 'item_id');
        }
      }
    } catch (e) {
      debugPrint("Erro na sincronização: $e");
    } finally {
      // Busca o que temos no banco (mesmo que o sync tenha falhado)
      await _buscarConexoes();
    }
  }
  Future<void> _buscarConexoes() async {
    try {
      final data = await _supabase.from('user_connections')
          .select('*')
          .order('institution_name'); // Organiza por nome

      if (mounted) {
        setState(() {
          _conexoes = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar conexões: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Movimentações por Instituição"),
        backgroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _conexoes.length,
        itemBuilder: (context, index) {
          final item = _conexoes[index];
          return _buildInstituicaoCard(item['institution_name'], item['item_id']);
        },
      ),
    );
  }

  Widget _buildInstituicaoCard(String nome, String itemId) {
    return Card(
      color: const Color(0xFF1A1A1A),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.account_balance, color: Colors.white),
        ),
        title: Text(nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: const Text("Toque para ver o extrato", style: TextStyle(color: Colors.white60)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
        onTap: () => _abrirModalTransacoes(nome, itemId),
      ),
    );
  }

  // MODAL TRANSLÚCIDO (GLASSMORPHISM)
  void _abrirModalTransacoes(String nome, String itemId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), // Efeito Translúcido
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withOpacity(0.8), // Fundo transparente
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: _ListaTransacoesWidget(itemId: itemId, nome: nome),
        ),
      ),
    );
  }
}

class _ListaTransacoesWidget extends StatelessWidget {
  final String itemId;
  final String nome;

  const _ListaTransacoesWidget({required this.itemId, required this.nome});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text("Extrato: $nome", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: FutureBuilder(
            future: Supabase.instance.client.functions.invoke('get-transactions', body: {'itemId': itemId}),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              final results = snapshot.data?.data['results'] ?? [];

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final t = results[index];
                  final valor = t['amount'] ?? 0.0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t['description'] ?? 'Sem descrição', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Text(t['date'].toString().split('T')[0], style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: Text(
                      "R\$ $valor",
                      style: TextStyle(color: valor < 0 ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}