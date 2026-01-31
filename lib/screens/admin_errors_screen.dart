import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminErrorsScreen extends StatefulWidget {
  const AdminErrorsScreen({Key? key}) : super(key: key);

  @override
  State<AdminErrorsScreen> createState() => _AdminErrorsScreenState();
}

class _AdminErrorsScreenState extends State<AdminErrorsScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _tickerErrors = [];
  List<Map<String, dynamic>> _aiQueries = [];
  List<Map<String, dynamic>> _availableIntents = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchTickerErrors(),
      _fetchAiQueries(),
      _fetchIntents(),
    ]);
    setState(() => _isLoading = false);
  }

  // --- BUSCA DE DADOS ---

  Future<void> _fetchTickerErrors() async {
    try {
      final response = await _supabase.rpc('get_missing_tickers_report');
      setState(() {
        _tickerErrors = List<Map<String, dynamic>>.from(response as List);
      });
    } catch (e) {
      debugPrint('Erro Yahoo: $e');
    }
  }

  Future<void> _fetchAiQueries() async {
    try {
      final response = await _supabase
          .from('ai_unanswered_queries')
          .select()
          .order('frequency', ascending: false);
      setState(() {
        _aiQueries = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Erro IA: $e');
    }
  }

  Future<void> _fetchIntents() async {
    try {
      final response = await _supabase.from('ai_knowledge_base').select('intent, description');
      setState(() {
        _availableIntents = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Erro ao buscar intenções: $e');
    }
  }

  // --- LÓGICA DE RESOLUÇÃO AUTOMÁTICA (TREINAMENTO DIRETO) ---

  Future<void> _trainAiDirectly(String query, String intent) async {
    try {
      // Extração automática da keyword (ex: 'cacau')
      final words = query.toLowerCase().split(' ');
      String keyword = words.length > 2 ? words[words.length - 2] : words.last;
      keyword = keyword.replaceAll(RegExp(r'[?|!|.|,]'), '').trim();

      // Chama a função RPC que criamos no Passo 1
      await _supabase.rpc('train_ai_from_app', params: {
        'p_intent': intent,
        'p_keyword': keyword,
        'p_original_query': query,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('IA Treinada! "$keyword" agora faz parte de $intent.')),
      );

      _refreshAll(); // Recarrega as listas
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao treinar IA: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showAiIntentSelector(String query) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Mapear dúvida para qual categoria?",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 15),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableIntents.length,
                  itemBuilder: (context, index) {
                    final item = _availableIntents[index];
                    return ListTile(
                      leading: const Icon(Icons.psychology, color: Colors.cyanAccent),
                      title: Text(item['intent'], style: const TextStyle(color: Colors.white)),
                      subtitle: Text(item['description'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _trainAiDirectly(query, item['intent']);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- RESOLUÇÃO TICKERS ---

  Future<void> _resolveTickerAutomatically(String oldTicker, String newTicker) async {
    try {
      await _supabase.rpc('resolve_missing_ticker', params: {
        'p_old_ticker': oldTicker,
        'p_new_ticker': newTicker.toUpperCase(),
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sucesso! Ticker corrigido.')));
      _fetchTickerErrors();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  void _showTickerDialog(String oldTicker) {
    final controller = TextEditingController();
    if (oldTicker.endsWith('F')) controller.text = oldTicker.substring(0, oldTicker.length - 1);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text('Corrigir $oldTicker', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Novo Ticker', labelStyle: TextStyle(color: Colors.white60)),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () {
              _resolveTickerAutomatically(oldTicker, controller.text);
              Navigator.pop(context);
            },
            child: const Text('RESOLVER AGORA'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: const Text('Painel de Controle Admin'),
          backgroundColor: const Color(0xFF1E1E1E),
          bottom: const TabBar(
            indicatorColor: Colors.cyanAccent,
            tabs: [
              Tab(icon: Icon(Icons.show_chart), text: 'Erros Ticker'),
              Tab(icon: Icon(Icons.psychology), text: 'Dúvidas IA'),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshAll),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
          children: [
            _buildTickerTab(),
            _buildAiTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildTickerTab() {
    if (_tickerErrors.isEmpty) {
      return const Center(child: Text('Nenhum erro de ticker.', style: TextStyle(color: Colors.green)));
    }
    return ListView.builder(
      itemCount: _tickerErrors.length,
      itemBuilder: (context, index) {
        final item = _tickerErrors[index];
        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.red[900], child: Text('${item['error_count']}', style: const TextStyle(color: Colors.white))),
            title: Text(item['ticker'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('Visto em: ${DateFormat('dd/MM HH:mm').format(DateTime.parse(item['last_seen']))}', style: const TextStyle(color: Colors.white54)),
            trailing: IconButton(
              icon: const Icon(Icons.build, color: Colors.blueAccent),
              onPressed: () => _showTickerDialog(item['ticker']),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAiTab() {
    if (_aiQueries.isEmpty) {
      return const Center(child: Text('A IA entendeu tudo até agora!', style: TextStyle(color: Colors.green)));
    }
    return ListView.builder(
      itemCount: _aiQueries.length,
      itemBuilder: (context, index) {
        final item = _aiQueries[index];
        final query = item['query'];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF1E1E1E),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.purple[900],
              child: Text('${item['frequency']}', style: const TextStyle(color: Colors.white)),
            ),
            title: Text(query, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            subtitle: const Text('Dúvida não mapeada', style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent.withOpacity(0.1),
                foregroundColor: Colors.cyanAccent,
                side: const BorderSide(color: Colors.cyanAccent),
              ),
              icon: const Icon(Icons.bolt, size: 16),
              label: const Text('RESOLVER'),
              onPressed: () => _showAiIntentSelector(query),
            ),
          ),
        );
      },
    );
  }
}