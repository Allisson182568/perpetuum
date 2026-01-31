import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'import_strategy.dart';
import '../../services/ai/asset_classifier.dart';

class B3Strategy implements ImportStrategy {
  @override
  String get title => "Importar Excel (B3/Inter/Outros)";
  @override
  String get description => "Planilhas de corretoras.\nLê Taxas, IDs e calcula PM real.";
  @override
  List<String> get allowedExtensions => ['xlsx'];
  @override
  IconData get icon => Icons.table_view_rounded;

  @override
  Future<List<ImportResult>> parse(PlatformFile file, Uint8List bytes) async {
    // Variável fora do try para garantir escopo
    var excel;

    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      debugPrint("Erro fatal ao decodificar Excel: $e");
      throw Exception("O arquivo Excel parece estar corrompido ou incompatível.");
    }

    try {
      List<ImportResult> items = [];

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table];
        if (sheet == null || sheet.rows.isEmpty) continue;

        debugPrint("--- Processando Aba: $table ---");

        // 1. CAÇADOR DE CABEÇALHO
        int headerRowIndex = -1;
        Map<String, int> map = {};

        for (int r = 0; r < sheet.rows.length && r < 20; r++) {
          var row = sheet.rows[r];
          var candidateMap = _mapHeaders(row);

          if (candidateMap.containsKey('ticker') && (candidateMap.containsKey('qty') || candidateMap.containsKey('date'))) {
            headerRowIndex = r;
            map = candidateMap;
            debugPrint("✅ Cabeçalho encontrado na linha $r");
            break;
          }
        }

        if (headerRowIndex == -1) continue;

        // 2. LEITURA DE DADOS
        for (int i = headerRowIndex + 1; i < sheet.rows.length; i++) {
          var row = sheet.rows[i];
          if (row.isEmpty) continue;

          String ticker = _getVal(row, map['ticker']).toUpperCase();

          if (ticker.length < 3 || ticker.contains("TOTAL") || ticker.contains("RESUMO")) continue;

          String date = _getVal(row, map['date']);
          String id = _getVal(row, map['id']);
          String broker = _getVal(row, map['broker']);
          if (broker.isEmpty) broker = "Importado Excel";

          double qty = _parseNum(row, map['qty']);
          double rawPrice = _parseNum(row, map['price']);
          double fees = _parseNum(row, map['fees']);

          // --- LÓGICA DE DETECÇÃO DE TIPO (C/V) SUPERIOR ---
          String typeRaw = _getVal(row, map['type']).toUpperCase().trim();
          String type = 'C'; // Padrão é compra

          // Regra 1: Quantidade Negativa é sempre VENDA
          if (qty < 0) {
            type = 'V';
            qty = qty.abs(); // Transforma em positivo para salvar
          }
          // Regra 2: Palavras Chave
          else if (
          typeRaw.startsWith('V') ||  // V, Venda, Vendido
              typeRaw.startsWith('S') ||  // Sell, Sale, Saida
              typeRaw.contains('CREDITO') ||
              typeRaw.contains('CRÉDITO') ||
              typeRaw.contains('ALIENA') // Alienação
          ) {
            type = 'V';
          }

          // Cálculo do Preço Médio Efetivo
          double finalPrice = rawPrice;
          if (qty > 0) {
            if (type == 'C') {
              finalPrice = ((rawPrice * qty) + fees) / qty;
            } else {
              finalPrice = ((rawPrice * qty) - fees) / qty;
            }
          }

          if (qty > 0) {
            items.add(ImportResult(
                ticker: ticker,
                qty: qty,
                price: finalPrice,
                fees: fees,
                transactionId: id,
                type: type,
                assetType: AssetClassifier.classify(ticker),
                date: date,
                broker: broker,
                enrichment: {'name': ticker, 'original_row_id': id}
            ));
          }
        }
      }

      if (items.isEmpty) {
        throw Exception("Nenhuma operação identificada. Verifique se as colunas 'Ativo' e 'Quantidade' estão preenchidas.");
      }
      return items;

    } catch (e) {
      debugPrint("Erro B3 Strategy: $e");
      throw Exception("Erro ao ler dados do Excel: $e");
    }
  }

  // --- MAPA DE COLUNAS ---
  Map<String, int> _mapHeaders(List<Data?> headerRow) {
    Map<String, int> map = {};
    for (int i = 0; i < headerRow.length; i++) {
      String val = _getStringFromData(headerRow[i]).toLowerCase().trim();

      if (val.contains('ativo') || val.contains('papel') || val.contains('ticker') || val.contains('código')) map['ticker'] = i;
      else if (val.contains('data') || val.contains('negociação')) map['date'] = i;
      else if (val.contains('quantidade') || val == 'qtd') map['qty'] = i;
      else if ((val.contains('preço') || val.contains('unitário')) && !val.contains('com taxas')) map['price'] = i;
      else if (val.contains('taxas') || val.contains('custos')) map['fees'] = i;
      else if (val.contains('número') || val.contains('nota') || val == 'id') map['id'] = i;
      else if (val.contains('instituição') || val.contains('corretora')) map['broker'] = i;
      else if (val.contains('tipo') || val.contains('operação') || val == 'c/v') map['type'] = i;
    }
    return map;
  }

  // --- HELPERS SEGUROS ---

  String _getStringFromData(Data? data) {
    if (data == null || data.value == null) return "";
    return data.value.toString();
  }

  String _getVal(List<Data?> row, int? index) {
    if (index == null || index >= row.length) return "";
    var cell = row[index];
    if (cell == null || cell.value == null) return "";
    return cell.value.toString().trim();
  }

  double _parseNum(List<Data?> row, int? index) {
    if (index == null || index >= row.length) return 0.0;

    var cell = row[index];
    if (cell == null || cell.value == null) return 0.0;

    var val = cell.value;

    if (val is DoubleCellValue) return val.value;
    if (val is IntCellValue) return val.value.toDouble();

    String s = val.toString().trim();
    if (s.isEmpty) return 0.0;

    s = s.replaceAll('R\$', '').replaceAll(' ', '');

    if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    }

    return double.tryParse(s) ?? 0.0;
  }
}