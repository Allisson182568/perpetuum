import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'; // Para kIsWeb
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'import_strategy.dart';
import '../../services/ocr_service.dart';
import '../../services/ai/asset_classifier.dart';

class PrintStrategy implements ImportStrategy {
  final OcrService _ocr = OcrService();

  @override
  String get title => "Leitura de Print";

  @override
  String get description => "Envie um print da tela da corretora.\nIdentificamos Ticker, Qtd e Preço.";

  @override
  List<String> get allowedExtensions => ['png', 'jpg', 'jpeg', 'heic'];

  @override
  IconData get icon => Icons.image_search_rounded;

  @override
  Future<List<ImportResult>> parse(PlatformFile file, Uint8List bytes) async {
    // OCR geralmente roda localmente no dispositivo (ML Kit), não funciona bem na Web
    if (kIsWeb) {
      throw Exception("Leitura de print não suportada na versão Web.");
    }

    try {
      // Chama o serviço de OCR existente
      // O path é necessário para bibliotecas nativas de OCR (Google ML Kit)
      final rawData = await _ocr.extractData(file.path!);

      List<ImportResult> results = [];

      for (var item in rawData) {
        String ticker = (item['ticker'] ?? '').toString().toUpperCase().trim();

        // Validação básica para ignorar lixo do OCR
        if (ticker.length < 3) continue;

        double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
        double price = double.tryParse(item['price'].toString()) ?? 0.0;

        // Se o OCR não pegou o tipo, usamos a IA Classificadora
        String type = item['type'] ?? 'C'; // Assume Compra se não souber
        String assetType = AssetClassifier.classify(ticker);

        results.add(ImportResult(
            ticker: ticker,
            qty: qty,
            price: price,
            type: type,
            assetType: assetType,
            date: DateFormat('dd/MM/yyyy').format(DateTime.now()), // Data de hoje
            broker: "Importado via Print",
            enrichment: {'original_desc': 'OCR Scan', 'name': ticker},
            isEarning: false
        ));
      }

      if (results.isEmpty) {
        throw Exception("O OCR não conseguiu identificar ativos na imagem. Tente uma imagem com melhor resolução ou layout padrão.");
      }

      return results;

    } catch (e) {
      throw Exception("Erro no processamento da imagem: $e");
    }
  }
}