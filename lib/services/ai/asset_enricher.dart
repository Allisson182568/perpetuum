import 'package:supabase_flutter/supabase_flutter.dart';

class AssetEnricher {
  static final _supabase = Supabase.instance.client;

  /// Enriquece o ativo buscando no banco mestre ou usando heurísticas de IA.
  static Future<Map<String, dynamic>> enrich(String ticker, String assetType) async {
    // Limpeza para busca: Remove o 'F' do fracionário brasileiro
    String cleanTicker = ticker.toUpperCase().trim();
    if (cleanTicker.endsWith('F') && !cleanTicker.startsWith('F')) {
      if (RegExp(r'\dF$').hasMatch(cleanTicker)) {
        cleanTicker = cleanTicker.substring(0, cleanTicker.length - 1);
      }
    }

    try {
      final response = await _supabase
          .from('ticker_info')
          .select()
          .eq('ticker', cleanTicker)
          .maybeSingle();

      if (response != null) {
        return {
          'cnpj': response['cnpj'] ?? '',
          'sector': response['sector'] ?? 'Outros',
          'sub_sector': response['sub_sector'] ?? 'Geral',
          'country': assetType == 'STOCK_US' || assetType == 'REIT' || cleanTicker.length <= 5 ? 'US' : 'BR',
          'currency': assetType == 'STOCK_US' || assetType == 'REIT' || cleanTicker.length <= 5 ? 'USD' : 'BRL',
        };
      }
    } catch (e) {
      print("Erro ao consultar ticker_info: $e");
    }

    // Fallback: Se não achar no banco, usa lógica de dedução pública
    return {
      'cnpj': '',
      'sector': deduceSector(ticker, assetType),
      'sub_sector': 'Geral',
      'country': assetType == 'STOCK_US' || assetType == 'REIT' ? 'US' : 'BR',
      'currency': assetType == 'STOCK_US' || assetType == 'REIT' ? 'USD' : 'BRL',
    };
  }

  /// Heurística pública para visualização instantânea no ImportScreen.
  static String deduceSector(String ticker, String type) {
    final t = ticker.toUpperCase();

    // Prioridade por Classe
    if (type == 'CRYPTO') return 'Tecnologia (Blockchain)';
    if (type == 'FIXED_INCOME') return 'Governo / Bancário';
    if (type == 'ETF') return 'Índice de Mercado';
    if (type == 'FII' || type == 'REIT') return 'Imobiliário';

    // Heurística para Stocks US (S&P 500 top tickers)
    if (type == 'STOCK_US') {
      if (['AAPL', 'MSFT', 'NVDA', 'GOOGL', 'META'].contains(t)) return 'Tecnologia';
      if (['KO', 'PEP', 'PG', 'WMT'].contains(t)) return 'Consumo Defensivo';
      if (['AMZN', 'TSLA', 'MCD'].contains(t)) return 'Consumo Cíclico';
      return 'Mercado Global';
    }

    // Heurística Setorial Brasileira (Prefixos)
    if (t.startsWith('ITUB') || t.startsWith('BBDC') || t.startsWith('SANB') || t.startsWith('BBAS')) {
      return 'Financeiro (Bancos)';
    }
    if (t.startsWith('BBSE') || t.startsWith('PSSA') || t.startsWith('CXSE') || t.startsWith('IRBR')) {
      return 'Financeiro (Seguros)';
    }
    if (t.startsWith('ELET') || t.startsWith('CPLE') || t.startsWith('CMIG') || t.startsWith('EGIE') || t.startsWith('TAEE')) {
      return 'Utilidade Pública (Energia)';
    }
    if (t.startsWith('PETR') || t.startsWith('PRIO') || t.startsWith('RECV')) {
      return 'Petróleo e Gás';
    }
    if (t.startsWith('VALE') || t.startsWith('GGBR') || t.startsWith('CSNA')) {
      return 'Materiais Básicos';
    }
    if (t.startsWith('ABEV') || t.startsWith('MDIA')) return 'Consumo não Cíclico';
    if (t.startsWith('MGLU') || t.startsWith('LREN')) return 'Consumo Cíclico';

    return 'Outros';
  }
}