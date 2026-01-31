import 'dart:ui';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:perpetuum/screens/rebalance_screen.dart';
import 'package:perpetuum/screens/tax_report_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme.dart';
import '../../services/cloud_service.dart';
import '../../services/dividend_service.dart';
import '../../services/ai/portfolio_brain.dart';

import '../services/ai/AiEngineService.dart';
import '../services/excel_generator_service.dart';
import 'add_asset_financeiro_screen.dart';
import 'admin_errors_screen.dart';
import '../import/import_screen.dart';
import 'add_asset_screen.dart';
import 'allocation_screen.dart';
import 'dividends_screen.dart';
import 'portfolio_auditor_screen.dart';
import 'package:perpetuum/screens/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final CloudService _cloud = CloudService();
  final DividendService _dividendService = DividendService();

  bool _isLocaleReady = false;
  bool _isLoading = true;

  // Financial Data
  double _totalPatrimony = 0.0;
  double _growthPercentage = 0.0;
  double _dividendsThisMonth = 0.0;

  int _easterEggCounter = 0;

  // Assets and AI
  List<Map<String, dynamic>> _allAssets = [];
  List<Insight> _portfolioInsights = [];
  Map<String, dynamic>? _topAsset;
  Map<String, dynamic>? _rebalanceAction;

  // Profile
  String? _avatarUrl;

  // Chart
  List<FlSpot> _chartSpots = [
    const FlSpot(0, 0),
    const FlSpot(1, 0),
    const FlSpot(2, 0),
    const FlSpot(3, 0),
    const FlSpot(4, 0),
  ];

  late AnimationController _hoverController;
  late Animation<Offset> _hoverAnimation;

  late PageController _insightPageController;
  // static: Garante que o índice persista mesmo se você sair e voltar da tela
  static int _globalInsightIndex = 0;

  @override
  void initState() {
    super.initState();
    // Inicializa o controller já na página correta (global)
    _insightPageController = PageController(initialPage: _globalInsightIndex);
    _loadData(); // Seu método de carregar dados

    // Icon floating animation
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _hoverAnimation =
        Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut),
        );

    _initSetup();
  }

  Future<void> _initSetup() async {
    await initializeDateFormatting('pt_BR', null);
    if (mounted) {
      setState(() => _isLocaleReady = true);
      _loadData();
    }
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _insightPageController.dispose();
    super.dispose();
  }

  // Função simples para avançar para o próximo
  void _advanceInsight() {
    if (_portfolioInsights.length < 2) return;

    setState(() {
      _globalInsightIndex++;
      // Se passar do limite, volta ao zero (ou remove essa linha se quiser loop infinito real no PageView)
      if (_globalInsightIndex >= _portfolioInsights.length) {
        _globalInsightIndex = 0; // Reset opcional, ou deixa crescer se usar index % length no builder
      }
    });

    // Pula direto ou anima suavemente
    _insightPageController.animateToPage(
      _globalInsightIndex,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
  }

  // Helper para limpar tickers e unificar fracionários
  String _cleanTicker(String ticker) {
    String t = ticker.toUpperCase().trim();
    if (t.length > 4 && t.endsWith('F')) {
      return t.substring(0, t.length - 1);
    }
    return t;
  }

  // --- PARSERS INTELIGENTES ---

  double _parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      try {
        String cleaned = value.replaceAll('R\$', '').replaceAll(' ', '').trim();
        if (cleaned.contains(',') && !cleaned.contains('.')) {
          cleaned = cleaned.replaceAll(',', '.');
        } else if (cleaned.contains('.') && cleaned.contains(',')) {
          cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
        }
        return double.tryParse(cleaned) ?? 0.0;
      } catch (_) {}
    }
    return 0.0;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    String s = value.toString().trim();

    if (s.length < 8) return null;

    try {
      if (s.contains('-')) {
        return DateTime.tryParse(s);
      }
      if (s.contains('/')) {
        var parts = s.split('/');
        if (parts.length == 3) {
          int day = int.tryParse(parts[0]) ?? 1;
          int month = int.tryParse(parts[1]) ?? 1;
          int year = int.tryParse(parts[2]) ?? DateTime.now().year;
          if (year < 100) year += 2000;
          return DateTime(year, month, day);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final currentYear = DateTime.now().year;

      final results = await Future.wait([
        _cloud.getConsolidatedPortfolio(),
        _cloud.getTotalNetWorth(currentYear - 1),
        _dividendService.getUserDividends(),
        Supabase.instance.client.from('assets').select(),
      ]);

      final portfolioData = results[0] as Map<String, dynamic>;
      final totalNow = (portfolioData['total'] as num).toDouble();
      final List<Map<String, dynamic>> consolidatedAssets =
      List<Map<String, dynamic>>.from(portfolioData['assets']);

      final List<Map<String, dynamic>> rawAssets =
      List<Map<String, dynamic>>.from(results[3] as List);

      // --- INÍCIO DA LÓGICA DE REBALANCEAMENTO (NOVO) ---
      Map<String, dynamic>? bestRebalanceAction;
      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        final targetResults = await Supabase.instance.client
            .from('asset_targets')
            .select()
            .eq('user_id', user.id);

        final List<Map<String, dynamic>> targets =
        List<Map<String, dynamic>>.from(targetResults);

        if (targets.isNotEmpty) {
          Map<String, double> targetMap = {
            for (var t in targets)
              t['ticker'].toString().toUpperCase():
              (t['target_percent'] as num).toDouble()
          };

          List<Map<String, dynamic>> gaps = [];
          for (var asset in consolidatedAssets) {
            String ticker = asset['ticker'].toString().toUpperCase();
            double currentVal = (asset['value'] as num).toDouble();

            // Evita divisão por zero
            double currentWeight = totalNow > 0 ? (currentVal / totalNow) * 100 : 0.0;
            double targetWeight = targetMap[ticker] ?? 0.0;

            if (targetWeight > currentWeight) {
              gaps.add({
                'ticker': ticker,
                'name': asset['name'],
                'gap': targetWeight - currentWeight,
                'needed': totalNow > 0 ? (targetWeight / 100 * totalNow) - currentVal : 0.0,
              });
            }
          }

          if (gaps.isNotEmpty) {
            gaps.sort((a, b) => (b['gap'] as num).compareTo(a['gap'] as num));
            bestRebalanceAction = gaps.first;
          }
        }
      }
      // --- FIM DA LÓGICA DE REBALANCEAMENTO ---

      Map<String, double> assetBalances = {};
      for (var asset in consolidatedAssets) {
        String ticker = _cleanTicker(asset['ticker'].toString());
        assetBalances[ticker] =
            (assetBalances[ticker] ?? 0) + (asset['quantity'] as num).toDouble();
      }

      final totalLastYear = (results[1] as num).toDouble();
      final dividendData =
      results[2] as Map<String, List<Map<String, dynamic>>>;

      List<FlSpot> historySpots = [];

      for (int i = 4; i >= 0; i--) {
        int year = currentYear - i;
        double yearValue = 0;

        if (i == 0) {
          yearValue = totalNow;
        } else {
          for (var asset in rawAssets) {
            try {
              DateTime? assetDate;
              if (asset.containsKey('date'))
                assetDate = _parseDate(asset['date']);
              if (assetDate == null && asset.containsKey('purchase_date'))
                assetDate = _parseDate(asset['purchase_date']);

              if (assetDate == null && asset['metadata'] != null) {
                final meta = asset['metadata'];
                if (meta is Map) {
                  var candidate = meta['Período (Inicial)'] ??
                      meta['date'] ??
                      meta['Data'];
                  assetDate = _parseDate(candidate);
                  if (assetDate == null) {
                    for (var val in meta.values) {
                      DateTime? d = _parseDate(val);
                      if (d != null &&
                          d.year > 2000 &&
                          d.year <= (currentYear + 1)) {
                        assetDate = d;
                        break;
                      }
                    }
                  }
                }
              }

              if (assetDate == null) {
                assetDate = _parseDate(asset['created_at']);
              }

              if (assetDate != null && assetDate.year <= year) {
                double qty = (asset['quantity'] as num).toDouble();
                double cost = (asset['average_price'] ??
                    asset['purchase_price'] ??
                    asset['current_price'] ??
                    0)
                    .toDouble();

                if (cost == 0 && asset['metadata'] is Map) {
                  var meta = asset['metadata'] as Map;
                  cost = _parsePrice(
                      meta['Preço Médio (Compra)'] ?? meta['price']);
                }
                yearValue += (qty * cost);
              }
            } catch (e) {}
          }
        }
        historySpots.add(FlSpot((4 - i).toDouble(), yearValue));
      }

      Map<String, dynamic>? topAsset;
      if (consolidatedAssets.isNotEmpty) {
        consolidatedAssets.sort(
              (a, b) => (b['value'] as num).compareTo(a['value'] as num),
        );
        topAsset = consolidatedAssets.first;
      }

      double growth = 0.0;
      if (totalLastYear > 0) {
        growth = ((totalNow - totalLastYear) / totalLastYear) * 100;
      } else if (totalNow > 0 && totalLastYear == 0) {
        growth = 100.0;
      }

      final pastDivs = dividendData['past'] ?? [];
      final futureDivs = dividendData['future'] ?? [];
      final allDividends = [...pastDivs, ...futureDivs];

      double monthlyDivs = 0.0;
      String targetMonthStr = DateFormat('MM/yyyy').format(DateTime.now());

      for (var item in allDividends) {
        final date = _parseDate(item['date']);
        if (date != null) {
          String itemMonthStr = DateFormat('MM/yyyy').format(date);
          String ticker = _cleanTicker(item['ticker'].toString());

          if (itemMonthStr == targetMonthStr &&
              assetBalances.containsKey(ticker) &&
              assetBalances[ticker]! > 0) {
            monthlyDivs += (item['total_value'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }

      final aiInsights = PortfolioBrain.analyze(consolidatedAssets);

      final avatar = user?.userMetadata?['avatar_url'];

      if (mounted) {
        setState(() {
          _totalPatrimony = totalNow;
          _growthPercentage = growth;
          _dividendsThisMonth = monthlyDivs;
          _allAssets = consolidatedAssets;
          _topAsset = topAsset;
          _chartSpots = historySpots;
          _portfolioInsights = aiInsights;
          _avatarUrl = avatar;
          _rebalanceAction = bestRebalanceAction; // Atualiza a variável de estado
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error Home Load: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _formattedMoney => NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  ).format(_totalPatrimony);

  String _formatCurrency(double val) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(val);

  String get _currentMonthName =>
      toBeginningOfSentenceCase(
        DateFormat('MMMM', 'pt_BR').format(DateTime.now()),
      ) ??
          "";

  Color _getInsightColor(String type) {
    switch (type) {
      case 'DANGER':
        return Colors.redAccent;
      case 'WARNING':
        return Colors.orangeAccent;
      case 'SUCCESS':
        return Colors.greenAccent;
      default:
        return AppTheme.cyanNeon;
    }
  }

  void _showAllAssets() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: Colors.black.withOpacity(0.85),
            body: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "Meus Ativos",
                            style: AppTheme.titleStyle.copyWith(fontSize: 20),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        itemCount: _allAssets.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: _buildSingleAssetCard(
                              _allAssets[index],
                              isClickable: false,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _exportExcelTemplate() async {
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['Sheet1'];

      List<String> headers = [
        "Código de Negociação", "Período (Inicial)", "Período (Final)",
        "Instituição", "Quantidade (Compra)", "Quantidade (Venda)",
        "Quantidade (Líquida)", "Preço Médio (Compra)", "Preço Médio (Venda)"
      ];

      for (var i = 0; i < headers.length; i++) {
        var cell = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel_pkg.TextCellValue(headers[i]);
      }

      final fileBytes = excel.save();
      final directory = await getTemporaryDirectory();
      final file = await File('${directory.path}/Planilha_Perpetuum.xlsx').create();
      await file.writeAsBytes(fileBytes!);

      await Share.shareXFiles([XFile(file.path)], text: 'Modelo de Planilha Perpetuum');
    } catch (e) {
      debugPrint("Erro export: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocaleReady) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.cyanNeon),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.cyanNeon.withOpacity(0.15),
                ),
              ),
            ),
          ),
          SafeArea(
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
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 30),
              _buildTotalBalance(),
              const SizedBox(height: 20),
              _buildDividendHighlight(),
              const SizedBox(height: 12),
              const AiSearchWidget(), // NOVO CARD DE PESQUISA IA
              const SizedBox(height: 24),
              _buildRebalanceCard(), // <--- COLOQUE AQUI
              const SizedBox(height: 24),
              _buildAiInsightsWidget(),
              const SizedBox(height: 30),
              _buildChartContainer(height: 240),
              const SizedBox(height: 20),

              if (_topAsset != null)
                GestureDetector(
                  onTap: _showAllAssets,
                  child: _buildSingleAssetCard(_topAsset!, isCompact: true),
                ),

              const SizedBox(height: 30),
              _buildAuditorCallout(),
              const SizedBox(height: 16),
              _buildActionButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 40),
                  _buildTotalBalance(isWeb: true),
                  const SizedBox(height: 20),
                  _buildDividendHighlight(isWeb: true),
                  const SizedBox(height: 12),
                  const AiSearchWidget(), // NOVO CARD DE PESQUISA IA
                  const SizedBox(height: 24),
                  Container(
                    color: Colors.red.withOpacity(0.1), // Cor de debug temporária
                    child: _buildRebalanceCard(),
                  ),
                  const SizedBox(height: 24),

                  _buildAiInsightsWidget(isWeb: true),
                  const SizedBox(height: 40),
                  _buildAuditorCallout(),
                  const SizedBox(height: 20),
                  _buildActionButtons(context),
                ],
              ),
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            flex: 6,
            child: Column(
              children: [
                Expanded(
                  flex: 5,
                  child: _buildChartContainer(height: double.infinity),
                ),
                const SizedBox(height: 20),
                if (_topAsset != null)
                  Expanded(
                    flex: 6,
                    child: GestureDetector(
                      onTap: _showAllAssets,
                      child: _buildSingleAssetCard(_topAsset!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditorCallout() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PortfolioAuditorScreen()),
        ).then((_) => _loadData());
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.purpleAccent.withOpacity(0.15),
              const Color(0xFF1E1E24),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.purpleAccent.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                color: Colors.purpleAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Auditoria Inteligente",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Valide ativos e corrija saldos com IA.",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white24,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiInsightsWidget({bool isWeb = false}) {
    if (_portfolioInsights.isEmpty) return const SizedBox.shrink();

    // ... dentro do build ...

    // ... dentro do build ...

    // ... dentro do build ...

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.cyanNeon, size: 16),
              const SizedBox(width: 8),
              Text(
                "ANÁLISE E ESTRATÉGIA",
                style: AppTheme.titleStyle.copyWith(
                  fontSize: 10,
                  letterSpacing: 1,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          height: 135,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              // --- CARD DE ANÁLISE (CARROSSEL CONTROLADO) ---
              if (_portfolioInsights.isNotEmpty)
                Container(
                  width: 260,
                  margin: const EdgeInsets.only(right: 12),
                  child: PageView.builder(
                    controller: _insightPageController,
                    physics: const BouncingScrollPhysics(),
                    // Usamos um número grande ou o length exato.
                    // Se quiser loop infinito real, use null no itemCount e index % length no builder.
                    // Aqui mantive simples conforme seu código anterior:
                    itemCount: _portfolioInsights.length,
                    itemBuilder: (context, index) {
                      // Garante que não quebre se o índice global dessincronizar
                      final safeIndex = index % _portfolioInsights.length;
                      final insight = _portfolioInsights[safeIndex];
                      final color = _getInsightColor(insight.type);

                      return Container(
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withOpacity(0.25), const Color(0xFF1E1E24)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
                          boxShadow: [
                            BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 4)),
                          ],
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb, color: color, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  insight.type == 'risk' ? "RISCO" : "OPORTUNIDADE",
                                  style: TextStyle(
                                    color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1,
                                  ),
                                ),
                                const Spacer(),
                                if (_portfolioInsights.length > 1)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                                    child: Text(
                                      // Mostra índice baseado no global para ficar consistente
                                      "${safeIndex + 1}/${_portfolioInsights.length}",
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  )
                              ],
                            ),
                            const Spacer(),
                            Text(
                              insight.title,
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14, height: 1.2, fontFamily: 'Outfit'),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              insight.message,
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              // --- CARD DO IR (GATILHO NO RETORNO) ---
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TaxReportScreen()),
                  ).then((_) {
                    // <--- AQUI ESTÁ O SEGREDO
                    // Quando voltar da tela de IR, avança o carrossel
                    _advanceInsight();
                  });
                },
                child: Container(
                  width: 130,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.cyanNeon.withOpacity(0.15), const Color(0xFF1E1E24)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.3)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.cyanNeon.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.pets, color: AppTheme.cyanNeon, size: 24),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Relatório IR",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSingleAssetCard(
      Map<String, dynamic> asset, {
        bool isCompact = false,
        bool isClickable = true,
      }) {
    final name = asset['name']?.toString() ?? 'Ativo';
    final type = asset['type']?.toString() ?? 'OUTROS';
    final value = (asset['value'] as num?)?.toDouble() ?? 0.0;

    final purchasePrice = (asset['purchase_price'] as num?)?.toDouble() ?? 0.0;
    final qty = (asset['quantity'] as num?)?.toDouble() ?? 0.0;

    double totalCost = 0.0;
    if (asset['average_price'] != null && (asset['average_price'] as num) > 0) {
      totalCost = (asset['average_price'] as num).toDouble() * qty;
    } else {
      totalCost = purchasePrice;
    }

    double gain = value - totalCost;
    if (totalCost == 0) gain = 0;

    bool isPositive = gain >= 0;
    String engagementText;

    if (gain == 0) {
      engagementText = "Posição Consolidada";
    } else if (isPositive) {
      engagementText = "Valorizou ${_formatCurrency(gain)}";
    } else {
      engagementText = "Desvalorizou ${_formatCurrency(gain.abs())}";
    }

    IconData icon;
    Color glowColor;
    String categoryLabel;

    if (type == 'CARRO' || type == 'VEHICLE' || type == 'MOTO') {
      icon = Icons.directions_car_filled_rounded;
      glowColor = Colors.purpleAccent;
      categoryLabel = "Veículo";
    } else if (type == 'ACAO' || type == 'STOCK') {
      icon = Icons.candlestick_chart_rounded;
      glowColor = Colors.greenAccent;
      categoryLabel = "Renda Variável";
    } else if (type == 'IMOVEL' || type == 'REAL_ESTATE') {
      icon = Icons.location_city_rounded;
      glowColor = Colors.orangeAccent;
      categoryLabel = "Imóvel";
    } else {
      icon = Icons.account_balance_wallet_rounded;
      glowColor = AppTheme.cyanNeon;
      categoryLabel = "Ativo";
    }

    return GlassCard(
      opacity: 0.1,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  glowColor.withOpacity(0.1),
                  Colors.black.withOpacity(0.3),
                ],
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.all(isCompact ? 20 : 30),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: glowColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              categoryLabel.toUpperCase(),
                              style: TextStyle(
                                color: glowColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          if (isClickable) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.open_in_full_rounded,
                              size: 12,
                              color: Colors.white24,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      Text(
                        name,
                        style: AppTheme.titleStyle.copyWith(
                          fontSize: isCompact ? 18 : 24,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      Text(
                        _formatCurrency(value),
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: isCompact ? 16 : 20,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Icon(
                            isPositive ? Icons.trending_up : Icons.shield,
                            color: isPositive
                                ? Colors.greenAccent
                                : Colors.grey,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            engagementText,
                            style: TextStyle(
                              color: isPositive
                                  ? Colors.greenAccent
                                  : Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Expanded(
                  flex: 2,
                  child: SlideTransition(
                    position: _hoverAnimation,
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.all(isCompact ? 15 : 25),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: glowColor.withOpacity(0.6),
                              blurRadius: 50,
                              spreadRadius: 2,
                            ),
                          ],
                          gradient: LinearGradient(
                            colors: [
                              glowColor.withOpacity(0.4),
                              Colors.transparent,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: isCompact ? 40 : 70,
                          color: Colors.white,
                        ),
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

  Widget _buildDividendHighlight({bool isWeb = false}) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DividendsScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.greenAccent,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(
                  "Proventos ($_currentMonthName)",
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            Text(
              _formatCurrency(_dividendsThisMonth),
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: isWeb ? 18 : 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () {
            _easterEggCounter++;
            if (_easterEggCounter >= 6) {
              _easterEggCounter = 0;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminErrorsScreen(),
                ),
              );
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "PERPETUUM",
                style: AppTheme.titleStyle.copyWith(
                  fontSize: 12,
                  letterSpacing: 3,
                  color: AppTheme.cyanNeon,
                ),
              ),
              const SizedBox(height: 4),
              Text("Visão Geral", style: AppTheme.bodyStyle),
            ],
          ),
        ),

        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child: Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: CircleAvatar(
              backgroundColor: Colors.black,
              backgroundImage: _avatarUrl != null
                  ? NetworkImage(_avatarUrl!)
                  : null,
              child: _avatarUrl == null
                  ? const Icon(Icons.person, color: Colors.white, size: 20)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalBalance({bool isWeb = false}) {
    final growthColor = _growthPercentage >= 0
        ? AppTheme.cyanNeon
        : Colors.redAccent;
    final fontSize = isWeb ? 56.0 : 36.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Patrimônio Líquido",
          style: TextStyle(color: Colors.white54, fontSize: isWeb ? 16 : 14),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _formattedMoney,
              style: TextStyle(
                fontFamily: 'Outfit',
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: -1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _growthPercentage >= 0 ? Icons.trending_up : Icons.trending_down,
              color: growthColor,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              "Consolidado",
              style: TextStyle(
                color: growthColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChartContainer({required double height}) {
    double maxY = 100;
    if (_chartSpots.isNotEmpty) {
      double maxVal = _chartSpots
          .map((e) => e.y)
          .reduce((a, b) => a > b ? a : b);
      maxY = maxVal > 0 ? maxVal * 1.2 : 100;
    }

    return SizedBox(
      height: height,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 10),
        opacity: 0.05,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Evolução",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "5 ANOS",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: LineChart(
                LineChartData(
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBgColor: const Color(0xFF1E1E1E),
                      getTooltipItems: (spots) => spots
                          .map(
                            (spot) => LineTooltipItem(
                          _formatCurrency(spot.y),
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                          .toList(),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (val) => FlLine(
                      color: Colors.white.withOpacity(0.05),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (val, _) {
                          int idx = val.toInt();
                          if (idx < 0 || idx > 4)
                            return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              (DateTime.now().year - (4 - idx)).toString(),
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  minX: 0,
                  maxX: 4,
                  minY: 0,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: _chartSpots,
                      isCurved: true,
                      curveSmoothness: 0.4,
                      color: AppTheme.cyanNeon,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.cyanNeon.withOpacity(0.2),
                            AppTheme.cyanNeon.withOpacity(0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutQuart,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        _buildSquareButton(
          Icons.upload_file_rounded,
          "Importar",
              () => _showImportOptions(context),
        ),
        const SizedBox(width: 12),
        _buildSquareButton(
          Icons.add_circle_outline_rounded,
          "Novo Bem",
              () => _showAddSelector(context),
          isPrimary: true,
        ),
        const SizedBox(width: 12),
        _buildSquareButton(
          Icons.pie_chart_outline_rounded,
          "Alocação",
              () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AllocationScreen()),
          ).then((_) => _loadData()),
        ),
      ],
    );
  }

  // --- NOVO CARD DO LEÃO (IR) ---
  Widget _buildIrLionCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TaxReportScreen()),
        );
      },
      child: Container(
        // Usando margem similar aos outros cards para consistência
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // Gradiente sutil misturando o fundo escuro com um toque do neon
          gradient: LinearGradient(
            colors: [
              AppTheme.cyanNeon.withOpacity(0.15),
              const Color(0xFF1E1E24)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          // Borda fina e elegante
          border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.cyanNeon.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Ícone do Leão em destaque
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cyanNeon.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.2)),
              ),
              // USANDO O ÍCONE DO PACOTE FONT AWESOME
              child: const FaIcon(FontAwesomeIcons.paw, color: AppTheme.cyanNeon, size: 26),
            ),
            const SizedBox(width: 20),
            // Textos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "ÁREA FISCAL",
                    style: TextStyle(
                        color: AppTheme.cyanNeon,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Relatório para o Leão",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Custos de aquisição e textos prontos para copiar.",
                    style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
            // Seta indicativa
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle
                ),
                child: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSquareButton(
      IconData icon,
      String label,
      VoidCallback onTap, {
        bool isPrimary = false,
      }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 90,
          decoration: BoxDecoration(
            color: isPrimary
                ? AppTheme.cyanNeon.withOpacity(0.1)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isPrimary
                  ? AppTheme.cyanNeon.withOpacity(0.5)
                  : Colors.white10,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isPrimary ? AppTheme.cyanNeon : Colors.white,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? AppTheme.cyanNeon : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: 600,
        margin: const EdgeInsets.all(16),
        child: GlassCard(
          opacity: 0.2,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Adicionar Patrimônio",
                style: AppTheme.titleStyle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 24),

              _buildOptionTile(
                context,
                icon: Icons.show_chart_rounded,
                title: "Ativo Financeiro",
                subtitle: "Ações, FIIs, Tesouro, Renda Fixa",
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddAssetFinanceiroScreen(
                        assetType: 'financeiro',
                      ),
                    ),
                  ).then((_) => _loadData());
                },
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                context,
                icon: Icons.directions_car_rounded,
                title: "Carro",
                subtitle: "Automóveis de passeio ou trabalho",
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddAssetScreen(assetType: 'carros'),
                    ),
                  ).then((_) => _loadData());
                },
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                context,
                icon: Icons.two_wheeler_rounded,
                title: "Moto",
                subtitle: "Motocicletas e veículos de duas rodas",
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddAssetScreen(assetType: 'motos'),
                    ),
                  ).then((_) => _loadData());
                },
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                context,
                icon: Icons.home_work_rounded,
                title: "Imóvel",
                subtitle: "Casas, apartamentos ou salas comerciais",
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                      const AddAssetScreen(assetType: 'imoveis'),
                    ),
                  ).then((_) => _loadData());
                },
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                context,
                icon: Icons.landscape_rounded,
                title: "Terreno",
                subtitle: "Lotes, áreas rurais ou urbanas",
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                      const AddAssetScreen(assetType: 'terrenos'),
                    ),
                  ).then((_) => _loadData());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: 650,
        margin: const EdgeInsets.all(16),
        child: GlassCard(
          opacity: 0.2,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Fonte de Dados",
                style: AppTheme.titleStyle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 24),
              _buildOptionTile(
                context,
                icon: Icons.description_outlined,
                title: "Declaração de IR",
                subtitle: "PDF oficial",
                onTap: () => _navigateToImport(context, ImportType.irpf),
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                context,
                icon: Icons.candlestick_chart_rounded,
                title: "B3 - Área do Investidor",
                subtitle: "Planilha Excel",
                onTap: () => _navigateToImport(context, ImportType.b3),
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                context,
                icon: Icons.image_search_rounded,
                title: "Leitura de Print",
                subtitle: "Reconhecimento via Imagem",
                onTap: () => _navigateToImport(context, ImportType.print),
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                context,
                icon: Icons.file_download_outlined,
                title: "Baixar Modelo de Planilha",
                subtitle: "Gere um arquivo Excel pronto para preencher",
                onTap: () async {
                  final generator = ExcelGeneratorService();
                  await generator.generateAndDownloadTemplate();
                },
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.cyanNeon.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.1)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.cyanNeon, size: 16),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "DICA: O modelo de planilha facilita a organização de dados manuais ou de corretoras não suportadas. Preencha e importe via opção 'B3'.",
                        style: TextStyle(color: Colors.white60, fontSize: 10, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.cyanNeon, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.titleStyle.copyWith(fontSize: 15),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToImport(BuildContext context, ImportType type) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ImportScreen(importType: type)),
    ).then((value) {
      _loadData();
    });
  }

  void _showRebalanceExplanation(String ticker, double gap, double needed) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lightbulb_outline, color: AppTheme.cyanNeon),
            const SizedBox(width: 10),
            Expanded(
              child: Text("Por que comprar $ticker?",
                  style: const TextStyle(color: Colors.white, fontSize: 18)
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Sua carteira está desbalanceada.",
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildExplanationRow("Defasagem (Gap):", "-${gap.toStringAsFixed(2)}%", Colors.redAccent),
            const SizedBox(height: 8),
            _buildExplanationRow("Aporte Necessário:", _formatCurrency(needed), AppTheme.cyanNeon),
            const SizedBox(height: 16),
            Text(
              "Este ativo está abaixo da porcentagem que você definiu nas metas. Aportar nele trará sua carteira de volta ao equilíbrio (Risco x Retorno ideal).",
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Entendi", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanationRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildRebalanceCard() {
    // CASO 1: Nenhuma meta ou ação detectada (Mostra botão de configuração)
    if (_rebalanceAction == null) {
      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RebalanceScreen()),
        ).then((_) => _loadData()),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.cyanNeon.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.tune, color: AppTheme.cyanNeon, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "INTELIGÊNCIA DE CARTEIRA",
                      style: TextStyle(
                          color: AppTheme.cyanNeon,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Definir Metas de Alocação",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Toque para configurar sua estratégia",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
            ],
          ),
        ),
      );
    }

    // CASO 2: Recomendação Ativa (Com botão de Informação)
    final String ticker = _rebalanceAction!['ticker'];
    final double gap = (_rebalanceAction!['gap'] as num).toDouble();
    final double needed = (_rebalanceAction!['needed'] as num).toDouble();
    final double progress = ((100 - gap) / 100).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RebalanceScreen()),
      ).then((_) => _loadData()),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.cyanNeon.withOpacity(0.15),
              Colors.black.withOpacity(0.2)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    color: AppTheme.cyanNeon,
                    backgroundColor: Colors.white10,
                  ),
                ),
                const Icon(Icons.shopping_cart_outlined,
                    color: Colors.white, size: 20),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- LINHA DO TÍTULO COM O ÍCONE 'i' ---
                  Row(
                    children: [
                      Text(
                        "OPORTUNIDADE DE APORTE",
                        style: TextStyle(
                            color: AppTheme.cyanNeon,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            letterSpacing: 1),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _showRebalanceExplanation(ticker, gap, needed),
                        child: Icon(Icons.info_outline,
                            color: AppTheme.cyanNeon.withOpacity(0.8),
                            size: 14
                        ),
                      ),
                    ],
                  ),
                  // ---------------------------------------
                  const SizedBox(height: 4),
                  Text(
                    "$ticker está ${gap.toStringAsFixed(1)}% abaixo da meta",
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Aporte sugerido: ${_formatCurrency(needed)}",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }
}

// --- NOVO WIDGET: BARRA DE PESQUISA INTELIGENTE (IA) ---
class AiSearchWidget extends StatefulWidget {
  const AiSearchWidget({Key? key}) : super(key: key);

  @override
  State<AiSearchWidget> createState() => _AiSearchWidgetState();
}

class _AiSearchWidgetState extends State<AiSearchWidget> {
  final TextEditingController _controller = TextEditingController();
  final AiEngineService _aiService = AiEngineService();
  bool _isAnalyzing = false;

  void _submitQuery() async {
    if (_controller.text.isEmpty) return;

    final query = _controller.text;
    _controller.clear();
    FocusScope.of(context).unfocus();

    setState(() => _isAnalyzing = true);

    // Processa na lógica interna de ML (Feedback Loop)
    final result = await _aiService.processQuery(query);

    setState(() => _isAnalyzing = false);

    _showAiResult(query, result);
  }

  void _showAiResult(String question, Map<String, dynamic> result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite que o modal ocupe mais espaço se necessário
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        // Define uma altura máxima de 85% da tela para não cobrir o topo
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppTheme.cyanNeon, size: 20),
                const SizedBox(width: 8),
                Text(
                  "INSIGHT DA IA",
                  style: TextStyle(
                    color: AppTheme.cyanNeon,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Pergunta do usuário
            Text(
              question,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white10),
            const SizedBox(height: 12),

            // --- CORREÇÃO AQUI ---
            // Usamos Flexible + SingleChildScrollView para permitir rolagem
            // apenas no texto da resposta, mantendo o botão fixo embaixo.
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  result['content'],
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            // ---------------------

            const SizedBox(height: 24),

            // Botão fixo no rodapé
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("Entendido", style: TextStyle(color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withOpacity(0.1),
            AppTheme.cyanNeon.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined, color: Colors.purpleAccent, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Como posso ajudar hoje?",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (_isAnalyzing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.cyanNeon,
                  ),
                )
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            onSubmitted: (_) => _submitQuery(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Ex: Qual meu melhor ativo para vender?",
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 13,
              ),
              filled: true,
              fillColor: Colors.black26,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded, color: AppTheme.cyanNeon, size: 20),
                onPressed: _submitQuery,
              ),
            ),
          ),
        ],
      ),
    );
  }

}