import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../../services/ai/asset_classifier.dart';

class ImportReviewDialog extends StatefulWidget {
  final List<Map<String, dynamic>> assets;
  final String fileName;

  // ATENÇÃO: Mudou para Future<bool>
  final Future<bool> Function(List<Map<String, dynamic>>) onConfirm;

  const ImportReviewDialog({
    Key? key,
    required this.assets,
    required this.fileName,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<ImportReviewDialog> createState() => _ImportReviewDialogState();
}

class _ImportReviewDialogState extends State<ImportReviewDialog> {
  late List<Map<String, TextEditingController>> _ctrls;
  bool _saving = false; // Controla o spinner do botão

  @override
  void initState() {
    super.initState();
    _ctrls = widget.assets.map((a) => {
      'ticker': TextEditingController(text: a['ticker'] ?? ''),
      'qty': TextEditingController(text: a['qty']?.toString() ?? '0'),
      'price': TextEditingController(text: (a['price'] as num?)?.toStringAsFixed(2) ?? '0.00'),
      'type': TextEditingController(text: a['type'] ?? 'C'),
      'date': TextEditingController(text: a['date'] ?? ''), // Pode vir "19/05/2020"
      'broker': TextEditingController(text: a['broker'] ?? ''),
      'asset_type': TextEditingController(text: a['asset_type'] ?? 'OUTROS'),
      'cnpj': TextEditingController(text: a['cnpj'] ?? ''),
      'is_earning': TextEditingController(text: (a['is_earning'] == true).toString()),
      'original_desc': TextEditingController(text: a['enrichment']?['original_desc'] ?? ''),
    }).toList();
  }

  double _getRowTotal(int index) {
    try {
      String qText = _ctrls[index]['qty']!.text.replaceAll(',', '.');
      String pText = _ctrls[index]['price']!.text.replaceAll(',', '.');
      return (double.tryParse(qText) ?? 0) * (double.tryParse(pText) ?? 0);
    } catch (_) {
      return 0.0;
    }
  }

  void _addNewLine() {
    setState(() {
      _ctrls.add({
        'ticker': TextEditingController(),
        'qty': TextEditingController(text: '0'),
        'price': TextEditingController(text: '0.00'),
        'type': TextEditingController(text: 'C'),
        'date': TextEditingController(text: DateFormat('dd/MM/yyyy').format(DateTime.now())),
        'broker': TextEditingController(),
        'asset_type': TextEditingController(text: 'OUTROS'),
        'cnpj': TextEditingController(),
        'is_earning': TextEditingController(text: 'false'),
        'original_desc': TextEditingController(),
      });
    });
  }

  Widget _buildDashboard() {
    double totalBuy = 0;
    double totalSell = 0;
    Map<String, double> weightMap = {};
    DateTime? minD;
    DateTime? maxD;

    for (int i = 0; i < _ctrls.length; i++) {
      double rV = _getRowTotal(i);
      String t = _ctrls[i]['ticker']!.text.toUpperCase();

      if (_ctrls[i]['type']!.text == 'C') totalBuy += rV;
      else if (_ctrls[i]['type']!.text == 'V') totalSell += rV;

      if (t.isNotEmpty) weightMap[t] = (weightMap[t] ?? 0) + rV;

      try {
        String dText = _ctrls[i]['date']!.text;
        // Tenta parsear para mostrar no painel
        if (dText.contains('/')) {
          List<String> p = dText.split('/');
          if (p.length == 3) {
            DateTime d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
            if (minD == null || d.isBefore(minD)) minD = d;
            if (maxD == null || d.isAfter(maxD)) maxD = d;
          }
        }
      } catch (_) {}
    }

    String maxW = "-";
    double maxWV = -1;
    weightMap.forEach((k, v) { if (v > maxWV) { maxWV = v; maxW = k; } });

    String periodText = minD != null && maxD != null
        ? "${DateFormat('dd/MM/yy').format(minD)} a ${DateFormat('dd/MM/yy').format(maxD)}"
        : "N/A";

    final money = NumberFormat.compactCurrency(locale: 'pt_BR', symbol: 'R\$');

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.cyanNeon.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoCol("TOTAL LÍQUIDO", totalBuy - totalSell, AppTheme.cyanNeon, money),
              _infoCol("PERÍODO", 0, Colors.white, null, text: periodText),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Colors.white10, height: 1)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoCol("COMPRAS", totalBuy, Colors.greenAccent, money),
              _infoCol("VENDAS", totalSell, Colors.redAccent, money),
              _infoCol("MAIOR MOV.", 0, Colors.orangeAccent, null, text: maxW),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCol(String label, double val, Color color, NumberFormat? fmt, {String? text}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(text ?? fmt!.format(val), style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.maxFinite,
        height: 700,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Revisão (${widget.fileName})", style: AppTheme.titleStyle.copyWith(fontSize: 16)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 10),
            _buildDashboard(),
            Expanded(
              child: ListView.builder(
                itemCount: _ctrls.length,
                itemBuilder: (ctx, i) {
                  final isBuy = _ctrls[i]['type']!.text == 'C';
                  final isEarning = _ctrls[i]['is_earning']!.text == 'true';
                  final color = isEarning ? Colors.yellowAccent : (isBuy ? Colors.greenAccent : Colors.redAccent);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: color, width: 4)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(flex: 2, child: _buildField("Ticker", _ctrls[i]['ticker']!)),
                            const SizedBox(width: 8),
                            if (!isEarning)
                              GestureDetector(
                                onTap: () => setState(() => _ctrls[i]['type']!.text = isBuy ? 'V' : 'C'),
                                child: Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(isBuy ? 'C' : 'V', style: TextStyle(color: color, fontWeight: FontWeight.bold))),
                              ),
                            const SizedBox(width: 8),
                            Expanded(flex: 3, child: _buildField("Data", _ctrls[i]['date']!)),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: () => setState(() => _ctrls.removeAt(i))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildField(isEarning ? "--" : "Qtd", _ctrls[i]['qty']!, isNumber: true)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildField(isEarning ? "Total" : "Preço", _ctrls[i]['price']!, isNumber: true)),
                            const SizedBox(width: 12),
                            Text(NumberFormat.compactCurrency(locale: 'pt_BR', symbol: 'R\$').format(_getRowTotal(i)), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(onPressed: _addNewLine, icon: const Icon(Icons.add, color: Colors.white70), label: const Text("Nova Linha")),
                ElevatedButton(
                  onPressed: _saving ? null : _onSave,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cyanNeon),
                  child: _saving ? const CircularProgressIndicator(color: Colors.black) : const Text("CONFIRMAR E SALVAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {bool isNumber = false}) => TextField(
    controller: ctrl,
    keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    onChanged: (_) => setState((){}),
    style: const TextStyle(color: Colors.white, fontSize: 12),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
      isDense: true, filled: true, fillColor: Colors.black26,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    ),
  );

  // --- AQUI ESTAVA O PROBLEMA DO "SO RODANDO" ---
  Future<void> _onSave() async {
    setState(() => _saving = true);

    // 1. Prepara os dados
    List<Map<String, dynamic>> finalData = [];
    for (var c in _ctrls) {
      String t = c['ticker']!.text;
      if (t.isEmpty) continue;

      String aType = c['asset_type']!.text;
      if (aType.isEmpty || aType == 'OUTROS') aType = AssetClassifier.classify(t);

      finalData.add({
        'ticker': t,
        'qty': double.tryParse(c['qty']!.text.replaceAll(',', '.')) ?? 0,
        'price': double.tryParse(c['price']!.text.replaceAll(',', '.')) ?? 0,
        'type': c['type']!.text,
        'date': c['date']!.text,
        'broker': c['broker']!.text,
        'asset_type': aType,
        'cnpj': c['cnpj']!.text,
        'is_earning': c['is_earning']!.text == 'true',
        'enrichment': {'original_desc': c['original_desc']!.text}
      });
    }

    // 2. Chama a tela pai e ESPERA O RESULTADO
    bool success = await widget.onConfirm(finalData);

    // 3. Se deu sucesso, fecha o dialog
    if (success) {
      if (mounted) Navigator.pop(context);
    } else {
      // 4. Se deu erro, PARA DE RODAR e deixa o usuário tentar de novo
      if (mounted) {
        setState(() => _saving = false);
        // O erro já foi mostrado via Toast na tela pai
      }
    }
  }
}