import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../ocr_service.dart';
import 'ocr_stub.dart';

class OcrServiceImpl implements OcrService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<List<Map<String, dynamic>>> extractData(String path) async {
    try {
      final inputImage = InputImage.fromFilePath(path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      List<String> allLines = [];
      for (var block in recognizedText.blocks) {
        for (var line in block.lines) {
          allLines.add(line.text.trim());
        }
      }

      final tickerRegex = RegExp(r'\b[A-Z]{4}(3|4|5|6|11)\b');
      final List<_AssetMarker> markers = [];

      for (int i = 0; i < allLines.length; i++) {
        final cleanLine = allLines[i].toUpperCase().replaceAll(' ', '');
        final match = tickerRegex.firstMatch(cleanLine);

        if (match != null && cleanLine.length < 10) {
          markers.add(_AssetMarker(match.group(0)!, i));
        }
      }

      final List<Map<String, dynamic>> assetsFound = [];

      for (int i = 0; i < markers.length; i++) {
        final currentMarker = markers[i];
        final int startLine = currentMarker.lineIndex;
        final int endLine = (i + 1 < markers.length) ? markers[i + 1].lineIndex : allLines.length;
        final List<String> context = allLines.sublist(startLine, endLine);

        final data = _parseAssetBlock(currentMarker.ticker, context);
        if (data['qty'] > 0 || data['price'] > 0) {
          assetsFound.add(data);
        }
      }

      return assetsFound;

    } catch (e) {
      debugPrint("Erro OCR Mobile: $e");
      return [];
    }
  }

  Map<String, dynamic> _parseAssetBlock(String ticker, List<String> lines) {
    int qty = 0;
    double pm = 0.0;
    double currentTotal = 0.0;
    double costTotal = 0.0;

    List<int> integersFound = [];
    List<double> moneyFound = [];

    for (String line in lines) {
      if (line.contains('%') || line.toLowerCase().contains('min')) continue;

      if (!line.contains('R\$') && RegExp(r'^\d+$').hasMatch(line.replaceAll('.', ''))) {
        int val = _extractInt(line);
        if (val > 0 && val < 1000000) integersFound.add(val);
      }

      if (line.contains(',') || line.contains('R\$')) {
        double val = _extractDouble(line);
        if (val > 0) moneyFound.add(val);
      }
    }

    if (integersFound.isNotEmpty) qty = integersFound.first;

    for (var val in moneyFound) {
      if (currentTotal == 0.0 && val > 1000) {
        currentTotal = val;
        continue;
      }
      if (pm == 0.0 && val < 1000) {
        pm = val;
        continue;
      }
      if (costTotal == 0.0 && val > 1000 && val != currentTotal) {
        costTotal = val;
      }
    }

    if (pm == 0.0 && costTotal > 0 && qty > 0) pm = costTotal / qty;
    if (pm == 0.0 && currentTotal > 0 && qty > 0) pm = currentTotal / qty;

    return {
      'ticker': ticker,
      'qty': qty,
      'price': double.parse(pm.toStringAsFixed(2)),
    };
  }

  int _extractInt(String text) {
    try {
      String clean = text.replaceAll('.', '').trim();
      return int.parse(clean);
    } catch (_) {}
    return 0;
  }

  double _extractDouble(String text) {
    try {
      String clean = text.replaceAll(RegExp(r'[^0-9.,]'), '');
      clean = clean.replaceAll('.', '').replaceAll(',', '.');
      return double.parse(clean);
    } catch (_) {}
    return 0.0;
  }
}

class _AssetMarker {
  final String ticker;
  final int lineIndex;
  _AssetMarker(this.ticker, this.lineIndex);
}