class AssetClassifier {
  static const Set<String> _knownEtfs = {
    'IVVB11', 'BOVA11', 'SMAL11', 'HASH11', 'XINA11', 'NASD11', 'VNQ', 'IAU', 'GLD', 'QQQ', 'VOO', 'SPY'
  };

  static const Set<String> _knownUnits = {
    'TAEE11', 'KLBN11', 'SAPR11', 'SANB11', 'ALUP11', 'BPAC11'
  };

  static const Set<String> _knownCryptos = {
    'BTC', 'ETH', 'SOL', 'USDT', 'ADA', 'DOT', 'AVAX', 'LINK'
  };

  static String classify(String ticker) {
    final t = ticker.trim().toUpperCase();
    if (t.isEmpty) return 'OUTROS';

    // 1. ETFs Conhecidos (BR e US)
    if (_knownEtfs.contains(t) || _knownEtfs.contains(t.replaceAll('F', ''))) {
      return 'ETF';
    }

    // 2. Criptomoedas
    if (_knownCryptos.contains(t) || t.endsWith('BRL') || t.endsWith('USDT')) {
      return 'CRYPTO';
    }

    // 3. Stocks EUA e REITs (Heurística de Ticker curto e sem números)
    if (!RegExp(r'\d').hasMatch(t) && t.length <= 5) {
      // REITs conhecidos de 1 a 4 letras
      if (['O', 'AMT', 'PLD', 'VICI', 'PSA', 'STAG', 'DLR', 'EQIX', 'WELL'].contains(t)) {
        return 'REIT';
      }
      return 'STOCK_US';
    }

    // 4. BDRs (34, 35)
    if (RegExp(r'3[45]F?$').hasMatch(t)) return 'BDR';

    // 5. Ativos B3 terminados em 11 (FII ou Unit)
    if (RegExp(r'11F?$').hasMatch(t)) {
      String base = t.endsWith('F') ? t.substring(0, t.length - 1) : t;
      if (_knownUnits.contains(base)) return 'ACAO';
      return 'FII';
    }

    // 6. Ações Brasil (3, 4, 5, 6)
    if (RegExp(r'[3456]F?$').hasMatch(t)) return 'ACAO';

    return 'OUTROS';
  }

  static String getLabel(String type) {
    switch (type) {
      case 'STOCK_US': return 'Ação EUA';
      case 'REIT': return 'REIT (EUA)';
      case 'CRYPTO': return 'Cripto';
      case 'BDR': return 'BDR Global';
      case 'FII': return 'Fundo Imob.';
      case 'ETF': return 'ETF';
      case 'ACAO': return 'Ação BR';
      default: return 'Outros';
    }
  }
}