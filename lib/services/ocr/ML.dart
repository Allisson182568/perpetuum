import 'dart:math';
import 'dart:ui';

/// Representa um número detectado no OCR
class NumericToken {
  final double value;
  final Rect? box;

  NumericToken(this.value, this.box);
}

/// Resultado final de um ativo
class ClassifiedAsset {
  final String ticker;
  final int quantity;
  final double averagePrice;
  final double confidence;

  ClassifiedAsset({
    required this.ticker,
    required this.quantity,
    required this.averagePrice,
    required this.confidence,
  });

  Map<String, dynamic> toMap() => {
    'ticker': ticker,
    'qty': quantity,
    'price': averagePrice,
    'confidence': confidence,
  };
}

/// ML determinístico local (baseline)
/// Pode ser substituído futuramente por TFLite
class LocalAssetML {
  static ClassifiedAsset? classify({
    required String ticker,
    required List<NumericToken> numbers,
  }) {
    int? qty;
    double? price;

    // 1️⃣ Quantidade → inteiro, grande, sem decimal
    final qtyCandidates = numbers
        .where((n) => n.value % 1 == 0)
        .map((n) => n.value.toInt())
        .where((v) => v > 0 && v < 1000000)
        .toList();

    if (qtyCandidates.isNotEmpty) {
      qty = qtyCandidates.reduce(max);
    }

    // 2️⃣ Preço médio → decimal, pequeno
    final priceCandidates = numbers
        .where((n) => n.value % 1 != 0)
        .map((n) => n.value)
        .where((v) => v > 1 && v < 5000)
        .toList();

    if (priceCandidates.isNotEmpty) {
      price = priceCandidates.reduce(min);
    }

    if (qty == null || price == null) return null;

    return ClassifiedAsset(
      ticker: ticker,
      quantity: qty,
      averagePrice: price,
      confidence: _confidence(qty, price),
    );
  }

  static double _confidence(int qty, double price) {
    double score = 0.0;
    if (qty > 0) score += 0.4;
    if (price > 0) score += 0.4;
    if (price < 1000) score += 0.2;
    return score.clamp(0, 1);
  }
}