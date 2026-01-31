import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart'; // Seu tema

class StockDividendsList extends StatefulWidget {
  final String ticker; // ex: "ITUB4"

  const StockDividendsList({Key? key, required this.ticker}) : super(key: key);

  @override
  State<StockDividendsList> createState() => _StockDividendsListState();
}

class _StockDividendsListState extends State<StockDividendsList> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _dividends = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    // Tratamento do símbolo
    String symbol = widget.ticker.toUpperCase();
    if (!symbol.endsWith('.SA')) symbol += '.SA';

    try {
      // Usando o pacote para pegar dados
      // O YahooReader geralmente traz o histórico de preços.
      // Para dividendos específicos, o pacote 'yahoo_finance_data_reader'
      // pode não ter um método explícito 'getDividends' na versão padrão.

      // TRUQUE: Se o pacote não tiver, usamos a lógica de HTTP direto aqui mesmo
      // Se preferir, instale o pacote 'http' no pubspec.yaml

      // Exemplo Mockado (para você ver funcionando visualmente enquanto não instala o 'http')
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          // Dados REAIS viriam da API. Aqui simulo o formato que você pediu.
          _dividends = [
            {'data': DateTime(2025, 12, 01), 'valor': 0.8543},
            {'data': DateTime(2025, 08, 15), 'valor': 0.2310},
            {'data': DateTime(2025, 05, 20), 'valor': 1.1000},
          ];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: AppTheme.cyanNeon));

    if (_dividends.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text("Nenhum dividendo encontrado ou erro na API.", style: TextStyle(color: Colors.white54)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text("Histórico de Proventos", style: AppTheme.titleStyle.copyWith(fontSize: 16)),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _dividends.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
          itemBuilder: (context, index) {
            final item = _dividends[index];
            return ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle
                ),
                child: const Icon(Icons.attach_money, color: Colors.greenAccent, size: 20),
              ),
              title: Text(
                DateFormat('dd/MM/yyyy').format(item['data']),
                style: const TextStyle(color: Colors.white),
              ),
              trailing: Text(
                "R\$ ${item['valor'].toStringAsFixed(4)}",
                style: const TextStyle(color: AppTheme.cyanNeon, fontWeight: FontWeight.bold),
              ),
            );
          },
        ),
      ],
    );
  }
}