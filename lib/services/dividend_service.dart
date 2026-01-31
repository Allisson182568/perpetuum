import 'package:supabase_flutter/supabase_flutter.dart';

class DividendService {
  final _supabase = Supabase.instance.client;

  /// Busca os proventos do banco e separa entre Histórico e Futuro
  Future<Map<String, List<Map<String, dynamic>>>> getUserDividends() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return {'past': [], 'future': []};
    }

    try {
      // Busca todos os proventos do usuário ordenados por data
      final response = await _supabase
          .from('earnings')
          .select()
          .eq('user_id', userId)
          .order('date', ascending: false);

      final List<dynamic> data = response;
      final now = DateTime.now();

      // Normaliza a data de hoje para comparar apenas dia/mês/ano (ignora hora)
      final today = DateTime(now.year, now.month, now.day);

      List<Map<String, dynamic>> past = [];
      List<Map<String, dynamic>> future = [];

      for (var item in data) {
        // Converte a data do banco (String) para DateTime
        final dateStr = item['date'] as String;
        final date = DateTime.parse(dateStr);

        // Mapeia os dados do banco para o formato que a tela espera
        final mappedItem = {
          'id': item['id'],
          'ticker': item['ticker'] ?? 'S/T',
          'type': item['type'] ?? 'DIVIDENDO',
          'date': date, // Importante: Passa como DateTime
          'total_value': (item['total_value'] as num?)?.toDouble() ?? 0.0,
          'value_per_share': (item['unit_value'] as num?)?.toDouble() ?? 0.0,
        };

        // Separação Lógica
        if (date.isBefore(today)) {
          past.add(mappedItem);
        } else {
          future.add(mappedItem);
        }
      }

      // Ordena futuro da data mais próxima para a mais distante
      future.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      return {
        'past': past,
        'future': future,
      };

    } catch (e) {
      print("Erro ao buscar dividendos: $e");
      return {'past': [], 'future': []};
    }
  }
}