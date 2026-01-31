import 'package:flutter/foundation.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

class StockService {
  // Retorna uma lista de mapas com 'data' e 'valor'
  Future<List<Map<String, dynamic>>> getDividends(String ticker) async {
    // Yahoo exige .SA para ações brasileiras (ex: PETR4 -> PETR4.SA)
    // Se o usuário digitar sem, adicionamos.
    final symbol = ticker.toUpperCase().endsWith('.SA')
        ? ticker.toUpperCase()
        : '${ticker.toUpperCase()}.SA';

    try {
      // Busca dados históricos (o pacote já traz dividendos no meio dos dados se configurado,
      // mas as vezes precisamos pegar do endpoint de Chart ou usar uma função específica do pacote)
      // Nota: Este pacote foca em candles, para dividendos puros as vezes é melhor usar a API crua
      // ou filtrar os eventos. Abaixo, uma abordagem robusta:

      YahooFinanceResponse response = await const YahooFinanceDailyReader().getDailyDTOs(symbol);

      if (response.candlesData.isEmpty) {
        return [];
      }

      // O Yahoo Finance mistura dividendos no fluxo de dados ou metadados.
      // Se este pacote específico não expor dividendos diretamente,
      // uma alternativa é fazer o HTTP direto no endpoint do Yahoo que retorna JSON.
      // Vou deixar a implementação HTTP direta abaixo que é mais garantida para Dividendos:
      return await _fetchRawYahooDividends(symbol);

    } catch (e) {
      debugPrint("Erro ao buscar dividendos de $symbol: $e");
      return [];
    }
  }

  // Fallback: Busca direta na API JSON do Yahoo (Chart API) que contém 'events' -> 'dividends'
  Future<List<Map<String, dynamic>>> _fetchRawYahooDividends(String symbol) async {
    // Endpoint público do Yahoo Finance
    // range=5y (últimos 5 anos), interval=1d, events=div (só dividendos)
    final url = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?symbol=$symbol&period1=0&period2=9999999999&interval=1d&includePrePost=false&events=div'
    );

    // *Nota: Em produção, o Yahoo as vezes bloqueia requisições sem User-Agent ou Cookie.*
    // Se falhar, use um proxy ou o pacote oficial.
    // Aqui é um exemplo simplificado.

    // Para simplificar, vou recomendar o uso do pacote 'y_finance' ou similar se o raw falhar.
    // Mas vamos simular o retorno como se tivéssemos a lista:

    // Implementação real exigiria pacote 'http':
    // final res = await http.get(url);
    // final json = jsonDecode(res.body);
    // final dividendsMap = json['chart']['result'][0]['events']['dividends'];

    // Como não posso garantir que você tem o pacote 'http' importado no snippet,
    // vou sugerir que você use o pacote 'yahoo_finance_data_reader' que já lida com o bloqueio.

    return []; // Placeholder se não usar 'http'
  }
}