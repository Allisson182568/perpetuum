import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/tax_report_service.dart'; // <--- IMPORTANTE

class TaxReportScreen extends StatefulWidget {
  const TaxReportScreen({Key? key}) : super(key: key);

  @override
  State<TaxReportScreen> createState() => _TaxReportScreenState();
}

class _TaxReportScreenState extends State<TaxReportScreen> with SingleTickerProviderStateMixin {
  final TaxReportService _taxService = TaxReportService(); // <--- INSTÂNCIA DO SERVIÇO
  late TabController _tabController;
  bool _isLoading = true;

  int _selectedYear = DateTime.now().year - 1;
  final List<int> _availableYears = [2022, 2023, 2024, 2025, 2026];

  List<Map<String, dynamic>> _assets = [];
  List<Map<String, dynamic>> _earningsDiv = [];
  List<Map<String, dynamic>> _earningsJcp = [];

  double _totalPatrimonyCost = 0.0;
  double _totalEarningsYear = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReportData();
  }

  // --- HELPER METHODS ---
  double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  String _cleanTicker(String ticker) {
    ticker = ticker.toUpperCase().trim();
    if (ticker.endsWith('F') && ticker.length >= 5) {
      return ticker.substring(0, ticker.length - 1);
    }
    return ticker;
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 1. ATIVOS (Via TaxReportService - Histórico Real)
      // Isso substitui a lógica manual antiga
      List<Map<String, dynamic>> reportAssets = await _taxService.generateAssetsReport(_selectedYear);

      _totalPatrimonyCost = 0.0;
      for (var asset in reportAssets) {
        _totalPatrimonyCost += (asset['total_cost'] as double);
        // Gera o texto aqui na UI
        asset['description_text'] = _generateDescription(asset);
      }
      _assets = reportAssets;

      // 2. PROVENTOS (Mantemos direto do banco pois Earnings já tem data exata)
      final startDate = '$_selectedYear-01-01';
      final endDate = '$_selectedYear-12-31';
      final earningsResponse = await Supabase.instance.client
          .from('earnings')
          .select('ticker, total_value, type, date')
          .eq('user_id', user.id)
          .gte('date', startDate)
          .lte('date', endDate);

      // Processamento de Proventos
      Map<String, double> divMap = {};
      Map<String, double> jcpMap = {};
      _totalEarningsYear = 0.0;

      for (var item in earningsResponse) {
        String t = _cleanTicker(item['ticker'] ?? 'OUTROS');
        double val = _safeDouble(item['total_value']);
        String type = (item['type'] ?? '').toString().toUpperCase();

        if (type == 'DIV' || type == 'RENDIMENTO') {
          divMap[t] = (divMap[t] ?? 0.0) + val;
        } else {
          jcpMap[t] = (jcpMap[t] ?? 0.0) + val;
        }
        _totalEarningsYear += val;
      }

      _earningsDiv = divMap.entries.map((e) => {'ticker': e.key, 'total': e.value, 'type': 'Isentos (Cód 09)'}).toList();
      _earningsDiv.sort((a, b) => b['total'].compareTo(a['total']));

      _earningsJcp = jcpMap.entries.map((e) => {'ticker': e.key, 'total': e.value, 'type': 'Exclusiva (Cód 10)'}).toList();
      _earningsJcp.sort((a, b) => b['total'].compareTo(a['total']));

      setState(() => _isLoading = false);

    } catch (e) {
      debugPrint("ERRO IR: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- TEXTO IRPF ---
  String _generateDescription(Map<String, dynamic> asset) {
    String ticker = asset['ticker'] ?? '';
    String name = asset['name'] ?? '';
    String type = asset['type'] ?? 'OUTROS';
    String cnpj = asset['cnpj'] ?? '';
    String broker = asset['broker'] ?? 'CORRETORA';

    double qty = asset['safe_qty'];
    double pm = asset['safe_pm'];
    double total = asset['total_cost'];

    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    String cnpjText = cnpj.isNotEmpty ? " (CNPJ: $cnpj)" : "";

    if (type == 'STOCK' || type == 'REIT' || type == 'ETF_EUA') {
      return "${qty.toStringAsFixed(4)} AÇÕES DE $ticker ($name) - CUSTÓDIA: $broker (EXTERIOR). CUSTO TOTAL: ${f.format(total)}.";
    }

    String qtyText = qty % 1 == 0 ? qty.toInt().toString() : qty.toString().replaceAll('.', ',');
    String pmFormatted = "R\$ ${pm.toStringAsFixed(2).replaceAll('.', ',')}";

    return "$qtyText AÇÕES/COTAS DE $ticker - $name$cnpjText. CUSTÓDIA: $broker. CUSTO MÉDIO: $pmFormatted. VALOR TOTAL: ${f.format(total)}";
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Copiado!"), backgroundColor: AppTheme.cyanNeon, duration: Duration(milliseconds: 800)),
    );
  }

  void _exportFullReport() {
    StringBuffer sb = StringBuffer();
    sb.writeln("=== RELATÓRIO IRPF $_selectedYear (PERPETUUM) ===");
    sb.writeln("Posição em 31/12/$_selectedYear\n");

    for (var asset in _assets) {
      sb.writeln("BENS E DIREITOS");
      sb.writeln("Discriminação: ${asset['description_text']}");
      sb.writeln("Situação em 31/12: R\$ ${asset['total_cost'].toStringAsFixed(2)}");
      sb.writeln("-----------------------------------");
    }
    _copyToClipboard(sb.toString());
  }

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("Informe de Rendimentos", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.copy_all, color: AppTheme.cyanNeon), onPressed: _exportFullReport, tooltip: "Copiar Tudo"),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              dropdownColor: const Color(0xFF1E1E24),
              value: _selectedYear,
              icon: const Icon(Icons.calendar_today, color: AppTheme.cyanNeon, size: 18),
              style: const TextStyle(color: AppTheme.cyanNeon, fontWeight: FontWeight.bold),
              items: _availableYears.map((int year) => DropdownMenuItem<int>(value: year, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Text(year.toString())))).toList(),
              onChanged: (int? newValue) { if (newValue != null) { setState(() => _selectedYear = newValue); _loadReportData(); }},
            ),
          ),
          const SizedBox(width: 16),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.cyanNeon,
          labelColor: AppTheme.cyanNeon,
          unselectedLabelColor: Colors.white38,
          tabs: const [Tab(text: "Bens e Direitos"), Tab(text: "Rendimentos")],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanNeon))
          : TabBarView(
        controller: _tabController,
        children: [
          // ABA 1
          Column(children: [
            _buildSummaryCard("Patrimônio Total", _totalPatrimonyCost, "Posição em 31/12/$_selectedYear."),
            Expanded(child: _assets.isEmpty ? _buildEmptyState("Nenhum ativo histórico.") : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _assets.length, itemBuilder: (context, index) => _buildAssetTaxCard(_assets[index], moneyFormat))),
          ]),
          // ABA 2
          SingleChildScrollView(child: Column(children: [
            _buildSummaryCard("Total Recebido", _totalEarningsYear, "Dividendos + JCP no ano."),
            if (_earningsDiv.isNotEmpty) ...[_buildSectionTitle("ISENTOS (Cód 09 - Dividendos)"), ..._earningsDiv.map((e) => _buildEarningsCard(e, moneyFormat)).toList()],
            if (_earningsJcp.isNotEmpty) ...[_buildSectionTitle("EXCLUSIVA (Cód 10 - JCP)"), ..._earningsJcp.map((e) => _buildEarningsCard(e, moneyFormat)).toList()],
            if (_earningsDiv.isEmpty && _earningsJcp.isEmpty) _buildEmptyState("Nenhum provento.")
          ])),
        ],
      ),
    );
  }

  // --- WIDGETS ---
  Widget _buildSectionTitle(String title) { return Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(color: AppTheme.cyanNeon, fontWeight: FontWeight.bold, fontSize: 14)))); }
  Widget _buildSummaryCard(String title, double value, String subtitle) { final moneyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$'); return Container(width: double.infinity, margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.cyanNeon.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.3))), child: Column(children: [Text(title, style: const TextStyle(color: Colors.white54)), const SizedBox(height: 4), Text(moneyFormat.format(value), style: const TextStyle(color: AppTheme.cyanNeon, fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center)])); }
  Widget _buildEmptyState(String msg) { return Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text(msg, style: const TextStyle(color: Colors.white38), textAlign: TextAlign.center))); }

  Widget _buildAssetTaxCard(Map<String, dynamic> asset, NumberFormat moneyFormat) {
    bool isZeroCost = asset['total_cost'] == 0.0;
    bool missingCnpj = (asset['cnpj'] == null || asset['cnpj'] == '') && (asset['type'] == 'ACAO' || asset['type'] == 'FII');

    return Container(
      margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1E24), borderRadius: BorderRadius.circular(16), border: Border.all(color: isZeroCost ? Colors.redAccent : (missingCnpj ? Colors.orangeAccent : Colors.white10), width: 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(asset['ticker'].isNotEmpty ? asset['ticker'] : asset['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))), if (missingCnpj) _buildStatusBadge("SEM CNPJ", Colors.orangeAccent, Icons.warning)]),
        if (isZeroCost) const Padding(padding: EdgeInsets.only(top: 8), child: Text("⚠️ Custo R\$ 0.00. Corrija na Auditoria.", style: TextStyle(color: Colors.redAccent, fontSize: 11))),
        const SizedBox(height: 12), const Text("DISCRIMINAÇÃO:", style: TextStyle(color: Colors.white38, fontSize: 10)), const SizedBox(height: 4),
        GestureDetector(onTap: () => _copyToClipboard(asset['description_text']), child: Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.3))), child: Row(children: [Expanded(child: Text(asset['description_text'], style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Courier', height: 1.2))), const SizedBox(width: 8), const Icon(Icons.copy, color: AppTheme.cyanNeon, size: 18)]))),
        const SizedBox(height: 12), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Em 31/12/$_selectedYear:", style: const TextStyle(color: Colors.white54, fontSize: 12)), Text(moneyFormat.format(asset['total_cost']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))])
      ]),
    );
  }

  Widget _buildStatusBadge(String text, Color color, IconData icon) { return Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withOpacity(0.5))), child: Row(children: [Icon(icon, color: color, size: 10), const SizedBox(width: 4), Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold))])); }
  Widget _buildEarningsCard(Map<String, dynamic> item, NumberFormat moneyFormat) { return Container(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.attach_money, color: Colors.greenAccent, size: 16)), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['ticker'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), Text(item['type'], style: const TextStyle(color: Colors.white38, fontSize: 10))])]), Text(moneyFormat.format(item['total']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))])); }
}