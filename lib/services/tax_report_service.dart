import 'package:supabase_flutter/supabase_flutter.dart';

class TaxReportService {
  final _supabase = Supabase.instance.client;

  /// Gera o relatório. Se não tiver histórico, usa o saldo atual como estimativa.
  Future<List<Map<String, dynamic>>> generateAssetsReport(int year) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    // Data limite: 01/01 do ano seguinte (para garantir fuso horário)
    final safetyLimitDate = DateTime(year + 1, 1, 2);

    try {
      // 1. TENTA BUSCAR NO HISTÓRICO (O CORRETO)
      final txResponse = await _supabase
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .lt('date', safetyLimitDate.toIso8601String())
          .order('date', ascending: true);

      List<dynamic> transactions = txResponse as List<dynamic>;

      // 2. BUSCA METADADOS (Nomes, CNPJs)
      final metaResponse = await _supabase
          .from('assets')
          .select('ticker, name, cnpj, type, quantity, purchase_price, value')
          .eq('user_id', userId);

      Map<String, Map<String, dynamic>> metaMap = {};
      List<dynamic> assetsSnapshot = metaResponse as List<dynamic>;

      for (var m in assetsSnapshot) {
        metaMap[m['ticker']] = m;
      }

      // --- AQUI ESTÁ A CORREÇÃO "MODO DE SEGURANÇA" ---
      // Se não achou NENHUMA transação no histórico, mas tem ativos na carteira,
      // significa que o usuário importou com a versão antiga do app.
      // Vamos usar o Snapshot atual para não mostrar "Tudo Zerado".

      if (transactions.isEmpty && assetsSnapshot.isNotEmpty) {
        print("⚠️ Histórico vazio. Usando Snapshot Atual (Assets) como fallback.");
        return _convertSnapshotToReport(assetsSnapshot, year);
      }

      // Se tem histórico, processa bonitinho
      return _consolidatePositions(transactions, metaMap);

    } catch (e) {
      print("Erro TaxReportService: $e");
      return [];
    }
  }

  // Lógica Principal (Baseada em Transações)
  List<Map<String, dynamic>> _consolidatePositions(
      List<dynamic> transactions,
      Map<String, Map<String, dynamic>> metaMap
      ) {
    Map<String, Map<String, dynamic>> portfolio = {};

    for (var tx in transactions) {
      String ticker = (tx['ticker'] ?? '').toString().toUpperCase();
      if (ticker.length > 4 && ticker.endsWith('F') && RegExp(r'\d').hasMatch(ticker[ticker.length-2])) {
        ticker = ticker.substring(0, ticker.length - 1);
      }

      String opType = (tx['operation_type'] ?? 'C').toString().toUpperCase();
      double qty = (tx['quantity'] as num?)?.toDouble() ?? 0.0;
      double price = (tx['unit_price'] as num?)?.toDouble() ?? 0.0;
      double txTotalValue = (tx['total_value'] as num?)?.toDouble() ?? (qty * price);

      if (!portfolio.containsKey(ticker)) {
        var meta = metaMap[ticker] ?? {};
        portfolio[ticker] = {
          'ticker': ticker,
          'name': meta['name'] ?? ticker,
          'cnpj': meta['cnpj'] ?? '',
          'type': meta['type'] ?? tx['asset_type'] ?? 'OUTROS',
          'quantity': 0.0,
          'total_cost': 0.0,
          'broker': tx['broker'] ?? 'Diversas',
        };
      }

      var position = portfolio[ticker]!;

      if (opType == 'V' || opType == 'VENDA') {
        double currentQty = position['quantity'];
        double currentTotalCost = position['total_cost'];

        if (currentQty > 0) {
          double avgPrice = currentTotalCost / currentQty;
          double costSold = qty * avgPrice;
          position['quantity'] = currentQty - qty;
          position['total_cost'] = currentTotalCost - costSold;
        } else {
          position['quantity'] = currentQty - qty;
        }
      } else {
        position['quantity'] = (position['quantity'] as double) + qty;
        position['total_cost'] = (position['total_cost'] as double) + txTotalValue;
      }
    }

    return _finalizeReport(portfolio);
  }

  // Lógica de Emergência (Baseada no Saldo Atual)
  List<Map<String, dynamic>> _convertSnapshotToReport(List<dynamic> assets, int year) {
    Map<String, Map<String, dynamic>> portfolio = {};

    // Se o ano solicitado for o atual ou anterior, o snapshot é uma boa estimativa.
    // Se for 2020, vai estar errado, mas é melhor que zero.

    for (var asset in assets) {
      String ticker = asset['ticker'];
      double qty = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
      double value = (asset['value'] as num?)?.toDouble() ?? 0.0; // Valor de mercado ou custo?

      // No snapshot, geralmente guardamos 'purchase_price' (PM).
      double pm = (asset['purchase_price'] as num?)?.toDouble() ?? 0.0;
      double totalCost = qty * pm;

      // Se o totalCost for 0 mas tiver value, usa value (caso de físicos)
      if (totalCost == 0 && value > 0) totalCost = value;

      if (qty > 0.001) {
        portfolio[ticker] = {
          'ticker': ticker,
          'name': asset['name'],
          'cnpj': asset['cnpj'],
          'type': asset['type'],
          'quantity': qty,
          'total_cost': totalCost,
          'safe_qty': qty,
          'safe_pm': pm,
          'broker': 'Carteira Atual'
        };
      }
    }

    return portfolio.values.toList()
      ..sort((a, b) => (b['total_cost'] as num).compareTo(a['total_cost'] as num));
  }

  // Helper final de formatação
  List<Map<String, dynamic>> _finalizeReport(Map<String, Map<String, dynamic>> portfolio) {
    List<Map<String, dynamic>> report = [];
    portfolio.forEach((key, val) {
      double qty = val['quantity'];
      if (qty > 0.001) {
        double total = val['total_cost'];
        double pm = qty > 0 ? total / qty : 0.0;

        val['safe_qty'] = qty;
        val['safe_pm'] = pm;
        val['total_cost'] = total;
        report.add(val);
      }
    });
    report.sort((a, b) => (b['total_cost'] as num).compareTo(a['total_cost'] as num));
    return report;
  }
}