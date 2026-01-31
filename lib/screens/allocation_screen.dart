import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../services/cloud_service.dart';

class AllocationScreen extends StatefulWidget {
  const AllocationScreen({Key? key}) : super(key: key);

  @override
  State<AllocationScreen> createState() => _AllocationScreenState();
}

class _AllocationScreenState extends State<AllocationScreen> with SingleTickerProviderStateMixin {
  final CloudService _cloud = CloudService();

  // --- ANIMAÇÃO (RESTAURADA) ---
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool _isLoading = true;

  // Controle de Seleção
  int _touchedIndexCategory = -1;
  int _touchedIndexLiquidity = -1;
  // Mantém a lógica original de agrupamento
  double _totalValue = 0.0;
  Map<String, double> _allocationTotals = {};
  Map<String, List<Map<String, dynamic>>> _groupedAssets = {}; // Lista original agrupada

  // Novos dados para o gráfico de liquidez
  Map<String, double> _liquidityTotals = {
    'D0': 0.0,
    'D2': 0.0,
    'FIXED': 0.0,
  };

  Map<String, dynamic>? _aiRecommendation;

  final Map<String, Color> _categoryColors = {
    'STOCK': AppTheme.cyanNeon,
    'FII': Colors.purpleAccent,
    'VEHICLE': const Color(0xFFD946EF),
    'REAL_ESTATE': const Color(0xFFF59E0B),
    'CASH': const Color(0xFF10B981),
    'CARRO': const Color(0xFFD946EF),
    'MOTO': const Color(0xFFD946EF),
    'IMOVEL': const Color(0xFFF59E0B),
    'TERRENO': const Color(0xFF8D6E63),
    'OUTROS': Colors.grey,
  };

  // Cores para o novo gráfico de liquidez
  final Map<String, Color> _liquidityColors = {
    'D0': const Color(0xFF10B981),
    'D2': Colors.blueAccent,
    'FIXED': Colors.redAccent,
  };

  final Map<String, String> _liquidityNames = {
    'D0': 'Imediato (D+0)',
    'D2': 'Padrão B3 (D+2)',
    'FIXED': 'Imobilizado',
  };

  final Map<String, IconData> _categoryIcons = {
    'STOCK': Icons.candlestick_chart,
    'FII': Icons.domain,
    'VEHICLE': Icons.directions_car_filled,
    'CARRO': Icons.directions_car_filled,
    'MOTO': Icons.two_wheeler,
    'REAL_ESTATE': Icons.apartment_rounded,
    'IMOVEL': Icons.home_work,
    'TERRENO': Icons.landscape,
    'CASH': Icons.savings_rounded,
    'OUTROS': Icons.category,
  };

  final Map<String, String> _categoryNames = {
    'STOCK': 'Ações',
    'FII': 'FIIs',
    'VEHICLE': 'Veículos',
    'CARRO': 'Carros',
    'MOTO': 'Motos',
    'REAL_ESTATE': 'Imóveis',
    'IMOVEL': 'Imóveis',
    'TERRENO': 'Terrenos',
    'CASH': 'Caixa',
    'OUTROS': 'Outros',
  };

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);

    _loadAllocation();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // --- LÓGICA CENTRALIZADA (MANTIDA E EXPANDIDA) ---
  Future<void> _loadAllocation() async {
    setState(() => _isLoading = true);
    try {
      final portfolioData = await _cloud.getConsolidatedPortfolio();

      final double totalPortfolio = (portfolioData['total'] as num).toDouble();
      final List<Map<String, dynamic>> assets = List<Map<String, dynamic>>.from(portfolioData['assets']);

      Map<String, double> chartTotals = {};
      Map<String, List<Map<String, dynamic>>> listGroups = {};

      // Totais para o novo gráfico
      Map<String, double> liqTotals = {'D0': 0.0, 'D2': 0.0, 'FIXED': 0.0};

      for (var asset in assets) {
        String type = asset['type'] ?? 'OUTROS';
        double value = (asset['value'] as num).toDouble();
        bool isPhysical = asset['is_physical'] ?? false;

        // Soma totais por categoria (Lógica Original)
        if (chartTotals.containsKey(type)) {
          chartTotals[type] = chartTotals[type]! + value;
        } else {
          chartTotals[type] = value;
        }

        // Agrupa lista de ativos (Lógica Original)
        if (!listGroups.containsKey(type)) {
          listGroups[type] = [];
        }
        listGroups[type]!.add(asset);

        // Classificação de Liquidez (NOVO)
        if (isPhysical) {
          liqTotals['FIXED'] = liqTotals['FIXED']! + value;
        } else {
          if (type == 'CASH' || type == 'TESOURO_SELIC' || asset['name'].toString().toUpperCase().contains('SELIC')) {
            liqTotals['D0'] = liqTotals['D0']! + value;
          } else {
            liqTotals['D2'] = liqTotals['D2']! + value;
          }
        }
      }

      // Calcula recomendação IA (NOVO)
      final recommendation = _calculateAiRecommendation(assets);

      if (mounted) {
        setState(() {
          _totalValue = totalPortfolio;
          _allocationTotals = chartTotals;
          _groupedAssets = listGroups;
          _liquidityTotals = liqTotals;
          _aiRecommendation = recommendation;
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Error loading allocation: $e");
    }
  }

  // --- NOVA FUNÇÃO IA ---
  Map<String, dynamic>? _calculateAiRecommendation(List<Map<String, dynamic>> assets) {
    final liquidAssets = assets.where((a) => (a['is_physical'] ?? false) == false).toList();
    if (liquidAssets.isEmpty) return null;

    liquidAssets.sort((a, b) {
      double buyA = (a['average_price'] as num).toDouble();
      double currA = (a['current_price'] as num).toDouble();
      double rentA = buyA > 0 ? (currA - buyA) / buyA : 0;

      double buyB = (b['average_price'] as num).toDouble();
      double currB = (b['current_price'] as num).toDouble();
      double rentB = buyB > 0 ? (currB - buyB) / buyB : 0;

      if (rentA >= 0 && rentB < 0) return -1;
      if (rentB >= 0 && rentA < 0) return 1;
      return rentB.compareTo(rentA);
    });

    if (liquidAssets.isNotEmpty) {
      final best = liquidAssets.first;
      double buy = (best['average_price'] as num).toDouble();
      double curr = (best['current_price'] as num).toDouble();
      double rent = buy > 0 ? ((curr - buy) / buy) * 100 : 0.0;

      return {
        'asset': best,
        'reason': rent >= 0
            ? "Lucro de ${rent.toStringAsFixed(1)}%. Realize ganho."
            : "Menor perca (${rent.toStringAsFixed(1)}%). Proteja o principal."
      };
    }
    return null;
  }

  // --- AÇÕES DE GERENCIAMENTO (ORIGINAL) ---

  Future<void> _deleteAsset(String id, String categoryKey) async {
    try {
      // O Navigator.pop está dentro do modal agora, ou aqui se for chamado direto
      // Mas para manter a lógica original onde o modal chama essa função:
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Processando..."), duration: Duration(milliseconds: 500)));
      await _cloud.deleteAsset(id);
      await _loadAllocation();

      // Se a categoria ainda existir, reabre detalhes (Lógica Original)
      if ((_groupedAssets[categoryKey]?.length ?? 0) > 0) {
        _showCategoryDetails(categoryKey);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _clearTotalPortfolio() async {
    try {
      Navigator.pop(context);
      setState(() => _isLoading = true);
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('assets').delete().eq('user_id', userId);
      }
      await _loadAllocation();
    } catch (e) { setState(() => _isLoading = false); }
  }

  String _formatMoney(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  // --- MODALS (ORIGINAIS) ---

  void _showAssetHistory(Map<String, dynamic> asset) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AssetSmartModal(
          asset: asset,
          onUpdate: _loadAllocation
      ),
    );
  }

  void _showCategoryDetails(String categoryKey) {
    final List<Map<String, dynamic>> assets = _groupedAssets[categoryKey] ?? [];
    final color = _categoryColors[categoryKey] ?? Colors.white;
    final title = _categoryNames[categoryKey] ?? categoryKey;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: color, width: 2)),
              ),
              child: Column(
                children: [
                  Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        Icon(_categoryIcons[categoryKey] ?? Icons.circle, color: color),
                        const SizedBox(width: 12),
                        Text(title, style: AppTheme.titleStyle.copyWith(fontSize: 20)),
                        const Spacer(),
                        Text("${assets.length} ativos", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: assets.length,
                      itemBuilder: (context, index) {
                        final asset = assets[index];
                        final name = asset['name'] ?? 'Sem nome';
                        final ticker = asset['ticker'] ?? '';
                        final value = (asset['value'] as num).toDouble();
                        final qty = (asset['quantity'] as num?)?.toDouble() ?? 0.0;
                        final id = asset['id'].toString();

                        String type = asset['type'];
                        IconData itemIcon = Icons.circle;
                        if (type == 'VEHICLE') itemIcon = Icons.directions_car;
                        if (type == 'STOCK') itemIcon = Icons.show_chart;

                        return Card(
                          color: Colors.white.withOpacity(0.05),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              _showAssetHistory(asset); // HABILITADO
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: color.withOpacity(0.1),
                                    child: categoryKey == 'STOCK' || categoryKey == 'FII'
                                        ? Text(ticker.isNotEmpty ? ticker[0] : name[0], style: TextStyle(color: color, fontWeight: FontWeight.bold))
                                        : Icon(itemIcon, color: color, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(ticker.isNotEmpty && ticker != 'Desconhecido' ? ticker : name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        if (qty > 0 && (categoryKey == 'STOCK' || categoryKey == 'FII'))
                                          Text(qty % 1 == 0 ? "${qty.toInt()} cotas" : "$qty cotas", style: const TextStyle(color: Colors.white38, fontSize: 12))
                                        else
                                          Text(name, style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_formatMoney(value), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () => _confirmDeleteAsset(id, name, categoryKey),
                                            child: const Padding(padding: EdgeInsets.all(6.0), child: Icon(Icons.delete_outline, color: Colors.redAccent, size: 18)),
                                          ),
                                          const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.info_outline, color: Colors.white24, size: 18))
                                        ],
                                      )
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAsset(String id, String name, String categoryKey) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Excluir Ativo?", style: TextStyle(color: Colors.white)),
        content: Text("Deseja remover $name?", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          TextButton(onPressed: () {
            Navigator.pop(ctx); // Fecha dialog
            _deleteAsset(id, categoryKey); // Chama delete e recarrega
          }, child: const Text("Excluir", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  // --- LAYOUT E BUILD ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned(top: -100, right: -50, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80), child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.cyanNeon.withOpacity(0.1))))),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanNeon))
                      : _allocationTotals.isEmpty
                      ? const Center(child: Text("Nenhum patrimônio ativo", style: TextStyle(color: Colors.white54)))
                      : FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth > 900) {
                            return _buildWebLayout();
                          } else {
                            return _buildMobileLayout();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- LAYOUTS MISTOS (ORIGINAL + NOVIDADES) ---

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        children: [
          const SizedBox(height: 10),
          // 1. Gráfico Original (Categorias)
          SizedBox(height: 300, child: _buildPieChartCategories()),
          const SizedBox(height: 20),

          // 2. Novos Cards (Liquidez e IA)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _buildLiquidityCard(),
                const SizedBox(height: 16),
                if (_aiRecommendation != null) _buildAiInsightCard(),
              ],
            ),
          ),
          const SizedBox(height: 30),

          // 3. Novo Gráfico (Liquidez)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0),
            child: Align(alignment: Alignment.centerLeft, child: Text("Tempo de Resgate (Liquidez)", style: TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.bold))),
          ),
          SizedBox(height: 250, child: _buildPieChartLiquidity()),
          const SizedBox(height: 30),

          // 4. Lista Horizontal Original (Cards de Categoria)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.symmetric(horizontal: 24.0), child: Text("Composição (Líquida)", style: TextStyle(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.bold))),
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _allocationTotals.length,
                    itemBuilder: (context, idx) {
                      final key = _allocationTotals.keys.elementAt(idx);
                      final value = _allocationTotals[key]!;
                      final color = _categoryColors[key] ?? Colors.grey;
                      final name = _categoryNames[key] ?? key;
                      final icon = _categoryIcons[key] ?? Icons.circle;

                      return GestureDetector(
                        onTap: () => _showCategoryDetails(key), // CHAMA O MODAL ORIGINAL
                        child: Container(
                          width: 150,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: _touchedIndexCategory == idx ? color : Colors.white.withOpacity(0.1))),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)), const Spacer(), Text(name, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text(_formatMoney(value), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Container(height: 4, width: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)))]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: Column(children: [const Text("Alocação por Classe", style: TextStyle(color: Colors.white54)), SizedBox(height: 350, child: _buildPieChartCategories())])),
                Expanded(flex: 2, child: Column(children: [const SizedBox(height: 40), _buildLiquidityCard(), const SizedBox(height: 20), if (_aiRecommendation != null) _buildAiInsightCard()])),
                Expanded(flex: 3, child: Column(children: [const Text("Perfil de Liquidez", style: TextStyle(color: Colors.white54)), SizedBox(height: 350, child: _buildPieChartLiquidity())])),
              ],
            ),
          ),
          const SizedBox(height: 40),
          // Mantém a lista horizontal também no Web
          SizedBox(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 40),
              itemCount: _allocationTotals.length,
              itemBuilder: (context, idx) {
                final key = _allocationTotals.keys.elementAt(idx);
                final value = _allocationTotals[key]!;
                final color = _categoryColors[key] ?? Colors.grey;
                final name = _categoryNames[key] ?? key;
                final icon = _categoryIcons[key] ?? Icons.circle;
                return GestureDetector(
                  onTap: () => _showCategoryDetails(key),
                  child: Container(
                    width: 150,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.1))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)), const Spacer(), Text(name, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text(_formatMoney(value), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Container(height: 4, width: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)))]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white), onPressed: () => Navigator.pop(context)),
          const Expanded(child: Text("Sua Fortaleza", style: TextStyle(fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1), textAlign: TextAlign.center)),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.white54),
            onPressed: _totalValue > 0
                ? () => showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), title: const Text("Zerar Carteira?", style: TextStyle(color: Colors.white)), content: const Text("Isso apaga todo o histórico.", style: TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")), TextButton(onPressed: _clearTotalPortfolio, child: const Text("ZERAR", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))]))
                : null,
          ),
        ],
      ),
    );
  }

  // Gráfico Original (Categorias)
  Widget _buildPieChartCategories() {
    final List<PieChartSectionData> sections = [];
    int index = 0;
    String centerLabel = "Total";
    String centerValue = NumberFormat.compactCurrency(locale: 'pt_BR', symbol: 'R\$').format(_totalValue);
    Color centerColor = Colors.white;

    _allocationTotals.forEach((key, value) {
      final isTouched = index == _touchedIndexCategory;
      final color = _categoryColors[key] ?? Colors.grey;
      final percentage = _totalValue > 0 ? (value / _totalValue) * 100 : 0;

      if (isTouched) {
        centerLabel = _categoryNames[key] ?? key;
        centerValue = "${percentage.toStringAsFixed(1)}%";
        centerColor = color;
      }

      final radius = isTouched ? 60.0 : 50.0;
      sections.add(PieChartSectionData(color: color, value: value, title: '${percentage.toInt()}%', radius: radius, titleStyle: TextStyle(fontSize: isTouched ? 18 : 14, fontWeight: FontWeight.bold, color: Colors.white, shadows: const [Shadow(color: Colors.black, blurRadius: 2)])));
      index++;
    });

    return Stack(
      alignment: Alignment.center,
      children: [
        Column(mainAxisSize: MainAxisSize.min, children: [Text(centerLabel.toUpperCase(), style: TextStyle(color: centerColor.withOpacity(0.7), letterSpacing: 2, fontSize: 12)), const SizedBox(height: 4), Text(centerValue, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Outfit'))]),
        PieChart(PieChartData(
          pieTouchData: PieTouchData(touchCallback: (FlTouchEvent event, pieTouchResponse) {
            if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
              if (_touchedIndexCategory != -1) setState(() => _touchedIndexCategory = -1);
              return;
            }
            final newIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
            if (newIndex != _touchedIndexCategory) setState(() => _touchedIndexCategory = newIndex);
          }),
          borderData: FlBorderData(show: false),
          sectionsSpace: 4,
          centerSpaceRadius: 90,
          sections: sections,
        )),
      ],
    );
  }

  // Novo Gráfico (Liquidez)
  Widget _buildPieChartLiquidity() {
    List<PieChartSectionData> sections = [];
    int index = 0;
    _liquidityTotals.forEach((key, value) {
      if (value > 0) {
        final isTouched = index == _touchedIndexLiquidity;
        final color = _liquidityColors[key] ?? Colors.grey;
        final percentage = _totalValue > 0 ? (value / _totalValue) * 100 : 0;
        final radius = isTouched ? 60.0 : 50.0;
        sections.add(PieChartSectionData(color: color, value: value, title: '${percentage.toInt()}%', radius: radius, titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)));
      }
      index++;
    });

    String label = "Liquidez";
    String val = "";
    if (_touchedIndexLiquidity != -1) {
      int activeIdx = 0;
      String? foundKey;
      _liquidityTotals.forEach((k, v) { if (v > 0) { if (activeIdx == _touchedIndexLiquidity) foundKey = k; activeIdx++; } });
      if (foundKey != null) { label = _liquidityNames[foundKey]!; val = _formatMoney(_liquidityTotals[foundKey]!); }
    }

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(mainAxisSize: MainAxisSize.min, children: [Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10), textAlign: TextAlign.center), if(val.isNotEmpty) Text(val, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))]),
              PieChart(PieChartData(
                pieTouchData: PieTouchData(touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                    if (_touchedIndexLiquidity != -1) setState(() => _touchedIndexLiquidity = -1);
                    return;
                  }
                  final newIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                  if (newIndex != _touchedIndexLiquidity) setState(() => _touchedIndexLiquidity = newIndex);
                }),
                borderData: FlBorderData(show: false),
                sectionsSpace: 2,
                centerSpaceRadius: 60,
                sections: sections,
              )),
            ],
          ),
        ),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _liquidityTotals.entries.where((e) => e.value > 0).map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: _liquidityColors[e.key], shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_liquidityNames[e.key]!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), Text(_formatMoney(e.value), style: const TextStyle(color: Colors.white38, fontSize: 10))]))]),
              );
            }).toList(),
          ),
        )
      ],
    );
  }

  Widget _buildLiquidityCard() {
    double liquidTotal = (_liquidityTotals['D0'] ?? 0) + (_liquidityTotals['D2'] ?? 0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFF10B981).withOpacity(0.15), Colors.black], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Ícone (Tamanho Fixo)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.account_balance_wallet, color: Color(0xFF10B981), size: 24),
          ),
          const SizedBox(width: 12), // Reduzi de 16 para 12 para ganhar espaço

          // 2. Coluna de Títulos (Usa Expanded para ocupar o espaço central disponível)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Reserva Potencial",
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis, // Corta com "..." se o espaço sumir
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown, // Faz o texto diminuir se o valor da direita empurrar
                  alignment: Alignment.centerLeft,
                  child: const Text(
                    "Vira dinheiro rápido",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // 3. Coluna de Valor (Usa Flexible + FittedBox para encolher o valor monetário)
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown, // CRÍTICO: Faz o R$ diminuir em vez de quebrar a linha
                  child: Text(
                    _formatMoney(liquidTotal), // Use sua variável aqui
                    style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        fontFamily: 'Outfit'
                    ),
                  ),
                ),
                const Text(
                  "Em até 2 dias",
                  style: TextStyle(color: Colors.white38, fontSize: 9),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      )
    );
  }

  Widget _buildAiInsightCard() {
    if (_aiRecommendation == null) return const SizedBox.shrink();
    final asset = _aiRecommendation!['asset'];
    final name = asset['name'];
    final ticker = asset['ticker'];
    final reason = _aiRecommendation!['reason'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.5)), boxShadow: [BoxShadow(color: AppTheme.cyanNeon.withOpacity(0.1), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [const Icon(Icons.auto_awesome, color: AppTheme.cyanNeon, size: 18), const SizedBox(width: 8), const Text("IA Insight: Emergência", style: TextStyle(color: AppTheme.cyanNeon, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1))]),
          const SizedBox(height: 12),
          RichText(text: TextSpan(style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4), children: [const TextSpan(text: "Precisa de caixa? Sugerimos vender "), TextSpan(text: ticker != 'Desconhecido' ? ticker : name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const TextSpan(text: " primeiro.\n"), TextSpan(text: reason, style: TextStyle(color: Colors.white.withOpacity(0.5), fontStyle: FontStyle.italic, fontSize: 12))])),
        ],
      ),
    );
  }
}

// --- MODAL INTELIGENTE (ORIGINAL - MANTIDO) ---
class AssetSmartModal extends StatefulWidget {
  final Map<String, dynamic> asset;
  final VoidCallback onUpdate;
  const AssetSmartModal({Key? key, required this.asset, required this.onUpdate}) : super(key: key);
  @override
  State<AssetSmartModal> createState() => _AssetSmartModalState();
}

class _AssetSmartModalState extends State<AssetSmartModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  List<Map<String, dynamic>> _earnings = [];
  List<Map<String, dynamic>> _transactions = [];
  late double _localAvgPrice;
  late int _localQty;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _localAvgPrice = (widget.asset['average_price'] as num?)?.toDouble() ?? 0.0;
    _localQty = (widget.asset['quantity'] as num?)?.toInt() ?? 0;
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    final ticker = widget.asset['ticker'] as String?;
    if (ticker == null || ticker.isEmpty || ticker == 'Desconhecido') {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final client = Supabase.instance.client;
      final earningsResp = await client.from('earnings').select().eq('ticker', ticker).order('date', ascending: false).limit(12);

      List<Map<String, dynamic>> orders = [];
      try {
        String t = ticker.toUpperCase().trim();
        String cleanTicker = t.replaceAll(RegExp(r'[Ff]$'), '');
        String fracTicker = cleanTicker + 'F';
        final ordersResp = await client.from('assets').select().inFilter('ticker', [t, cleanTicker, fracTicker]).order('created_at', ascending: false);
        orders = List<Map<String, dynamic>>.from(ordersResp);
      } catch (e) { debugPrint("Erro hist: $e"); }

      if (mounted) {
        setState(() {
          _earnings = List<Map<String, dynamic>>.from(earningsResp);
          _transactions = orders;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showEditDialog() {
    final qtyCtrl = TextEditingController(text: _localQty.toString());
    final priceCtrl = TextEditingController(text: _localAvgPrice.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Editar Posição", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mudei para decimal para aceitar 0.5 ações ou coisas do tipo se precisar
            TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Quantidade", labelStyle: TextStyle(color: AppTheme.cyanNeon))
            ),
            const SizedBox(height: 16),
            TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Preço Médio / Valor Pago", labelStyle: TextStyle(color: AppTheme.cyanNeon))
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cyanNeon),
            onPressed: () async {
              // Conversão segura
              final newQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? _localQty;
              final newPrice = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? _localAvgPrice;

              // 1. DESCOBRE A TABELA CERTA (O PULO DO GATO 🐈)
              // Se não tiver o campo, assume 'assets' por segurança
              String tableName = widget.asset['source_table'] ?? 'assets';

              Map<String, dynamic> updateData = {};

              if (tableName == 'immobilized_assets') {
                // --- LÓGICA PARA CARROS/CASAS ---
                // Nessas tabelas, as colunas têm nomes diferentes
                updateData = {
                  'purchase_price': newPrice, // O "Preço Médio" vira Preço de Compra
                  'current_price': newPrice,  // Atualizamos o valor atual também para refletir a edição
                  // Geralmente físico não muda quantidade (sempre 1), mas se quiser forçar:
                  // 'quantity': 1
                };
              } else {
                // --- LÓGICA PARA AÇÕES/FIIS (assets) ---
                // Atualiza Qtd, PM e recalcula o Valor Total
                double currentMarketPrice = (widget.asset['current_price'] as num?)?.toDouble() ?? newPrice;
                updateData = {
                  'quantity': newQty,
                  'average_price': newPrice,
                  'value': newQty * currentMarketPrice // Recalcula o total
                };
              }

              // Executa o update na tabela correta
              await Supabase.instance.client
                  .from(tableName)
                  .update(updateData)
                  .eq('id', widget.asset['id']);

              widget.onUpdate();
              Navigator.pop(ctx);
            },
            child: const Text("Salvar", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final name = asset['ticker'] ?? asset['name'];
    final bool isPhysical = asset['is_physical'] ?? false;
    double totalValue = isPhysical ? (asset['value'] as num).toDouble() : _localQty * ((asset['current_price'] as num?)?.toDouble() ?? _localAvgPrice);

    final currentPrice = (asset['current_price'] as num?)?.toDouble() ?? _localAvgPrice;
    double rentability = 0.0;
    if (_localAvgPrice > 0 && currentPrice > 0 && !isPhysical) {
      rentability = ((currentPrice - _localAvgPrice) / _localAvgPrice) * 100;
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(color: Color(0xFF141414), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 12, bottom: 10), width: 50, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2.5)))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(color: Colors.white54, fontSize: 14)), Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(totalValue), style: TextStyle(color: AppTheme.cyanNeon, fontSize: 32, fontWeight: FontWeight.bold, fontFamily: 'Outfit'))]),
                IconButton(onPressed: _showEditDialog, icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.edit, color: Colors.white, size: 20)))
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _infoBox("Custo/Médio", NumberFormat.simpleCurrency(locale: 'pt_BR').format(_localAvgPrice)),
                const SizedBox(width: 12),
                if (!isPhysical) ...[ _infoBox("Rentabilidade", "${rentability.toStringAsFixed(2)}%", textColor: rentability >= 0 ? Colors.greenAccent : Colors.redAccent), const SizedBox(width: 12) ],
                _infoBox("Qtd.", "$_localQty"),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), child: TabBar(controller: _tabController, indicator: BoxDecoration(color: AppTheme.cyanNeon.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), labelColor: AppTheme.cyanNeon, unselectedLabelColor: Colors.white54, tabs: const [Tab(text: "Resumo"), Tab(text: "Movimentações")])),
          const SizedBox(height: 10),
          Expanded(child: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanNeon)) : TabBarView(controller: _tabController, children: [_buildEarningsList(), _buildTransactionsList()])),
        ],
      ),
    );
  }

  Widget _buildEarningsList() {
    if (_earnings.isEmpty) return const Center(child: Text("Sem proventos recentes", style: TextStyle(color: Colors.white30)));
    return ListView.builder(itemCount: _earnings.length, itemBuilder: (ctx, i) { final e = _earnings[i]; return ListTile(leading: const Icon(Icons.attach_money, color: Colors.greenAccent), title: Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(e['date'])), style: const TextStyle(color: Colors.white)), trailing: Text("+ ${NumberFormat.simpleCurrency(locale: 'pt_BR').format(e['total_value'])}", style: const TextStyle(color: Colors.greenAccent))); });
  }

  Widget _buildTransactionsList() {
    if (_transactions.isEmpty) return const Center(child: Text("Sem histórico", style: TextStyle(color: Colors.white30)));
    return ListView.builder(itemCount: _transactions.length, itemBuilder: (ctx, i) { final t = _transactions[i]; final isBuy = (t['metadata']?['operation_type'] ?? 'C').toString().toUpperCase().startsWith('C'); return ListTile(leading: Icon(isBuy ? Icons.arrow_downward : Icons.arrow_upward, color: isBuy ? AppTheme.cyanNeon : Colors.orangeAccent), title: Text(isBuy ? "Compra/Entrada" : "Venda/Saída", style: const TextStyle(color: Colors.white)), subtitle: Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(t['created_at'])), style: const TextStyle(color: Colors.white38)), trailing: Text("${isBuy?'+':''}${t['quantity']}", style: const TextStyle(color: Colors.white))); });
  }

  Widget _infoBox(String label, String value, {Color textColor = Colors.white}) {
    return Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.1))), child: Column(children: [Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 6), FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)))])));
  }
}