import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'import_strategy.dart';

class IrpfStrategy implements ImportStrategy {
  @override
  String get title => "Importar Declaração IRPF";
  @override
  String get description => "Leitura de Precisão: Layout Tabular 2025 (Bens e Rendimentos).";
  @override
  List<String> get allowedExtensions => ['pdf'];
  @override
  IconData get icon => Icons.picture_as_pdf_rounded;

  @override
  Future<List<ImportResult>> parse(PlatformFile file, Uint8List bytes) async {
    PdfDocument? document;
    try {
      document = file.path != null
          ? PdfDocument(inputBytes: await File(file.path!).readAsBytes())
          : PdfDocument(inputBytes: bytes);

      // Usamos uma extração que mantém o layout para não misturar as colunas de valores
      String rawText = PdfTextExtractor(document).extractText();
      List<String> lines = rawText.split('\n');

      List<ImportResult> results = [];

      bool inBensSection = false;
      bool inRendimentosSection = false;

      for (int i = 0; i < lines.length; i++) {
        String line = lines[i].toUpperCase().trim();

        // --- DETECÇÃO DE SEÇÃO ---
        if (line.contains("DECLARAÇÃO DE BENS E DIREITOS")) {
          inBensSection = true;
          inRendimentosSection = false;
          continue;
        }
        if (line.contains("RENDIMENTOS ISENTOS E NÃO TRIBUTÁVEIS")) {
          inRendimentosSection = true;
          inBensSection = false;
          continue;
        }
        // Para se mudar de seção principal
        if (line.contains("DÍVIDAS E ÔNUS") || line.contains("RESUMO DA DECLARAÇÃO")) {
          inBensSection = false;
          inRendimentosSection = false;
        }

        // --- LÓGICA PARA BENS E DIREITOS (Páginas 5 e 6 do seu print) ---
        if (inBensSection) {
          // Detecta o início de um bloco de bem (Ex: 228 01 16)
          // O Regex procura: Item(3 dígitos) Grupo(2 dígitos) Código(2 dígitos)
          final assetStart = RegExp(r'^(\d{3})\s+(\d{2})\s+(\d{2})');
          if (assetStart.hasMatch(line)) {
            final match = assetStart.firstMatch(line)!;
            String code = match.group(3)!;

            // A descrição costuma estar na mesma linha ou nas seguintes
            // Vamos pegar as próximas 3 linhas para garantir que pegamos o Ticker/CNPJ
            String fullDesc = line;
            for (int j = 1; j <= 4 && (i + j) < lines.length; j++) {
              fullDesc += " " + lines[i+j].toUpperCase().trim();
            }

            // O valor de 2024 é sempre o ÚLTIMO valor da linha ou bloco
            // Procuramos por valores no formato 0.000,00
            final valueMatches = RegExp(r'(\d{1,3}(?:\.\d{3})*,\d{2})').allMatches(fullDesc).toList();

            if (valueMatches.isNotEmpty) {
              double val2024 = _parseMoney(valueMatches.last.group(1)!);

              if (val2024 > 0) {
                String ticker = _extractTicker(fullDesc);
                String cnpj = _extractCNPJ(fullDesc);
                double qty = _extractQty(fullDesc);

                results.add(ImportResult(
                    ticker: ticker == "OUTROS" ? _generateSlug(fullDesc) : ticker,
                    qty: qty > 0 ? qty : 1.0,
                    price: qty > 0 ? val2024 / qty : val2024,
                    assetType: _mapCodeToType(code),
                    type: 'C',
                    date: "31/12/2024",
                    broker: "IRPF 2025",
                    cnpj: cnpj,
                    isEarning: false,
                    enrichment: {'location': _inferLocation(fullDesc), 'ir_code': code}
                ));
              }
            }
          }
        }

        // --- LÓGICA PARA RENDIMENTOS (Página 1 do seu print) ---
        if (inRendimentosSection) {
          // Busca linhas com CNPJ + Nome + Valor (Final da linha)
          final earningMatch = RegExp(r'(\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2})\s+(.*?)\s+(\d{1,3}(?:\.\d{3})*,\d{2})$')
              .firstMatch(line);

          if (earningMatch != null) {
            results.add(ImportResult(
              ticker: _extractTicker(earningMatch.group(2)!) != "OUTROS"
                  ? _extractTicker(earningMatch.group(2)!)
                  : earningMatch.group(1)!,
              qty: 0,
              price: _parseMoney(earningMatch.group(3)!),
              assetType: 'DIVIDENDO',
              type: 'DIV',
              date: "Ano 2024",
              broker: earningMatch.group(2)!.trim(),
              cnpj: earningMatch.group(1)!,
              isEarning: true,
            ));
          }
        }
      }

      document.dispose();
      if (results.isEmpty) throw Exception("Nenhum dado encontrado. Verifique se o PDF tem texto selecionável.");
      return results;
    } catch (e) {
      document?.dispose();
      throw Exception("Erro na lapidação: $e");
    }
  }

  // --- HELPERS DE PRECISÃO ---

  double _parseMoney(String s) => double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;

  String _mapCodeToType(String c) {
    if (c == '31' || c == '01' || c == '03') return 'ACAO'; // 03/31 para ações/stocks
    if (c == '73' || c == '74') return 'FII';
    if (c == '16' || c == '11' || c == '12') return 'REAL_ESTATE';
    if (c == '02') return 'VEHICLE';
    return 'OUTROS';
  }

  String _extractTicker(String s) {
    // Busca: 4 letras + número (PETR4) ou Tickers USA (3-4 letras: STAG, AVB)
    final br = RegExp(r'\b([A-Z]{4}\d{1,2})\b').firstMatch(s);
    if (br != null) return br.group(0)!;

    // Se tiver "TICKER:" ou "CÓDIGO:" escrito, pega o que vem depois
    final label = RegExp(r'(?:CÓDIGO|TICKER|NEGOCIAÇÃO):\s?([A-Z]{2,5})').firstMatch(s);
    if (label != null) return label.group(1)!;

    return "OUTROS";
  }

  double _extractQty(String s) {
    // Pega números decimais antes de AÇÕES/COTAS (Ex: 16,32815 AÇÕES)
    final m = RegExp(r'([\d\.,]{1,15})\s?(AÇÕES|COTAS|UNIDADES|SHARES)', caseSensitive: false).firstMatch(s);
    if (m != null) return _parseMoney(m.group(1)!);
    return 0.0;
  }

  String _extractCNPJ(String s) => RegExp(r'\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}').firstMatch(s)?.group(0) ?? "";

  String _inferLocation(String s) => (s.contains("ESTADOS UNIDOS") || s.contains("EXTERIOR")) ? "USA" : "BR";

  String _generateSlug(String s) {
    final words = s.split(' ').where((w) => w.length > 3 && !w.contains(RegExp(r'\d'))).toList();
    if (words.length >= 2) return "${words[0]}_${words[1]}".toUpperCase();
    return "ATIVO_IR";
  }
}