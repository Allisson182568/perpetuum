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
  String get description =>
      "PDF completo.\nExtração inteligente com heurística (BR / Exterior).";

  @override
  List<String> get allowedExtensions => ['pdf'];

  @override
  IconData get icon => Icons.picture_as_pdf_rounded;

  @override
  Future<List<ImportResult>> parse(
      PlatformFile file, Uint8List bytes) async {
    PdfDocument? document;

    try {
      if (file.path != null) {
        document =
            PdfDocument(inputBytes: await File(file.path!).readAsBytes());
      } else {
        document = PdfDocument(inputBytes: bytes);
      }

      final extractor = PdfTextExtractor(document);
      final rawText = extractor.extractText();

      final cleanText = rawText
          .replaceAll('\n', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .toUpperCase();

      if (!cleanText.contains("BENS E DIREITOS")) {
        throw Exception("Seção BENS E DIREITOS não encontrada");
      }

      String section = cleanText.split("BENS E DIREITOS")[1];

      if (section.contains("DÍVIDAS E ÔNUS")) {
        section = section.split("DÍVIDAS E ÔNUS")[0];
      }

      final itemSplitter = RegExp(r'(\d{2}\s?-\s?)');
      final blocks = section.split(itemSplitter);
      final codes = itemSplitter
          .allMatches(section)
          .map((m) =>
          m.group(0)!.replaceAll(RegExp(r'[^0-9]'), ''))
          .toList();

      if (blocks.isNotEmpty) {
        blocks.removeAt(0);
      }

      final List<ImportResult> results = [];

      for (int i = 0; i < blocks.length; i++) {
        final block = blocks[i];
        final code = codes[i];

        if (!_isValidCode(code)) continue;

        final values =
        RegExp(r'R\$\s?([\d\.,]+)').allMatches(block).toList();

        if (values.isEmpty) continue;

        final totalValue = _parseMoney(values.last.group(1)!);
        if (totalValue <= 0) continue;

        final ticker = _extractTicker(block);
        final qty = _extractQty(block);
        final cnpj = _extractCNPJ(block);

        final location = _inferLocation(block);
        final confidence = _calculateConfidence(
          hasTicker: ticker != "OUTROS",
          hasQty: qty > 0,
          hasCnpj: cnpj.isNotEmpty,
          hasValue: totalValue > 0,
          validCode: true,
        );

        results.add(
          ImportResult(
            ticker:
            ticker == "OUTROS" ? _generateSlug(block) : ticker,
            qty: qty > 0 ? qty : 1.0,
            price: qty > 0 ? totalValue / qty : totalValue,
            assetType: _mapCodeToType(code),
            type: 'C',
            date: DateFormat('dd/MM/yyyy')
                .format(DateTime.now()),
            broker: "IRPF Importado",
            cnpj: cnpj,
            isEarning: false,
            enrichment: {
              'original_desc': block.trim(),
              'location': location,
              'confidence': confidence,
              'ir_code': code,
            },
          ),
        );
      }

      document.dispose();

      if (results.isEmpty) {
        throw Exception("Nenhum ativo identificado");
      }

      return results;
    } catch (e) {
      document?.dispose();
      throw Exception("Erro ao importar IRPF: $e");
    }
  }

  bool _isValidCode(String c) {
    return [
      '31',
      '73',
      '74',
      '01',
      '02',
      '11',
      '12',
      '21',
      '81',
      '82',
      '89',
      '99'
    ].contains(c);
  }

  double _parseMoney(String s) {
    return double.tryParse(
        s.replaceAll('.', '').replaceAll(',', '.')) ??
        0.0;
  }

  String _mapCodeToType(String c) {
    if (c == '31') return 'ACAO';
    if (['73', '74'].contains(c)) return 'FII';
    if (c.startsWith('0') || c.startsWith('1')) return 'IMOVEL';
    return 'OUTROS';
  }

  String _extractTicker(String s) {
    final br =
    RegExp(r'\b[A-Z]{4}\d{1,2}\b').firstMatch(s);
    if (br != null) return br.group(0)!;

    final us =
    RegExp(r'\b[A-Z]{2,5}\b').firstMatch(s);
    if (us != null) return us.group(0)!;

    return "OUTROS";
  }

  double _extractQty(String s) {
    final m = RegExp(
        r'([\d\.,]+)\s?(AÇÕES|COTAS|QUOTAS|UNIDADES)',
        caseSensitive: false)
        .firstMatch(s);
    return m != null ? _parseMoney(m.group(1)!) : 0.0;
  }

  String _extractCNPJ(String s) {
    return RegExp(r'\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}')
        .firstMatch(s)
        ?.group(0) ??
        "";
  }

  String _inferLocation(String s) {
    if (s.contains("EXTERIOR") ||
        s.contains("USA") ||
        s.contains("ESTADOS UNIDOS")) {
      return "EXTERIOR";
    }
    return "BR";
  }

  double _calculateConfidence({
    required bool hasTicker,
    required bool hasQty,
    required bool hasCnpj,
    required bool hasValue,
    required bool validCode,
  }) {
    double score = 0.0;

    if (validCode) score += 0.25;
    if (hasValue) score += 0.25;
    if (hasTicker) score += 0.20;
    if (hasQty) score += 0.15;
    if (hasCnpj) score += 0.15;

    return score.clamp(0.0, 1.0);
  }

  String _generateSlug(String s) {
    final words = s
        .replaceAll(RegExp(r'[^A-Z ]'), '')
        .split(' ')
        .where((w) => w.length > 3)
        .toList();

    if (words.length >= 2) {
      return "${words[0]}_${words[1]}";
    }

    return "ATIVO_IRPF";
  }
}