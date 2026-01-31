import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'import_strategy.dart';

class AvenueStrategy implements ImportStrategy {
  @override
  String get title => "Importar Avenue (EUA)";
  @override
  String get description => "PDF de Extrato ou Notas.\nProcessa Stocks, REITs e Dividendos.";
  @override
  List<String> get allowedExtensions => ['pdf'];
  @override
  IconData get icon => Icons.account_balance_rounded;

  @override
  Future<List<ImportResult>> parse(PlatformFile file, Uint8List bytes) async {
    try {
      String fullText = await ReadPdfText.getPDFtext(file.path!);
      // Limpeza para facilitar regex
      String text = fullText.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');

      List<ImportResult> items = [];

      // 1. DETECÇÃO DE OPERAÇÕES (COMPRA/VENDA)
      // Padrão Avenue/Apex: DATA | TIPO | SIMBOLO | QTD | PREÇO
      // Exemplo Regex flexível para capturar: "12/05/2023 COMPRA AAPL 10 150.00"

      // Regex para data (MM/DD/YYYY ou DD/MM/YYYY dependendo do relatório)
      final regexTrade = RegExp(r'(\d{2}/\d{2}/\d{4})\s+(COMPRA|VENDA|BUY|SELL)\s+([A-Z]{1,5})\s+([\d\.,]+)\s+([\d\.,]+)');

      for (var m in regexTrade.allMatches(text)) {
        String dateStr = m.group(1)!;
        String typeRaw = m.group(2)!.toUpperCase();
        String ticker = m.group(3)!;
        double qty = _parseUSNumber(m.group(4)!); // Avenue usa ponto para decimal geralmente
        double price = _parseUSNumber(m.group(5)!);

        String type = (typeRaw == 'COMPRA' || typeRaw == 'BUY') ? 'C' : 'V';

        // Ajuste de data se necessário (assumindo formato BR no PDF pt-br)
        // Se for formato US, precisaria inverter

        if (qty > 0 && price > 0) {
          items.add(ImportResult(
              ticker: ticker,
              qty: qty,
              price: price, // Preço em Dólar
              type: type,
              assetType: 'STOCK',
              date: dateStr,
              broker: "Avenue Securities",
              enrichment: {
                'name': ticker,
                'location': 'USA',
                'currency': 'USD',
                'original_desc': 'Importado Avenue'
              }
          ));
        }
      }

      // 2. DETECÇÃO DE DIVIDENDOS
      // Padrão: DATA | DIVIDENDOS | SIMBOLO | VALOR
      final regexDiv = RegExp(r'(\d{2}/\d{2}/\d{4})\s+(DIVIDENDO|DIVIDEND)\s+([A-Z]{1,5})\s+([\d\.,]+)');

      for (var m in regexDiv.allMatches(text)) {
        String dateStr = m.group(1)!;
        String ticker = m.group(3)!;
        double val = _parseUSNumber(m.group(4)!);

        if (val > 0) {
          items.add(ImportResult(
              ticker: ticker,
              qty: 0,
              price: val, // Valor líquido
              type: 'DIV',
              assetType: 'DIVIDENDO',
              date: dateStr,
              broker: "Avenue Securities",
              isEarning: true,
              enrichment: {
                'location': 'USA',
                'currency': 'USD',
                'original_desc': 'Dividend Avenue $ticker'
              }
          ));
        }
      }

      if (items.isEmpty) throw Exception("Nenhuma operação encontrada. Verifique se é o PDF correto (Nota de Corretagem ou Extrato).");
      return items;

    } catch (e) {
      throw Exception("Erro Avenue: $e");
    }
  }

  // Helper para números americanos (1,000.50) vs brasileiros (1.000,50)
  // Relatórios Avenue geralmente vêm em formato americano ou misto.
  double _parseUSNumber(String s) {
    try {
      // Remove virgula de milhar se existir antes do ponto
      if (s.contains('.') && s.indexOf(',') < s.indexOf('.')) {
        s = s.replaceAll(',', '');
      }
      // Se tiver virgula no final, troca por ponto (formato BR)
      else if (s.contains(',')) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      }
      return double.parse(s);
    } catch (_) {
      return 0.0;
    }
  }
}