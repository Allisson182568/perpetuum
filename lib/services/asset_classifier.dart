class AssetClassifier {
  static const List<String> knownEtfs = ['BOVA11', 'IVVB11', 'SMAL11', 'HASH11']; // Lista pode crescer

  static Map<String, String> classify(String ticker) {
    String cleanTicker = ticker.toUpperCase().trim();

    // Regra 1: Stocks americanas (Sem números no final, exceto casos raros)
    if (!RegExp(r'\d+$').hasMatch(cleanTicker)) {
      return {'type': 'STOCK_US', 'label': 'Ação EUA'};
    }

    // Regra 2: BDRs
    if (cleanTicker.endsWith('34') || cleanTicker.endsWith('35')) {
      return {'type': 'BDR', 'label': 'BDR (Internacional)'};
    }

    // Regra 3: FIIs vs ETFs vs Units (Final 11)
    if (cleanTicker.endsWith('11')) {
      if (knownEtfs.contains(cleanTicker)) {
        return {'type': 'ETF', 'label': 'ETF'};
      }
      // Heurística: Na dúvida, assume FII, mas o ideal é consultar API
      return {'type': 'FII', 'label': 'Fundo Imobiliário'};
    }

    // Regra 4: Ações BR (3, 4, 5, 6)
    if (RegExp(r'[3456]$').hasMatch(cleanTicker)) {
      return {'type': 'ACTION_BR', 'label': 'Ação Brasil'};
    }

    return {'type': 'OUTROS', 'label': 'Outros'};
  }
}