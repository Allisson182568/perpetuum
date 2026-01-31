import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';

// --- CONSTANTES ---
const String kClassPrefix = 'CLASS_'; // Prefixo para identificar metas de classe no banco

// --- MODELOS DE DADOS ---

class AssetItem {
  String ticker;
  double currentPrice;
  double quantity;
  double currentTotalValue;
  double targetInsideClass; // 0-100% (Relativo à classe)

  AssetItem({
    required this.ticker,
    required this.currentPrice,
    required this.quantity,
    required this.currentTotalValue,
    this.targetInsideClass = 0.0,
  });
}

class AssetClassGroup {
  String id;
  String displayName;
  List<AssetItem> assets;
  double currentTotalValue;
  double targetPercentOfPortfolio; // A Meta da Classe (Salva explicitamente)

  AssetClassGroup({
    required this.id,
    required this.displayName,
    required this.assets,
    this.currentTotalValue = 0.0,
    this.targetPercentOfPortfolio = 0.0,
  });

  AssetItem? get largestAsset {
    if (assets.isEmpty) return null;
    return assets.reduce((a, b) => a.currentTotalValue > b.currentTotalValue ? a : b);
  }
}

class RebalanceScreen extends StatefulWidget {
  const RebalanceScreen({Key? key}) : super(key: key);

  @override
  State<RebalanceScreen> createState() => _RebalanceScreenState();
}

class _RebalanceScreenState extends State<RebalanceScreen> {
  bool _isLoading = true;
  List<AssetClassGroup> _classes = [];
  double _totalPortfolioValue = 0.0;
  double _totalAllocationCheck = 0.0;

  final Map<String, String> _classDefinitions = {
    'ACAO': 'Ações Brasil',
    'STOCK': 'Exterior (Stocks/REITs)',
    'FII': 'Fundos Imobiliários',
    'R_FIXA': 'Renda Fixa',
    'CRIPTO': 'Criptomoedas',
    'OUTROS': 'Outros',
  };

  @override
  void initState() {
    super.initState();
    _initializeGroups();
    _loadData();
  }

  void _initializeGroups() {
    _classes = _classDefinitions.entries.map((e) => AssetClassGroup(
      id: e.key,
      displayName: e.value,
      assets: [],
    )).toList();
  }

  String _mapTypeToGroup(String rawType, String ticker) {
    rawType = rawType.toUpperCase().trim();
    ticker = ticker.toUpperCase().trim();

    if (ticker.contains('TESOURO') || ticker.contains('IPCA') || ticker.contains('SELIC') || ticker.contains('CDB') || ticker.contains('LCI') || ticker.contains('LCA')) return 'R_FIXA';
    if (ticker == 'BTC' || ticker == 'ETH' || ticker.contains('BITCOIN')) return 'CRIPTO';
    if (ticker.endsWith('34') || ticker.endsWith('39') || ['IVVB11', 'WRLD11', 'NASD11', 'EURP11'].contains(ticker)) return 'STOCK';

    if (rawType.contains('STOCK') || rawType.contains('REIT') || rawType.contains('BDR') || rawType.contains('EXTERIOR') || rawType.contains('EUA')) return 'STOCK';
    if (rawType.contains('TESOURO') || rawType.contains('FIXA') || rawType.contains('FIXED') || rawType.contains('CDB')) return 'R_FIXA';
    if (rawType.contains('FII') || rawType.contains('REAL_ESTATE') || rawType.contains('IMOBILIARIO')) return 'FII';
    if (rawType.contains('CRIPTO') || rawType.contains('COIN')) return 'CRIPTO';
    if (rawType.contains('ACAO') || rawType.contains('ACOES') || rawType.contains('BR_STOCK')) return 'ACAO';

    return 'OUTROS';
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) { Navigator.pop(context); return; }

    try {
      // 1. Busca Dados
      final assetsResponse = await Supabase.instance.client.from('assets').select().eq('user_id', user.id);
      final targetsResponse = await Supabase.instance.client.from('asset_targets').select().eq('user_id', user.id);

      // 2. Separa Metas: De Classe vs De Ativos
      Map<String, double> assetGlobalTargets = {}; // Ex: BTC -> 2.0
      Map<String, double> classTargets = {};       // Ex: CLASS_CRIPTO -> 5.0

      for (var t in targetsResponse) {
        if (t['ticker'] != null) {
          String key = t['ticker'].toString().toUpperCase().trim();
          double val = (t['target_percent'] as num?)?.toDouble() ?? 0.0;

          if (key.startsWith(kClassPrefix)) {
            // É uma meta de CLASSE (Ex: CLASS_CRIPTO)
            String classId = key.replaceFirst(kClassPrefix, '');
            classTargets[classId] = val;
          } else {
            // É uma meta de ATIVO (Ex: BTC)
            assetGlobalTargets[key] = val;
          }
        }
      }

      // 3. Reseta e Aplica Metas de Classe
      _totalPortfolioValue = 0.0;
      for (var group in _classes) {
        group.assets.clear();
        group.currentTotalValue = 0.0;
        // AQUI ESTÁ A MÁGICA: Carregamos a meta da classe direto do banco!
        group.targetPercentOfPortfolio = classTargets[group.id] ?? 0.0;
      }

      Set<String> processedTickers = {};

      // 4. Processa Ativos Reais (Carteira)
      for (var asset in assetsResponse) {
        String ticker = asset['ticker'].toString().toUpperCase().trim();
        String rawType = asset['type']?.toString() ?? 'OUTROS';

        if (rawType.toUpperCase().contains('ACAO') && ticker.endsWith('F') && ticker.length > 4) {
          ticker = ticker.substring(0, ticker.length - 1);
        }

        String groupId = _mapTypeToGroup(rawType, ticker);
        double price = (asset['current_price'] as num?)?.toDouble() ?? (asset['purchase_price'] as num?)?.toDouble() ?? 0.0;
        double qty = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
        double val = price * qty;

        _totalPortfolioValue += val;

        var group = _classes.firstWhere((g) => g.id == groupId, orElse: () => _classes.last);

        var idx = group.assets.indexWhere((a) => a.ticker == ticker);
        processedTickers.add(ticker);

        if (idx >= 0) {
          group.assets[idx].quantity += qty;
          group.assets[idx].currentTotalValue += val;
        } else {
          // Calcula a % interna baseada na global salva
          double globalT = assetGlobalTargets[ticker] ?? 0.0;
          double internalT = 0.0;

          // Se a classe tem meta > 0, calculamos a relativa. Se não, é 0.
          if (group.targetPercentOfPortfolio > 0) {
            internalT = (globalT / group.targetPercentOfPortfolio) * 100;
          }

          group.assets.add(AssetItem(
            ticker: ticker,
            currentPrice: price,
            quantity: qty,
            currentTotalValue: val,
            targetInsideClass: internalT,
          ));
        }
        group.currentTotalValue += val;
      }

      // 5. Processa Ativos Sem Saldo (Metas Órfãs)
      assetGlobalTargets.forEach((ticker, globalVal) {
        if (!processedTickers.contains(ticker)) {
          String groupId = _mapTypeToGroup('UNKNOWN', ticker);
          var group = _classes.firstWhere((g) => g.id == groupId, orElse: () => _classes.last);

          double internalT = 0.0;
          if (group.targetPercentOfPortfolio > 0) {
            internalT = (globalVal / group.targetPercentOfPortfolio) * 100;
          }

          group.assets.add(AssetItem(
            ticker: ticker,
            currentPrice: 0.0,
            quantity: 0.0,
            currentTotalValue: 0.0,
            targetInsideClass: internalT,
          ));
          processedTickers.add(ticker);
        }
      });

      // 6. Ordenação Inteligente
      _classes.sort((a, b) => b.targetPercentOfPortfolio.compareTo(a.targetPercentOfPortfolio));

      _recalcTotalCheck();
      if (mounted) setState(() => _isLoading = false);

    } catch (e) {
      debugPrint("Erro Load: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _recalcTotalCheck() {
    double sum = 0;
    for (var c in _classes) sum += c.targetPercentOfPortfolio;
    setState(() => _totalAllocationCheck = sum);
  }

  // --- SALVAMENTO ROBUSTO (COM METAS DE CLASSE) ---
  Future<void> _saveStrategies() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> upsertData = [];

      for (var group in _classes) {
        // 1. SALVA A META DA CLASSE (NOVO!)
        // Isso garante que "Cripto = 5%" fique salvo mesmo se não houver ativos
        upsertData.add({
          'user_id': user.id,
          'ticker': '$kClassPrefix${group.id}', // Ex: CLASS_CRIPTO
          'target_percent': group.targetPercentOfPortfolio,
        });

        // 2. SALVA AS METAS DOS ATIVOS (Convertendo para Global)
        for (var asset in group.assets) {
          double globalTarget = (group.targetPercentOfPortfolio * asset.targetInsideClass) / 100;

          upsertData.add({
            'user_id': user.id,
            'ticker': asset.ticker,
            'target_percent': globalTarget,
          });
        }
      }

      if (upsertData.isNotEmpty) {
        await Supabase.instance.client
            .from('asset_targets')
            .upsert(upsertData, onConflict: 'user_id, ticker');
      }

      // Limpeza segura (remove zeros, exceto se for uma classe que queremos manter zerada?)
      // Na verdade, podemos deletar tudo que for zero absoluto para limpar o banco
      await Supabase.instance.client
          .from('asset_targets')
          .delete()
          .eq('user_id', user.id)
          .eq('target_percent', 0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Estratégia salva com sucesso!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Erro Save: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erro ao salvar."), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    }
  }

  // --- UI (Sem alterações drásticas, apenas integrações) ---

  void _openClassDetail(AssetClassGroup group) {
    // Se a classe estiver zerada, avisa que precisa aumentar a meta na tela principal
    // MAS permite abrir para adicionar ativos futuros
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ClassDetailModal(
        group: group,
        onSave: () {
          Navigator.pop(context);
          setState(() {});
        },
      ),
    );
  }

  void _addNewClassDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Use os sliders para definir a meta de cada classe."), backgroundColor: AppTheme.cyanNeon)
    );
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor = _totalAllocationCheck > 100.1 ? Colors.redAccent
        : (_totalAllocationCheck < 99.9 ? Colors.orangeAccent : Colors.greenAccent);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Macro Alocação", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.help_outline, color: AppTheme.cyanNeon), onPressed: _addNewClassDialog)
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanNeon))
          : Column(
        children: [
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: statusColor.withOpacity(0.3))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Meta Total", style: TextStyle(color: Colors.white70)), Text("${_totalAllocationCheck.toStringAsFixed(1)}%", style: TextStyle(color: statusColor, fontSize: 24, fontWeight: FontWeight.bold))]),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Align(alignment: Alignment.centerLeft, child: Text("DISTRIBUIÇÃO POR CLASSE", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)))),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: _classes.length,
              itemBuilder: (context, index) {
                final group = _classes[index];
                // MOSTRA TUDO (Mesmo zerados)
                return _RichClassCard(
                  group: group,
                  totalPortfolio: _totalPortfolioValue,
                  onSliderChanged: (val) {
                    setState(() {
                      group.targetPercentOfPortfolio = val;
                      _recalcTotalCheck();
                    });
                  },
                  onTap: () => _openClassDetail(group),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.cyanNeon,
        onPressed: _saveStrategies,
        icon: const Icon(Icons.check_circle_outline, color: Colors.black),
        label: const Text("Aplicar Estratégia", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// --- CARD (Mesmo visual) ---
class _RichClassCard extends StatelessWidget {
  final AssetClassGroup group;
  final double totalPortfolio;
  final Function(double) onSliderChanged;
  final VoidCallback onTap;

  const _RichClassCard({Key? key, required this.group, required this.totalPortfolio, required this.onSliderChanged, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double currentPct = totalPortfolio > 0 ? (group.currentTotalValue / totalPortfolio) * 100 : 0;
    double gap = group.targetPercentOfPortfolio - currentPct;

    Color statusColor;
    String statusText;
    if (group.targetPercentOfPortfolio > 0 && currentPct == 0) { statusColor = AppTheme.cyanNeon; statusText = "COMEÇAR"; }
    else if (gap > 1.0) { statusColor = AppTheme.cyanNeon; statusText = "COMPRAR"; }
    else if (gap < -1.0) { statusColor = Colors.orangeAccent; statusText = "AGUARDAR"; }
    else { statusColor = Colors.greenAccent; statusText = "NA META"; }

    final topAsset = group.largestAsset;
    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF1E1E24), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10), gradient: LinearGradient(colors: [const Color(0xFF1E1E24), const Color(0xFF252530)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 10), child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: statusColor.withOpacity(0.15), shape: BoxShape.circle), child: Icon(_getIconForClass(group.id), color: statusColor, size: 24)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(group.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 4), Text(f.format(group.currentTotalValue), style: const TextStyle(color: Colors.white70, fontSize: 13))])), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: statusColor.withOpacity(0.5))), child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)))])),
            const Divider(color: Colors.white10, height: 1),
            Padding(padding: const EdgeInsets.fromLTRB(20, 15, 20, 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("MAIOR POSIÇÃO", style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text(topAsset != null ? "${topAsset.ticker} (${(topAsset.targetInsideClass).toStringAsFixed(0)}%)" : "---", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))])), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text("Meta ${group.targetPercentOfPortfolio.toStringAsFixed(0)}%", style: TextStyle(color: AppTheme.cyanNeon, fontSize: 12, fontWeight: FontWeight.bold)), Text("Atual ${currentPct.toStringAsFixed(1)}%", style: const TextStyle(color: Colors.white54, fontSize: 11))])])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: SliderTheme(data: SliderTheme.of(context).copyWith(activeTrackColor: AppTheme.cyanNeon, inactiveTrackColor: Colors.black45, thumbColor: Colors.white, trackHeight: 4, overlayColor: AppTheme.cyanNeon.withOpacity(0.2)), child: Slider(value: group.targetPercentOfPortfolio.clamp(0, 100), min: 0, max: 100, divisions: 100, onChanged: onSliderChanged))),
          ],
        ),
      ),
    );
  }

  IconData _getIconForClass(String id) {
    switch (id) {
      case 'ACAO': return Icons.candlestick_chart;
      case 'FII': return Icons.location_city;
      case 'R_FIXA': return Icons.savings;
      case 'CRIPTO': return Icons.currency_bitcoin;
      case 'STOCK': return Icons.public;
      default: return Icons.pie_chart;
    }
  }
}

// --- MODAL DETALHE (Incluindo Botão Adicionar Manual) ---
class _ClassDetailModal extends StatefulWidget {
  final AssetClassGroup group;
  final VoidCallback onSave;
  const _ClassDetailModal({Key? key, required this.group, required this.onSave}) : super(key: key);
  @override
  State<_ClassDetailModal> createState() => _ClassDetailModalState();
}

class _ClassDetailModalState extends State<_ClassDetailModal> {
  bool _equalWeight = false;
  @override
  void initState() { super.initState(); _checkEqualWeight(); }

  void _checkEqualWeight() {
    if (widget.group.assets.isEmpty) return;
    double expected = 100.0 / widget.group.assets.length;
    bool allEqual = widget.group.assets.every((a) => (a.targetInsideClass - expected).abs() < 1.0);
    setState(() => _equalWeight = allEqual);
  }

  void _applyEqualWeight(bool enable) {
    setState(() {
      _equalWeight = enable;
      if (enable && widget.group.assets.isNotEmpty) {
        double share = 100.0 / widget.group.assets.length;
        for (var a in widget.group.assets) a.targetInsideClass = share;
      }
    });
  }

  void _addNewAsset() {
    String newTicker = "";
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), title: const Text("Adicionar Ativo", style: TextStyle(color: Colors.white)), content: TextField(style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Ex: BTC, IVVB11", hintStyle: TextStyle(color: Colors.white30), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.cyanNeon))), onChanged: (val) => newTicker = val.toUpperCase().trim()), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))), TextButton(onPressed: () { if (newTicker.isNotEmpty && !widget.group.assets.any((a) => a.ticker == newTicker)) { setState(() { widget.group.assets.add(AssetItem(ticker: newTicker, currentPrice: 0, quantity: 0, currentTotalValue: 0, targetInsideClass: 0)); _equalWeight = false; }); Navigator.pop(ctx); } }, child: const Text("Adicionar", style: TextStyle(color: AppTheme.cyanNeon, fontWeight: FontWeight.bold)))]));
  }

  @override
  Widget build(BuildContext context) {
    double totalInternal = widget.group.assets.fold(0.0, (sum, a) => sum + a.targetInsideClass);
    Color statusColor = (totalInternal - 100).abs() < 0.5 ? Colors.greenAccent : Colors.orangeAccent;
    return BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(height: MediaQuery.of(context).size.height * 0.85, decoration: const BoxDecoration(color: Color(0xEE121212), borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(children: [Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))), Padding(padding: const EdgeInsets.all(24), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.group.displayName, style: AppTheme.titleStyle.copyWith(fontSize: 22)), const SizedBox(height: 4), Text("${widget.group.targetPercentOfPortfolio.toStringAsFixed(0)}% do Portfólio", style: const TextStyle(color: AppTheme.cyanNeon, fontWeight: FontWeight.bold))])), IconButton(onPressed: _addNewAsset, icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white)))])) , if (widget.group.assets.isNotEmpty) Container(margin: const EdgeInsets.symmetric(horizontal: 24), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Balancear Igualmente", style: TextStyle(color: Colors.white)), Switch(value: _equalWeight, activeColor: AppTheme.cyanNeon, onChanged: _applyEqualWeight)])), const SizedBox(height: 10), Expanded(child: widget.group.assets.isEmpty ? Center(child: Text("Adicione um ativo para começar.", style: TextStyle(color: Colors.white38))) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 24), itemCount: widget.group.assets.length, itemBuilder: (context, index) { final asset = widget.group.assets[index]; return Padding(padding: const EdgeInsets.only(bottom: 24), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(asset.ticker, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), Text("${asset.targetInsideClass.toStringAsFixed(1)}%", style: const TextStyle(color: AppTheme.cyanNeon, fontWeight: FontWeight.bold))]), SliderTheme(data: SliderTheme.of(context).copyWith(activeTrackColor: _equalWeight ? Colors.grey : AppTheme.cyanNeon, thumbColor: Colors.white, overlayColor: AppTheme.cyanNeon.withOpacity(0.2), trackHeight: 2), child: Slider(value: asset.targetInsideClass.clamp(0, 100), min: 0, max: 100, divisions: 100, onChanged: _equalWeight ? null : (val) => setState(() { _equalWeight = false; asset.targetInsideClass = val; })))])); })), Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Colors.black45, border: Border(top: BorderSide(color: Colors.white10))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Alocação Interna", style: TextStyle(color: Colors.white54, fontSize: 12)), Text("${totalInternal.toStringAsFixed(1)}%", style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 18))]), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12)), onPressed: widget.onSave, child: const Text("Concluir"))]))])));
  }
}