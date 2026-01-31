import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../cloud_service.dart';
import 'package:intl/intl.dart';

class AiEngineService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final CloudService _cloud = CloudService();
  final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  // --- FERRAMENTAS AUXILIARES ---

  String _normalize(String text) {
    var withDia = 'ÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÝÑàáâãäåèéêëìíîïòóôõöùúûüýñ';
    var withoutDia = 'AAAAAAEEEEIIIIOOOOOUUUUYNaaaaaaeeeeiiiiooooouuuuyn';
    for (int i = 0; i < withDia.length; i++) {
      text = text.replaceAll(withDia[i], withoutDia[i]);
    }
    return text.toLowerCase().replaceAll(RegExp(r'[?|!|.|,]'), '').trim();
  }

  // Extrai valor monetário da frase (ex: "investir 1000" -> 1000.0)
  double? _extractAmount(String text) {
    // Remove tudo que não é número, ponto ou vírgula
    String numbers = text.replaceAll(RegExp(r'[^0-9.,]'), '');
    // Troca vírgula por ponto para parse
    numbers = numbers.replaceAll(',', '.');
    // Pega o último número encontrado na string (assumindo que seja o valor)
    try {
      final regex = RegExp(r'(\d+(\.\d+)?)');
      final matches = regex.allMatches(numbers);
      if (matches.isNotEmpty) {
        String candidate = matches.last.group(0)!;
        return double.tryParse(candidate);
      }
    } catch (_) {}
    return null;
  }

  // --- MOTOR DE ENTENDIMENTO ---

  Future<Map<String, dynamic>> processQuery(String rawQuery) async {
    try {
      final query = _normalize(rawQuery);

      // 0. Atalho para Simulação de Aporte (Prioridade)
      if ((query.contains('investir') || query.contains('comprar') || query.contains('aporte') || query.contains('coloco')) &&
          _extractAmount(query) != null) {
        return await _executeIntentHandler('SIMULACAO_APORTE', rawQuery);
      }

      final queryWords = query.split(' ');

      // 1. Busca a Base de Conhecimento
      final List<dynamic> kb = await _supabase.from('ai_knowledge_base').select();

      String? detectedIntent;
      int maxScore = 0;

      for (var entry in kb) {
        final keywords = List<String>.from(entry['keywords']);
        int currentScore = 0;

        for (var word in keywords) {
          String normalizedK = _normalize(word);
          if (queryWords.any((qW) => qW == normalizedK || qW.contains(normalizedK))) {
            currentScore += 3;
          }
        }
        if (currentScore > maxScore) {
          maxScore = currentScore;
          detectedIntent = entry['intent'];
        }
      }

      // 2. Fallback e Aprendizado
      if (detectedIntent == null || maxScore < 3) {
        _reportUnanswered(rawQuery).catchError((e) => debugPrint("Erro log: $e"));
        return {
          "type": "text",
          "content": "Ainda não mapeei o termo '${rawQuery.split(' ').last}'. Mas já enviei para minha base de estudos!"
        };
      }

      return await _executeIntentHandler(detectedIntent, query);
    } catch (e) {
      debugPrint("Erro IA: $e");
      return {"type": "text", "content": "Tive um problema ao processar sua dúvida. Pode repetir?"};
    }
  }

  Future<void> _reportUnanswered(String query) async {
    try {
      await _supabase.rpc('increment_unanswered_query', params: {'q_text': query});
    } catch (e) {
      debugPrint("Erro ao reportar: $e");
    }
  }

  // --- EXECUTOR DE LÓGICA ---

  Future<Map<String, dynamic>> _executeIntentHandler(String intent, String query) async {
    final portfolio = await _cloud.getConsolidatedPortfolio();
    final List<Map<String, dynamic>> assets = List<Map<String, dynamic>>.from(portfolio['assets']);

    switch (intent) {
      case 'RESUMO_GERAL':
        return {
          "type": "summary",
          "content": "Sua Fortaleza totaliza ${f.format(portfolio['total'])}. Você possui ${assets.length} ativos na carteira."
        };

    // --- SIMULAÇÃO COM VALOR (A pergunta de 1000 reais) ---
      case 'SIMULACAO_APORTE':
        final user = _supabase.auth.currentUser;
        if (user == null) return {"type": "text", "content": "Faça login para simular investimentos."};

        double amountToInvest = _extractAmount(query) ?? 0.0;
        if (amountToInvest <= 0) {
          return {"type": "text", "content": "Entendi que você quer investir, mas não identifiquei o valor. Tente 'Investir 1000 reais'."};
        }

        final targetsResponse = await _supabase.from('asset_targets').select().eq('user_id', user.id);

        // Mapa: Ticker -> Meta % (FILTRANDO CLASSES VIRTUAIS)
        final Map<String, double> targetMap = {};
        for (var t in targetsResponse) {
          String key = t['ticker'].toString().toUpperCase();
          // Importante: Ignora metas que começam com CLASS_ para não recomendar comprar "CLASS_ACAO"
          if (!key.startsWith('CLASS_')) {
            targetMap[key] = (t['target_percent'] as num).toDouble();
          }
        }

        if (targetMap.isEmpty) {
          return {"type": "text", "content": "Para eu sugerir onde investir seus ${f.format(amountToInvest)}, primeiro defina suas metas na tela de Alocação."};
        }

        List<Map<String, dynamic>> opportunities = [];
        double totalPortfolio = portfolio['total'];

        for (var asset in assets) {
          String ticker = asset['ticker'].toString().toUpperCase();

          if (asset['type'] == 'ACAO' && ticker.endsWith('F') && ticker.length > 4) {
            ticker = ticker.substring(0, ticker.length - 1);
          }

          double currentVal = (asset['value'] as num).toDouble();
          double currentPct = totalPortfolio > 0 ? (currentVal / totalPortfolio) * 100 : 0.0;
          double targetPct = targetMap[ticker] ?? 0.0;

          double gap = targetPct - currentPct;

          if (gap > 0) {
            opportunities.add({
              'ticker': ticker,
              'gap': gap,
              'price': (asset['current_price'] ?? asset['purchase_price'] ?? 0).toDouble(),
            });
          }
        }

        opportunities.sort((a, b) => (b['gap'] as num).compareTo(a['gap'] as num));

        if (opportunities.isEmpty) {
          return {"type": "text", "content": "Sua carteira está perfeitamente balanceada! Pode investir livremente."};
        }

        var topPick = opportunities.first;
        String pickTicker = topPick['ticker'];
        double pickPrice = topPick['price'];
        double pickGap = topPick['gap'];

        int possibleQty = (pickPrice > 0) ? (amountToInvest / pickPrice).floor() : 0;

        String responseText = "Com base no aporte de **${f.format(amountToInvest)}**, o modelo matemático indica prioridade para **$pickTicker**.\n\n";

        if (possibleQty > 0) {
          responseText += "💰 Você consegue comprar aprox. **$possibleQty unidades** (Cotação ref: ${f.format(pickPrice)}).\n\n";
        }

        responseText += "📊 **Análise Técnica:** Este ativo está **${pickGap.toStringAsFixed(2)}% abaixo** da meta definida.\n\n";
        responseText += "⚠️ **Aviso Legal:** Esta sugestão é baseada estritamente no modelo matemático de rebalanceamento das suas metas. Não é recomendação de compra/venda.";

        return {
          "type": "text",
          "content": responseText
        };

    // --- REBALANCEAMENTO PASSIVO (Sem valor) ---
      case 'REBALANCEAMENTO':
        final user = _supabase.auth.currentUser;
        if (user == null) return {"type": "text", "content": "Faça login para ver recomendações."};

        final userId = user.id;
        final targets = await _supabase.from('asset_targets').select().eq('user_id', userId);

        // Mapa: Ticker -> Meta % (FILTRANDO CLASSES VIRTUAIS)
        final Map<String, double> targetMap = {};
        for (var t in targets) {
          String key = t['ticker'].toString().toUpperCase();
          if (!key.startsWith('CLASS_')) {
            targetMap[key] = (t['target_percent'] as num).toDouble();
          }
        }

        List<Map<String, dynamic>> recommendations = [];
        double totalP = portfolio['total'];

        for (var asset in assets) {
          String ticker = asset['ticker'].toString().toUpperCase();
          double currentVal = (asset['value'] as num).toDouble();
          double currentWeight = (currentVal / totalP) * 100;
          double targetWeight = targetMap[ticker] ?? 0.0;

          if (targetWeight > currentWeight) {
            recommendations.add({
              'ticker': ticker,
              'gap': targetWeight - currentWeight,
              'needed': (targetWeight / 100 * totalP) - currentVal
            });
          }
        }

        recommendations.sort((a, b) => (b['gap'] as num).compareTo(a['gap'] as num));

        if (recommendations.isEmpty) {
          return {"type": "text", "content": "Sua carteira está equilibrada!"};
        }

        final top = recommendations.first;
        return {
          "type": "insight",
          "content": "Sugerimos focar em ${top['ticker']}. Ele está ${top['gap'].toStringAsFixed(1)}% abaixo da sua meta. Aporte sugerido para zerar o gap: ${f.format(top['needed'])}.",
          "chartData": recommendations.take(4).map((e) => {
            "label": e['ticker'],
            "value": e['gap'],
          }).toList(),
        };

      case 'DIVIDENDOS':
        try {
          final user = _supabase.auth.currentUser;
          if (user == null) return {"type": "text", "content": "Você precisa estar logado."};

          final response = await _supabase
              .from('earnings')
              .select('total_value, date')
              .eq('user_id', user.id);

          final List<dynamic> data = response as List;
          double totalAcumulado = 0.0;
          double totalHoje = 0.0;
          double totalMes = 0.0;
          double totalAno = 0.0;

          final agora = DateTime.now();
          final hojeStr = DateFormat('yyyy-MM-dd').format(agora);
          final inicioMes = DateTime(agora.year, agora.month, 1);
          final inicioAno = DateTime(agora.year, 1, 1);

          for (var item in data) {
            double valor = (item['total_value'] as num).toDouble();
            DateTime dataPgto = DateTime.parse(item['date'].toString());

            totalAcumulado += valor;

            if (item['date'].toString().contains(hojeStr)) totalHoje += valor;
            if (dataPgto.isAfter(inicioMes.subtract(const Duration(seconds: 1)))) totalMes += valor;
            if (dataPgto.isAfter(inicioAno.subtract(const Duration(seconds: 1)))) totalAno += valor;
          }

          if (query.contains('hoje') || query.contains('agora')) {
            String msg = totalHoje > 0 ? "Hoje você recebeu ${f.format(totalHoje)}!" : "Para hoje não constam recebimentos.";
            return {"type": "summary", "content": "$msg Total acumulado: ${f.format(totalAcumulado)}."};
          }
          if (query.contains('mes') || query.contains('mensal')) {
            return {"type": "summary", "content": "Neste mês: ${f.format(totalMes)}. Total histórico: ${f.format(totalAcumulado)}."};
          }
          if (query.contains('ano') || query.contains('anual')) {
            return {"type": "summary", "content": "No ano: ${f.format(totalAno)}. Total histórico: ${f.format(totalAcumulado)}."};
          }

          return {"type": "summary", "content": "Total acumulado em dividendos: ${f.format(totalAcumulado)}."};
        } catch (e) {
          return {"type": "text", "content": "Erro ao calcular dividendos: $e"};
        }

      case 'DESEMPENHO_ATIVOS':
        if (assets.isEmpty) return {"type": "text", "content": "Sua carteira está vazia."};
        assets.sort((a, b) => (b['value'] as num).compareTo(a['value'] as num));
        final top = assets.first;
        return {
          "type": "insight",
          "content": "Sua maior posição é ${top['ticker'] ?? top['name']}, com valor atual de ${f.format(top['value'])}."
        };

      default:
        return {"type": "text", "content": "Entendido! No entanto, ainda estou calibrando os detalhes desta resposta."};
    }
  }
}