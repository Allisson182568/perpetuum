import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cloud_service.dart';
import '../theme.dart';

class PortfolioAuditorScreen extends StatefulWidget {
  const PortfolioAuditorScreen({Key? key}) : super(key: key);

  @override
  State<PortfolioAuditorScreen> createState() => _PortfolioAuditorScreenState();
}

class _PortfolioAuditorScreenState extends State<PortfolioAuditorScreen> with SingleTickerProviderStateMixin {
  final CloudService _cloud = CloudService();
  late TabController _tabController;

  bool _isLoading = true;
  bool _showAllAssets = false;
  bool _isGrouped = true;

  // Listas
  List<Map<String, dynamic>> _allAssetsRaw = [];
  List<Map<String, dynamic>> _regularAssets = [];
  List<Map<String, dynamic>> _divergentAssets = [];

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('assets')
          .select()
          .eq('user_id', user.id)
          .order('ticker', ascending: true);

      if (mounted) {
        setState(() {
          _allAssetsRaw = List<Map<String, dynamic>>.from(response);
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro auditoria: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    String query = _searchController.text.toLowerCase();

    var tempFlat = _allAssetsRaw.where((asset) {
      bool isAudited = asset['is_audited'] == true;
      if (!_showAllAssets && isAudited) return false;

      String ticker = (asset['ticker'] ?? '').toString().toLowerCase();
      String name = (asset['name'] ?? '').toString().toLowerCase();
      if (query.isEmpty) return true;
      return ticker.contains(query) || name.contains(query);
    }).toList();

    List<Map<String, dynamic>> processedList;

    if (_isGrouped) {
      processedList = _groupAssetsByTicker(tempFlat);
    } else {
      processedList = tempFlat;
    }

    _regularAssets = [];
    _divergentAssets = [];

    for (var asset in processedList) {
      double qty = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
      double pm = (asset['purchase_price'] as num?)?.toDouble() ?? 0.0;

      bool isNegative = qty < 0;
      bool isZeroPrice = qty > 0 && pm <= 0.01;
      bool isUnknown = (asset['ticker'] == 'DESC' || asset['ticker'] == null);

      if (isNegative || isZeroPrice || isUnknown) {
        _divergentAssets.add(asset);
      } else {
        _regularAssets.add(asset);
      }
    }

    _regularAssets.sort((a, b) => (a['is_audited'] == true ? 1 : 0).compareTo(b['is_audited'] == true ? 1 : 0));
  }

  List<Map<String, dynamic>> _groupAssetsByTicker(List<Map<String, dynamic>> flatList) {
    Map<String, Map<String, dynamic>> groups = {};

    for (var item in flatList) {
      String ticker = item['ticker'] ?? item['name'] ?? 'DESC';

      if (!groups.containsKey(ticker)) {
        groups[ticker] = {
          'id_list': <dynamic>[],
          'ticker': ticker,
          'name': item['name'],
          'type': item['type'],
          'quantity': 0.0,
          'value': 0.0,
          'purchase_price': 0.0,
          'current_price': item['current_price'],
          'is_audited': true,
          'count_rows': 0,
        };
      }

      var g = groups[ticker]!;
      double qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      double price = (item['purchase_price'] as num?)?.toDouble() ?? 0.0;
      double total = (item['value'] as num?)?.toDouble() ?? (qty * price);

      double oldQty = g['quantity'];
      double oldTotalCost = oldQty * g['purchase_price'];
      double newTotalCost = oldTotalCost + (qty * price);
      double newQty = oldQty + qty;

      g['quantity'] = newQty;
      g['value'] = (g['value'] as double) + total;

      if (newQty.abs() > 0.0001) {
        g['purchase_price'] = newTotalCost / newQty;
      } else {
        g['purchase_price'] = 0.0;
      }

      g['count_rows'] = (g['count_rows'] as int) + 1;
      (g['id_list'] as List).add(item['id']);

      if (item['is_audited'] == false) g['is_audited'] = false;
    }
    return groups.values.toList();
  }

  void _toggleGroupMode() { setState(() { _isGrouped = !_isGrouped; _applyFilters(); }); }
  void _toggleFilter() { setState(() { _showAllAssets = !_showAllAssets; _applyFilters(); }); }

  // --- LÓGICA DE VENDA (RESTAURADA) ---

  String _calculateTaxImplication(String type, double profit, double totalSaleValue) {
    if (profit < 0) return "Prejuízo de ${_formatMoney(profit.abs())} registrado para abater no futuro.";

    switch (type) {
      case 'ACAO':
      case 'STOCK': // Tratamento simplificado
        if (totalSaleValue < 20000 && type == 'ACAO') return "Lucro de ${_formatMoney(profit)} ISENTO (Vendas < 20k).";
        return "Lucro Tributável! DARF estimado: ${_formatMoney(profit * 0.15)} (15%).";
      case 'FII':
        return "Lucro FII Tributável! DARF estimado: ${_formatMoney(profit * 0.20)} (20%).";
      case 'CRIPTO':
        if (totalSaleValue < 35000) return "Lucro Cripto ISENTO (Vendas < 35k).";
        return "Lucro Cripto Tributável! DARF estimado: ${_formatMoney(profit * 0.15)} (15%).";
      default:
        return "Lucro registrado: ${_formatMoney(profit)}.";
    }
  }

  Future<void> _processSmartSale(Map<String, dynamic> asset, String qtyStr, String priceStr, DateTime saleDate) async {
    Navigator.pop(context);
    setState(() => _isLoading = true);

    try {
      double currentHolding = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
      double avgPrice = (asset['purchase_price'] as num?)?.toDouble() ?? 0.0;

      String ticker = asset['ticker'] ?? asset['name'];
      String type = asset['type'] ?? 'OUTROS';

      double qtyToSell = double.tryParse(qtyStr.replaceAll(',', '.')) ?? 0;
      double salePrice = double.tryParse(priceStr.replaceAll(',', '.')) ?? 0;

      // Cálculo Fiscal
      double totalSaleValue = qtyToSell * salePrice;
      double totalCost = qtyToSell * avgPrice;
      double profit = totalSaleValue - totalCost;
      String taxAlert = _calculateTaxImplication(type, profit, totalSaleValue);

      // Registra Venda
      await _cloud.registerTransaction(
          ticker: ticker,
          name: asset['name'],
          assetType: type,
          operationType: 'V',
          quantity: qtyToSell,
          unitPrice: salePrice,
          date: saleDate,
          //notes: "Venda Manual Auditor"
      );

      _loadData();
      _showFiscalFeedbackDialog(ticker, profit, taxAlert);

    } catch (e) {
      setState(() => _isLoading = false);
      _showCustomToast("Erro venda: $e", isError: true);
    }
  }

  void _showSaleDialog(Map<String, dynamic> asset) {
    final qtyController = TextEditingController();
    final priceController = TextEditingController();
    final dateController = TextEditingController();

    DateTime selectedDate = DateTime.now();

    double q = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
    double p = (asset['current_price'] as num?)?.toDouble() ?? 0.0;

    qtyController.text = q.toString();
    priceController.text = p.toString();
    dateController.text = DateFormat('dd/MM/yyyy').format(selectedDate);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> _pickDate() async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
                builder: (context, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppTheme.cyanNeon, onPrimary: Colors.black, surface: Color(0xFF1E1E24))), child: child!),
              );
              if (picked != null) {
                setStateDialog(() { selectedDate = picked; dateController.text = DateFormat('dd/MM/yyyy').format(picked); });
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [Icon(Icons.remove_circle, color: Colors.redAccent), SizedBox(width: 10), Text("Baixa (Venda)", style: TextStyle(color: Colors.white, fontSize: 18))]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Informe a venda para abater do saldo e calcular IR.", style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _pickDate,
                    child: AbsorbPointer(child: TextField(controller: dateController, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: "Data da Venda", suffixIcon: const Icon(Icons.calendar_today, color: AppTheme.cyanNeon, size: 20), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))), focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.cyanNeon))))),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(qtyController, "Quantidade Vendida"),
                  const SizedBox(height: 12),
                  _buildTextField(priceController, "Preço da Venda (Unitário)"),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => _processSmartSale(asset, qtyController.text, priceController.text, selectedDate), child: const Text("Confirmar Baixa", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ],
            );
          },
        );
      },
    );
  }

  void _showFiscalFeedbackDialog(String ticker, double profit, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: Row(children: [
          Icon(profit >= 0 ? Icons.trending_up : Icons.trending_down, color: profit >= 0 ? Colors.greenAccent : Colors.redAccent),
          const SizedBox(width: 10),
          const Text("Resumo Fiscal", style: TextStyle(color: Colors.white))
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Venda de $ticker registrada.", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
              child: Text(msg, style: TextStyle(color: profit >= 0 ? AppTheme.cyanNeon : Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  // --- OUTRAS AÇÕES (AJUSTE / VALIDAR / EXCLUIR) ---

  Future<void> _processAdjustment(Map<String, dynamic> asset, String realQtyStr, String realPmStr) async {
    if (realQtyStr.isEmpty || realPmStr.isEmpty) return;
    Navigator.pop(context);
    setState(() => _isLoading = true);

    try {
      double currentQty = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
      double currentPm = (asset['purchase_price'] as num?)?.toDouble() ?? 0.0;
      double currentTotalCost = currentPm * currentQty;

      double targetQty = double.tryParse(realQtyStr.replaceAll(',', '.')) ?? currentQty;
      double targetPm = double.tryParse(realPmStr.replaceAll(',', '.')) ?? currentPm;
      double targetTotalCost = targetQty * targetPm;

      double qtyDiff = targetQty - currentQty;
      double costDiff = targetTotalCost - currentTotalCost;

      String ticker = asset['ticker'] ?? asset['name'];
      String operation = qtyDiff >= 0 ? 'C' : 'V';
      double unitPrice = 0.0;

      if (qtyDiff.abs() > 0) {
        unitPrice = (costDiff / qtyDiff).abs();
      }
      if (unitPrice.isNaN || unitPrice.isInfinite) unitPrice = 0;

      await _cloud.registerTransaction(
          ticker: ticker,
          name: asset['name'],
          assetType: asset['type'],
          operationType: operation,
          quantity: qtyDiff.abs(),
          unitPrice: unitPrice,
          date: DateTime.now(),
          //notes: "Correção Manual"
      );

      _loadData();
      _showCustomToast("Corrigido! Saldo atualizado para $targetQty", isSuccess: true);

    } catch (e) {
      setState(() => _isLoading = false);
      _showCustomToast("Erro: $e", isError: true);
    }
  }

  void _showAdjustmentDialog(Map<String, dynamic> asset, {bool isDivergence = false}) {
    final qtyController = TextEditingController();
    final pmController = TextEditingController();

    double q = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
    double p = (asset['purchase_price'] as num?)?.toDouble() ?? 0.0;

    qtyController.text = q.toString();
    pmController.text = p.abs().toStringAsFixed(2);

    String title = isDivergence ? "Corrigir Divergência" : "Sincronia (IR)";
    Color color = isDivergence ? Colors.orangeAccent : AppTheme.cyanNeon;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [Icon(Icons.build_circle, color: color), SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)))]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDivergence)
              Container(margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Text("Informe o saldo REAL da sua corretora para corrigir este ativo.", style: TextStyle(color: Colors.orangeAccent, fontSize: 11))),
            _buildTextField(qtyController, "Quantidade Real (Corretora)"),
            const SizedBox(height: 12),
            _buildTextField(pmController, "Preço Médio Real"),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color), onPressed: () => _processAdjustment(asset, qtyController.text, pmController.text), child: const Text("Salvar Correção", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  void _askToConfirmValidation(Map<String, dynamic> item) {
    String ticker = item['ticker'];
    bool isGroup = _isGrouped && (item['count_rows'] ?? 1) > 1;
    String msg = isGroup ? "Isso validará TODAS as ${item['count_rows']} ordens de $ticker.\n\nConfirma?" : "Confirma que o saldo de $ticker está correto?";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.check_circle_outline, color: Color(0xFF10B981)), SizedBox(width: 10), Text("Validar?", style: TextStyle(color: Colors.white, fontSize: 18))]),
        content: Text(msg, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)), onPressed: () { Navigator.pop(context); _executeConfirmAsset(item); }, child: const Text("Confirmar", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Future<void> _executeConfirmAsset(Map<String, dynamic> item) async {
    setState(() => _isLoading = true);
    try {
      List<dynamic> idsToUpdate = [];
      if (_isGrouped && item['id_list'] != null) idsToUpdate = item['id_list']; else idsToUpdate = [item['id']];
      await Supabase.instance.client.from('assets').update({'is_audited': true, 'last_audit_date': DateTime.now().toIso8601String()}).inFilter('id', idsToUpdate);
      _loadData();
      setState(() => _isLoading = false);
      _showCustomToast("Validado!", isSuccess: true);
    } catch (e) { setState(() => _isLoading = false); _showCustomToast("Erro: $e", isError: true); }
  }

  Future<void> _processHardDelete(Map<String, dynamic> asset) async {
    setState(() => _isLoading = true);
    try {
      List<dynamic> idsToDelete = [];
      if (_isGrouped && asset['id_list'] != null) idsToDelete = asset['id_list']; else idsToDelete = [asset['id']];
      await Supabase.instance.client.from('assets').delete().inFilter('id', idsToDelete);
      _loadData();
      _showCustomToast("Excluído com sucesso.", isSuccess: true);
    } catch (e) { setState(() => _isLoading = false); _showCustomToast("Erro: $e", isError: true); }
  }

  void _askToHardDelete(Map<String, dynamic> asset) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Row(children: [Icon(Icons.delete_forever, color: Colors.redAccent), SizedBox(width: 10), Text("Excluir?", style: TextStyle(color: Colors.white, fontSize: 18))]),
        content: const Text("Isso apagará este registro do banco permanentemente.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () async { Navigator.pop(context); await _processHardDelete(asset); }, child: const Text("Excluir", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("Auditoria Inteligente", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: Icon(_isGrouped ? Icons.layers : Icons.list, color: AppTheme.cyanNeon), onPressed: _toggleGroupMode),
          IconButton(icon: Icon(_showAllAssets ? Icons.visibility : Icons.visibility_off, color: _showAllAssets ? AppTheme.cyanNeon : Colors.white38), onPressed: _toggleFilter),
          IconButton(icon: const Icon(Icons.refresh, color: AppTheme.cyanNeon), onPressed: _loadData)
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.cyanNeon, labelColor: AppTheme.cyanNeon, unselectedLabelColor: Colors.white38,
          tabs: [
            const Tab(text: "Ativos Regulares"),
            Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text("Divergências"), if (_divergentAssets.isNotEmpty) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)), child: Text("${_divergentAssets.length}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))])),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanNeon))
          : Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: TextField(controller: _searchController, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: "Buscar ativo...", hintStyle: const TextStyle(color: Colors.white38), prefixIcon: const Icon(Icons.search, color: AppTheme.cyanNeon), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)))),
        Expanded(child: TabBarView(controller: _tabController, children: [
          _regularAssets.isEmpty ? _buildEmptyState("Tudo certo por aqui!") : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _regularAssets.length, itemBuilder: (ctx, i) => _buildAuditorCard(_regularAssets[i])),
          _divergentAssets.isEmpty ? _buildEmptyState("Sem divergências.", icon: Icons.thumb_up) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _divergentAssets.length, itemBuilder: (ctx, i) => _buildDivergenceCard(_divergentAssets[i])),
        ])),
      ]),
    );
  }

  Widget _buildAuditorCard(Map<String, dynamic> asset) {
    String title = asset['ticker'] ?? asset['name'];
    double qty = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
    double pm = (asset['purchase_price'] as num?)?.toDouble() ?? 0.0;
    double total = (asset['value'] as num?)?.toDouble() ?? (qty * pm);
    bool isAudited = asset['is_audited'] == true;
    int count = asset['count_rows'] ?? 1;
    bool isGroup = _isGrouped && count > 1;

    IconData typeIcon = Icons.show_chart;
    if (asset['type'] == 'CRIPTO') typeIcon = Icons.currency_bitcoin;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: isGroup ? const Color(0xFF1E1E24).withOpacity(0.8) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: isAudited ? const Color(0xFF10B981).withOpacity(0.3) : Colors.white.withOpacity(0.1))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [if (isGroup) Padding(padding: const EdgeInsets.only(right:6), child: Icon(Icons.layers, color: AppTheme.cyanNeon, size: 16)), Icon(typeIcon, color: Colors.white54, size: 16), const SizedBox(width: 8), Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), if (isGroup) Container(margin: const EdgeInsets.only(left:8), padding: const EdgeInsets.symmetric(horizontal:6, vertical:2), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)), child: Text("$count ordens", style: const TextStyle(color: Colors.white54, fontSize: 9))), if (isAudited && !isGroup) const Padding(padding: EdgeInsets.only(left:8), child: Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14))]),
            const SizedBox(height: 4), Text("${_formatNumber(qty)} un. | PM: ${_formatMoney(pm)}", style: const TextStyle(color: Colors.white54, fontSize: 12))
          ])),
          Text(_formatMoney(total), style: const TextStyle(color: AppTheme.cyanNeon, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 12), const Divider(color: Colors.white10), const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _buildActionButton(Icons.check_circle_outline, "Validar", const Color(0xFF10B981), () => _askToConfirmValidation(asset)),
          _buildActionButton(Icons.balance, "Sincronizar", Colors.orangeAccent, () => _showAdjustmentDialog(asset)),
          _buildActionButton(Icons.remove_circle_outline, "Vendi", Colors.redAccent, () => _showSaleDialog(asset)), // <--- BOTÃO VENDI DE VOLTA
          _buildActionButton(Icons.delete_forever, "Excluir", Colors.white38, () => _askToHardDelete(asset)),
        ])
      ]),
    );
  }

  Widget _buildDivergenceCard(Map<String, dynamic> asset) {
    String title = asset['ticker'] ?? asset['name'];
    double qty = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
    double pm = (asset['purchase_price'] as num?)?.toDouble() ?? 0.0;
    String issue = qty < 0 ? "Saldo Negativo (Venda > Compra)" : (pm <= 0.01 ? "Custo Zero (Bonificação?)" : "Inconsistente");

    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.redAccent.withOpacity(0.3))),
      child: Column(children: [
        Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Text("GAP DETECTADO", style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Problema: $issue", style: const TextStyle(color: Colors.white70, fontSize: 12)), const SizedBox(height: 4), Text("Saldo Atual no App: ${_formatNumber(qty)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), Text("Preço Médio Atual: ${_formatMoney(pm)}", style: const TextStyle(color: Colors.white54, fontSize: 12))])),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent), onPressed: () => _showAdjustmentDialog(asset, isDivergence: true), icon: const Icon(Icons.build, color: Colors.black, size: 18), label: const Text("CORRIGIR DIVERGÊNCIA", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))))
      ]),
    );
  }

  void _showCustomToast(String message, {bool isError = false, bool isSuccess = false}) {
    Color color = AppTheme.cyanNeon; IconData icon = Icons.info_outline;
    if (isError) { color = Colors.redAccent; icon = Icons.error_outline; } else if (isSuccess) { color = const Color(0xFF10B981); icon = Icons.check_circle_outline; }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.transparent, elevation: 0, behavior: SnackBarBehavior.floating, duration: const Duration(milliseconds: 3000), content: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: const Color(0xFF1E1E24), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.5), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]), child: Row(children: [Icon(icon, color: color, size: 24), const SizedBox(width: 12), Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)))]))));
  }
  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) { return Material(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), splashColor: color.withOpacity(0.3), highlightColor: color.withOpacity(0.1), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 20), const SizedBox(height: 4), Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold))])))); }
  Widget _buildEmptyState(String msg, {IconData icon = Icons.check_rounded}) { return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle), child: Icon(icon, color: Colors.white24, size: 50)), const SizedBox(height: 24), Text(msg, style: const TextStyle(color: Colors.white54, fontSize: 16))])); }
  Widget _buildTextField(TextEditingController c, String l) { return TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: l, labelStyle: const TextStyle(color: Colors.white38, fontSize: 12), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))), focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.cyanNeon)))); }
  String _formatMoney(double v) => NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(v);
  String _formatNumber(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(4);
}