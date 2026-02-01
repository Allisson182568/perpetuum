import 'package:supabase_flutter/supabase_flutter.dart';

class CloudService {
  final _supabase = Supabase.instance.client;

  // ===========================================================================
  // 1. LEITURA UNIFICADA (A MÁGICA ACONTECE AQUI)
  // Junta 'assets' (Bolsa) + 'immobilized_assets' (Físicos) para a Home
  // ===========================================================================

  Future<Map<String, dynamic>> getConsolidatedPortfolio() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return {'total': 0.0, 'assets': []};

    try {
      // 1. Busca Financeiros (Assets)
      final financialResponse = await _supabase.from('assets').select().eq('user_id', userId);

      // 2. Busca Físicos (Immobilized) - NOVA TABELA
      // Se der erro aqui é porque a tabela ainda não foi criada no SQL
      final physicalResponse = await _supabase.from('immobilized_assets').select().eq('user_id', userId);

      Map<String, Map<String, dynamic>> consolidated = {};
      double totalValue = 0.0;

      // --- PROCESSA FINANCEIROS (Tabela assets) ---
      for (var row in financialResponse) {
        String name = row['name'] ?? 'Desconhecido';
        String ticker = (row['ticker'] ?? name).toString().toUpperCase();

        // Limpeza de Ticker Fracionário
        if (ticker.length > 4 && ticker.endsWith('F') && RegExp(r'\d').hasMatch(ticker[ticker.length-2])) {
          ticker = ticker.substring(0, ticker.length - 1);
        }

        if (!consolidated.containsKey(ticker)) {
          consolidated[ticker] = {
            'id': row['id'],
            'ticker': ticker,
            'name': name,
            'type': row['type'] ?? 'ACAO',
            'quantity': 0.0,
            'current_price': (row['current_price'] as num?)?.toDouble() ?? 0.0,
            'average_price': (row['average_price'] as num?)?.toDouble() ?? 0.0,
            'value': 0.0,
            'is_physical': false,
            'is_audited': row['is_audited'] == true,
            'source_table': 'assets', // Marca de onde veio
            'metadata': row['metadata']
          };
        }

        var item = consolidated[ticker]!;
        double qty = (row['quantity'] as num?)?.toDouble() ?? 0.0;

        // Soma algébrica (compras e vendas)
        item['quantity'] += qty;

        // Atualiza preço se vier um mais recente
        double cp = (row['current_price'] as num?)?.toDouble() ?? 0.0;
        if (cp > 0) item['current_price'] = cp;
      }

      // --- PROCESSA FÍSICOS (Tabela immobilized_assets) ---
      for (var row in physicalResponse) {
        // Usa um ID único visual para não conflitar com tickers de bolsa
        // Ex: "CARRO_123"
        String key = "PHYSICAL_${row['id']}";

        double currentPrice = (row['current_price'] as num?)?.toDouble() ?? 0.0;
        double purchasePrice = (row['purchase_price'] as num?)?.toDouble() ?? 0.0;
        String type = row['type']?.toString().toUpperCase() ?? 'OUTROS';

        consolidated[key] = {
          'id': row['id'],
          'ticker': row['name'].toString().toUpperCase(), // Na home, o nome (Ex: HONDA CIVIC) vira o destaque
          'name': row['description'] ?? row['name'],      // A descrição vira o detalhe
          'type': type,
          'quantity': 1.0, // Físico é sempre 1 unidade aqui
          'current_price': currentPrice,
          'average_price': purchasePrice,
          'value': currentPrice > 0 ? currentPrice : purchasePrice,
          'is_physical': true,
          'is_audited': true, // Assumimos correto pois foi inserido manualmente
          'source_table': 'immobilized_assets', // Marca de onde veio
          'metadata': row['metadata']
        };
      }

      // --- CALCULA TOTAIS E LIMPA ---
      List<Map<String, dynamic>> finalAssets = [];
      consolidated.forEach((key, asset) {
        if (asset['is_physical'] == true) {
          // Físicos: Valor já está definido
          totalValue += asset['value'];
          finalAssets.add(asset);
        } else {
          // Financeiros: Calcula Qtd * Preço
          double qty = asset['quantity'];
          // Só mostra se tiver saldo relevante
          if (qty.abs() > 0.001) {
            double val = qty * asset['current_price'];
            asset['value'] = val;
            totalValue += val;
            finalAssets.add(asset);
          }
        }
      });

      // Ordena por valor total (do maior para o menor)
      finalAssets.sort((a, b) => (b['value'] as num).compareTo(a['value'] as num));

      return {'total': totalValue, 'assets': finalAssets};

    } catch (e) {
      print("Erro CloudService: $e");
      // Retorna vazio para não travar o app
      return {'total': 0.0, 'assets': []};
    }
  }

  // ===========================================================================
  // 2. SALVAMENTO ESPECÍFICO (CADA UM NA SUA TABELA)
  // ===========================================================================

  // Salva Carro/Moto na tabela 'immobilized_assets'
  Future<void> saveVehicle({
    required String type, // 'carros' ou 'motos'
    required String brand,
    required String model,
    required String year,
    required double purchasePrice,
    required double currentFipePrice,
    String? fipeCode,
    Map<String, dynamic>? metadata,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("Usuário deslogado");

    // Normaliza tipo para o banco
    String dbType = type.toUpperCase().contains('MOTO') ? 'MOTO' : 'CARRO';
    String fullName = "$brand $model $year";

    Map<String, dynamic> meta = metadata ?? {};
    meta.addAll({'brand': brand, 'model': model, 'year': year, 'fipe_code': fipeCode});

    // 1. Salva na tabela dedicada
    await _supabase.from('immobilized_assets').insert({
      'user_id': userId,
      'name': fullName,
      'type': dbType,
      'description': "$brand $model",
      'purchase_price': purchasePrice,
      'current_price': currentFipePrice,
      'acquisition_date': DateTime.now().toIso8601String(),
      'metadata': meta
    });

    // 2. Salva no Histórico (Transactions) para o Relatório de IR
    await _registerHistory(userId, fullName, 'C', 1, purchasePrice, dbType);
  }

  // Salva Imóvel na tabela 'immobilized_assets'
  Future<void> saveRealEstate({
    required String type,
    required String description,
    required String location,
    required double marketValue,
    required double purchasePrice
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("Usuário deslogado");

    await _supabase.from('immobilized_assets').insert({
      'user_id': userId,
      'name': description,
      'type': 'IMOVEL',
      'description': location,
      'purchase_price': purchasePrice,
      'current_price': marketValue,
      'acquisition_date': DateTime.now().toIso8601String(),
      'metadata': {'location': location}
    });

    await _registerHistory(userId, description, 'C', 1, purchasePrice, 'IMOVEL');
  }

  // Salva Ação/FII na tabela 'assets' (Financeiro)
  Future<void> saveStock({
    required String ticker, required double quantity, required double currentPrice, required double purchasePrice,
    String? type, String? date, String? broker, String? assetType, Map<String, dynamic>? enrichmentData
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("Usuário deslogado");

    DateTime opDate = date != null ? DateTime.parse(date) : DateTime.now();
    String safeTicker = ticker.toUpperCase().trim();

    // 1. Assets (Snapshot - Saldo Atual)
    final assetData = {
      'user_id': userId,
      'ticker': safeTicker,
      'name': safeTicker,
      'type': assetType ?? 'ACAO',
      'year': DateTime.now().year,
      'quantity': quantity,
      'purchase_price': purchasePrice,
      'current_price': currentPrice,
      'operation_date': opDate.toIso8601String(),
      'metadata': enrichmentData ?? {},
      'is_audited': true
    };

    // Upsert Manual (Verifica se existe antes de inserir/atualizar)
    // Usamos 'ticker' como chave única para financeiros
    final existing = await _supabase.from('assets')
        .select('id')
        .eq('user_id', userId)
        .eq('ticker', safeTicker)
        .maybeSingle();

    if (existing != null) {
      await _supabase.from('assets').update(assetData).eq('id', existing['id']);
    } else {
      await _supabase.from('assets').insert(assetData);
    }

    // 2. Transactions (Histórico Eterno)
    await _registerHistory(userId, safeTicker, 'C', quantity, purchasePrice, assetType ?? 'ACAO', date: opDate);
  }

  // Helper privado para registrar histórico na tabela 'transactions'
  Future<void> _registerHistory(String uid, String ticker, String op, double qtd, double price, String type, {DateTime? date}) async {
    await _supabase.from('transactions').insert({
      'user_id': uid,
      'ticker': ticker,
      'operation_type': op,
      'quantity': qtd,
      'unit_price': price,
      'total_value': qtd * price,
      'date': (date ?? DateTime.now()).toIso8601String(),
      'asset_type': type,
      'broker': 'MANUAL'
    });
  }

  // ===========================================================================
  // 3. UTILITÁRIOS E COMPATIBILIDADE
  // ===========================================================================

  // Atualizado: Aceita 'source_table' para saber onde deletar
  Future<void> deleteAsset(String id, {String table = 'assets'}) async {
    // Se não especificar tabela, tenta 'assets' por padrão
    await _supabase.from(table).delete().eq('id', id);
  }

  Future<double> getTotalNetWorth([int? year]) async {
    final map = await getConsolidatedPortfolio();
    return map['total'] as double;
  }

  Future<List<Map<String, dynamic>>> getAllAssets([int? year]) async {
    final map = await getConsolidatedPortfolio();
    return map['assets'] as List<Map<String, dynamic>>;
  }

  // Auditoria (Geralmente usada apenas para financeiros importados)
  Future<void> confirmAsset(String t) async {
    final uid = _supabase.auth.currentUser?.id;
    if(uid!=null) {
      // Atualiza apenas na tabela de financeiros
      await _supabase.from('assets').update({'is_audited': true}).eq('user_id', uid).or('ticker.eq.$t,name.eq.$t');
    }
  }

  // Exclusão completa por Ticker (Usado pelo Auditor)
  Future<void> hardDeleteByTicker(String t) async {
    final uid = _supabase.auth.currentUser?.id;
    if(uid!=null) {
      // Tenta apagar das duas tabelas para garantir
      await _supabase.from('assets').delete().eq('user_id', uid).or('ticker.eq.$t,name.eq.$t');
      await _supabase.from('immobilized_assets').delete().eq('user_id', uid).eq('name', t);
    }
  }

  // Usado pelo Auditor para lançar ajustes
  Future<void> registerTransaction({
    required String ticker, required String name, required String operationType, required double quantity,
    required double unitPrice, required DateTime date, required String assetType, String? notes
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    // Registra no histórico
    if(uid!=null) await _registerHistory(uid, ticker, operationType, quantity, unitPrice, assetType, date: date);

    // Nota: O Auditor também costuma chamar saveStock depois disso para atualizar o saldo,
    // então não precisamos atualizar 'assets' aqui duplicado.
  }

  // Métodos de Importação (Mantidos)
  Future<void> saveRawTransactionBatch(List<Map<String, dynamic>> t) async => await _supabase.from('transactions').insert(t);
  Future<void> logImport(String h, String n) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid != null) await _supabase.from('import_logs').insert({'user_id': uid, 'file_hash': h, 'filename': n});
  }
  Future<bool> isFileAlreadyImported(String h) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final res = await _supabase.from('import_logs').select('id').eq('user_id', uid).eq('file_hash', h).maybeSingle();
    return res != null;
  }

  Future<String?> getTickerByCnpj(String cnpj) async {
    try {
      final cleanCnpj = cnpj.replaceAll(RegExp(r'[^0-9]'), '');
      final response = await _supabase
          .from('asset_metadata')
          .select('ticker')
          .eq('cnpj', cleanCnpj)
          .maybeSingle();

      return response?['ticker'] as String?;
    } catch (e) {
      return null;
    }
  }
}