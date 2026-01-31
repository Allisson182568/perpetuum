import '../cloud_service.dart';

class Insight {
  final String title;
  final String message;
  final String type; // 'DANGER', 'WARNING', 'SUCCESS', 'INFO'

  Insight({required this.title, required this.message, this.type = 'INFO'});
}

class PortfolioBrain {

  /// Analisa a lista de ativos e retorna uma lista de Insights
  static List<Insight> analyze(List<Map<String, dynamic>> assets) {
    List<Insight> insights = [];

    // 1. Verificação de Dados Insuficientes
    if (assets.isEmpty) {
      return [Insight(title: "Sem Dados", message: "Importe seus investimentos para receber análises da IA.", type: 'INFO')];
    }
    if (assets.length < 3) {
      return [Insight(title: "Dados Insuficientes", message: "Adicione mais ativos para que nossa IA possa traçar seu perfil de risco.", type: 'INFO')];
    }

    // Variáveis auxiliares
    double totalValue = 0.0;
    Map<String, double> allocationByType = {};
    Map<String, double> allocationByTicker = {};

    for (var asset in assets) {
      double val = (asset['value'] as num).toDouble(); // O CloudService já calcula value (qtd * preço)
      String type = asset['type'] ?? 'OUTROS';
      String ticker = asset['name'] ?? 'Desconhecido';

      totalValue += val;

      // Agrupamento
      allocationByType[type] = (allocationByType[type] ?? 0) + val;
      allocationByTicker[ticker] = (allocationByTicker[ticker] ?? 0) + val;
    }

    // 2. Análise de Concentração (Risco de Ruína)
    // Regra: Nenhum ativo deve representar mais de 20% do patrimônio (ajustável)
    allocationByTicker.forEach((ticker, value) {
      double percent = value / totalValue;
      if (percent > 0.20) {
        insights.add(Insight(
            title: "Concentração Elevada em $ticker",
            message: "$ticker representa ${(percent * 100).toStringAsFixed(1)}% da sua carteira. Isso aumenta seu risco específico.",
            type: 'DANGER'
        ));
      }
    });

    // 3. Análise de Diversificação de Classe (Radar)
    double acoes = allocationByType['ACAO'] ?? 0;
    double fiis = allocationByType['FII'] ?? 0;
    double stocks = allocationByType['STOCK_US'] ?? 0;

    if (fiis == 0 && acoes > 0) {
      insights.add(Insight(
          title: "Oportunidade em Renda Passiva",
          message: "Você não possui Fundos Imobiliários (FIIs). Considerar FIIs pode aumentar sua renda mensal isenta.",
          type: 'WARNING'
      ));
    }

    if (stocks == 0 && (acoes + fiis) > 10000) { // Só avisa se tiver patrimônio relevante
      insights.add(Insight(
          title: "Exposição ao Risco Brasil",
          message: "100% do seu patrimônio está no Brasil. Considere ativos internacionais (Stocks/BDRs) para proteção cambial.",
          type: 'WARNING'
      ));
    }

    // 4. Análise Comportamental (Holder vs Trader)
    // Essa lógica depende se temos o campo 'date' ou histórico de transações.
    // Assumindo que temos metadados de importação recente:
    // (Lógica simplificada para MVP)
    if (assets.length > 10) {
      insights.add(Insight(
          title: "Diversificação Saudável",
          message: "Parabéns! Sua carteira possui ${assets.length} ativos, o que dilui riscos não sistêmicos.",
          type: 'SUCCESS'
      ));
    }

    return insights;
  }
}