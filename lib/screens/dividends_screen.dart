import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../services/dividend_service.dart';
import '../services/cloud_service.dart';

class DividendsScreen extends StatefulWidget {
  const DividendsScreen({Key? key}) : super(key: key);

  @override
  State<DividendsScreen> createState() => _DividendsScreenState();
}

class _DividendsScreenState extends State<DividendsScreen> with SingleTickerProviderStateMixin {
  final DividendService _service = DividendService();
  final CloudService _cloud = CloudService();
  late TabController _tabController;

  bool _isLoading = true;

  // Listas de Dados
  List<Map<String, dynamic>> _allPast = [];
  List<Map<String, dynamic>> _allFuture = [];
  List<Map<String, dynamic>> _aiPredictions = [];

  Map<String, double> _assetBalances = {};

  DateTime? _selectedDate;
  double _totalReceived = 0.0;
  double _totalFuture = 0.0;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('pt_BR', null);
    _tabController = TabController(length: 2, vsync: this);

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _setDefaultSelection();
        });
      }
    });

    _loadData();
  }

  // Helper para limpar tickers e unificar fracionários
  String _cleanTicker(String ticker) {
    String t = ticker.toUpperCase().trim();
    if (t.length > 4 && t.endsWith('F')) {
      return t.substring(0, t.length - 1);
    }
    return t;
  }

  void _setDefaultSelection() {
    bool isFuture = _tabController.index == 1;
    List<Map<String, dynamic>> source = isFuture ? _allFuture : _allPast;

    if (source.isNotEmpty) {
      source.sort((a, b) => a['date'].compareTo(b['date']));
      _selectedDate = isFuture ? source.first['date'] : source.last['date'];
    } else if (isFuture && _aiPredictions.isNotEmpty) {
      _aiPredictions.sort((a, b) => a['predicted_date'].compareTo(b['predicted_date']));
      _selectedDate = DateTime.parse(_aiPredictions.first['predicted_date']);
    } else {
      _selectedDate = DateTime.now();
    }
  }

  // --- CARREGAMENTO DE DADOS ---
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    List<Map<String, dynamic>> pastRaw = [];
    List<Map<String, dynamic>> futureRaw = [];
    List<Map<String, dynamic>> aiRaw = [];
    Map<String, double> balances = {};

    try {
      // 1. Busca Saldo Real Consolidado para filtrar ativos vendidos
      final portfolio = await _cloud.getConsolidatedPortfolio();
      for (var asset in portfolio['assets']) {
        String ticker = _cleanTicker(asset['ticker'].toString());
        balances[ticker] = (balances[ticker] ?? 0) + (asset['quantity'] as num).toDouble();
      }

      // 2. Busca Proventos Oficiais
      final data = await _service.getUserDividends();

      Map<String, dynamic> normalizeItem(Map<String, dynamic> item) {
        if (item['date'] is String) item['date'] = DateTime.parse(item['date']);
        item['ticker'] = _cleanTicker(item['ticker'].toString());

        // Tradução de tipos para o usuário
        String type = item['type']?.toString().toUpperCase() ?? 'PROVENTO';
        if (type.contains('DIVIDENDO')) item['display_type'] = 'Dividendo';
        else if (type.contains('JCP') || type.contains('JUROS')) item['display_type'] = 'JCP';
        else if (type.contains('RENDIMENTO')) item['display_type'] = 'Rendimento';
        else item['display_type'] = 'Provento';

        return item;
      }

      pastRaw = List<Map<String, dynamic>>.from(data['past'] ?? []).map(normalizeItem).toList();
      futureRaw = List<Map<String, dynamic>>.from(data['future'] ?? []).map(normalizeItem).toList();

      // 3. Busca Previsões da IA
      try {
        final aiResponse = await Supabase.instance.client
            .from('ai_predictions')
            .select()
            .gte('predicted_date', DateTime.now().toIso8601String());

        aiRaw = List<Map<String, dynamic>>.from(aiResponse).map((item) {
          item['ticker'] = _cleanTicker(item['ticker'].toString());
          return item;
        }).toList();
      } catch (e) {
        debugPrint("Aviso: Sem dados de IA: $e");
      }

      // 4. Totais (Apenas ativos em carteira)
      double sumPast = pastRaw.where((item) => balances.containsKey(item['ticker']) && balances[item['ticker']]! > 0)
          .fold(0.0, (sum, item) => sum + (item['total_value'] as num).toDouble());

      double sumFuture = futureRaw.where((item) => balances.containsKey(item['ticker']) && balances[item['ticker']]! > 0)
          .fold(0.0, (sum, item) => sum + (item['total_value'] as num).toDouble());

      if (mounted) {
        setState(() {
          _allPast = pastRaw;
          _allFuture = futureRaw;
          _aiPredictions = aiRaw;
          _assetBalances = balances;
          _totalReceived = sumPast;
          _totalFuture = sumFuture;
          _isLoading = false;
          _setDefaultSelection();
        });
      }

    } catch (e) {
      debugPrint("Erro CRÍTICO ao carregar: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatMoney(double value) => NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);

  // --- BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    bool isFuture = _tabController.index == 1;
    double monthlyTotal = 0.0;

    if (_selectedDate != null) {
      String target = DateFormat('MM/yyyy').format(_selectedDate!);
      if (isFuture) {
        monthlyTotal += _allFuture.where((e) => DateFormat('MM/yyyy').format(e['date']) == target && _assetBalances.containsKey(e['ticker']) && _assetBalances[e['ticker']]! > 0)
            .fold(0.0, (sum, i) => sum + (i['total_value'] as num).toDouble());

        monthlyTotal += _aiPredictions.where((e) => DateFormat('MM/yyyy').format(DateTime.parse(e['predicted_date'])) == target && _assetBalances.containsKey(e['ticker']) && _assetBalances[e['ticker']]! > 0)
            .fold(0.0, (sum, i) => sum + (i['predicted_amount'] as num).toDouble());
      } else {
        monthlyTotal += _allPast.where((e) => DateFormat('MM/yyyy').format(e['date']) == target && _assetBalances.containsKey(e['ticker']) && _assetBalances[e['ticker']]! > 0)
            .fold(0.0, (sum, i) => sum + (i['total_value'] as num).toDouble());
      }
    }

    var topPayerData = _getTopPayerForSelectedMonth();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned(
            top: -50, right: -100,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isFuture ? Colors.amber : AppTheme.cyanNeon).withOpacity(0.15),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                const SizedBox(height: 10),
                SizedBox(
                  height: 200,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildInteractiveChart(isFuture),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                          child: _insightCard(
                              "Total em ${DateFormat('MMM', 'pt_BR').format(_selectedDate ?? DateTime.now())}",
                              monthlyTotal,
                              isFuture ? Colors.amber : AppTheme.cyanNeon,
                              Icons.calendar_month
                          )
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _insightCard(
                              "Maior Pagadora",
                              topPayerData['value'],
                              Colors.white,
                              Icons.star,
                              subtitle: topPayerData['ticker']
                          )
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                _buildTabBar(),

                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanNeon))
                      : _buildFilteredList(isFuture),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- MÉTODOS DE UI (HELPERS) ---

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(backgroundColor: Colors.white10, padding: const EdgeInsets.all(8)),
          ),
          const Expanded(
            child: Center(
              child: Text("Meus Proventos",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _insightCard(String label, double value, Color color, IconData icon, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white24, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 6),
          if (subtitle != null) ...[
            Text(subtitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            Text(_formatMoney(value), style: TextStyle(color: color.withOpacity(0.7), fontSize: 11)),
          ] else
            Text(_formatMoney(value), style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 50,
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white10),
        ),
        child: TabBar(
          controller: _tabController,
          labelPadding: const EdgeInsets.symmetric(horizontal: 30),
          padding: const EdgeInsets.all(4),
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
              color: _tabController.index == 0 ? AppTheme.cyanNeon : Colors.amber,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                    color: (_tabController.index == 0 ? AppTheme.cyanNeon : Colors.amber).withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2)
                )
              ]
          ),
          labelColor: Colors.black,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          isScrollable: true,
          onTap: (index) => setState(() {}),
          tabs: const [
            Tab(text: "HISTÓRICO"),
            Tab(text: "AGENDA FUTURA"),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveChart(bool isFuture) {
    List<MapEntry<DateTime, double>> data = _getChartData();
    if (data.isEmpty) {
      return Center(
        child: Text(
          isFuture ? "Sem previsões futuras" : "Sem histórico recente",
          style: const TextStyle(color: Colors.white24),
        ),
      );
    }
    double maxY = data.map((e) => e.value).reduce(max);
    if (maxY == 0) maxY = 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isFuture ? "Projeção (12 Meses)" : "Histórico (6 Meses)",
                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)
              ),
              if(isFuture)
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 10),
                    SizedBox(width: 4),
                    Text("IA Integrada", style: TextStyle(color: Colors.purpleAccent, fontSize: 10))
                  ],
                )
            ],
          ),
          const SizedBox(height: 15),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.map((entry) {
                bool isSelected = _selectedDate != null &&
                    entry.key.month == _selectedDate!.month &&
                    entry.key.year == _selectedDate!.year;
                double percentage = entry.value / maxY;

                Color barColor = isFuture ? Colors.amber : AppTheme.cyanNeon;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = entry.key;
                    });
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: isSelected ? 12 : 8,
                        height: max(4, 80 * percentage),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? barColor
                              : barColor.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: isSelected ? [BoxShadow(color: barColor.withOpacity(0.5), blurRadius: 10)] : [],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(DateFormat('MMM', 'pt_BR').format(entry.key).toUpperCase().replaceAll('.', ''),
                          style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white38,
                              fontSize: 9,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                          )
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // --- LÓGICA DE LISTAGEM ---

  Widget _buildFilteredList(bool isFuture) {
    if (_selectedDate == null) return const Center(child: Text("Selecione um mês no gráfico", style: TextStyle(color: Colors.white24)));

    String targetMonth = DateFormat('MM/yyyy').format(_selectedDate!);
    List<Widget> children = [];

    if (!isFuture) {
      // HISTÓRICO
      List<Map<String, dynamic>> items = _allPast.where((item) {
        return DateFormat('MM/yyyy').format(item['date']) == targetMonth &&
            _assetBalances.containsKey(item['ticker']) && _assetBalances[item['ticker']]! > 0;
      }).toList();
      items.sort((a, b) => a['date'].compareTo(b['date']));

      for (var item in items) {
        children.add(_buildListItem(item, false));
      }
    } else {
      // FUTURO (Oficial + IA)
      List<Map<String, dynamic>> officialItems = _allFuture.where((item) {
        return DateFormat('MM/yyyy').format(item['date']) == targetMonth &&
            _assetBalances.containsKey(item['ticker']) && _assetBalances[item['ticker']]! > 0;
      }).toList();

      List<Map<String, dynamic>> aiItems = _aiPredictions.where((item) {
        DateTime d = DateTime.parse(item['predicted_date']);
        return DateFormat('MM/yyyy').format(d) == targetMonth &&
            _assetBalances.containsKey(item['ticker']) && _assetBalances[item['ticker']]! > 0;
      }).toList();

      for (var official in officialItems) {
        String ticker = official['ticker'];
        Map<String, dynamic>? matchingPrediction;
        try {
          matchingPrediction = aiItems.firstWhere((ai) => ai['ticker'] == ticker);
          aiItems.remove(matchingPrediction);
        } catch (_) {}

        children.add(_buildListItem(official, true, predictionMatch: matchingPrediction));
      }

      for (var prediction in aiItems) {
        children.add(AiPredictionCard(
            item: prediction,
            onTap: () => _showAiDetails(prediction)
        ));
      }
    }

    if (children.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 40, color: Colors.white10),
            const SizedBox(height: 10),
            Text("Sem eventos em ${DateFormat('MMMM', 'pt_BR').format(_selectedDate!)}", style: const TextStyle(color: Colors.white30)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: children,
    );
  }

  // --- HELPERS LÓGICOS ---

  Map<String, dynamic> _getTopPayerForSelectedMonth() {
    if (_selectedDate == null) return {'ticker': '-', 'value': 0.0};

    String target = DateFormat('MM/yyyy').format(_selectedDate!);
    Map<String, double> totals = {};

    void add(String ticker, double val) {
      totals[ticker] = (totals[ticker] ?? 0.0) + val;
    }

    if (_tabController.index == 1) {
      for (var item in _allFuture) {
        if (DateFormat('MM/yyyy').format(item['date']) == target && _assetBalances.containsKey(item['ticker']) && _assetBalances[item['ticker']]! > 0) {
          add(item['ticker'], (item['total_value'] as num).toDouble());
        }
      }

      Set<String> officialTickers = _allFuture
          .where((i) => DateFormat('MM/yyyy').format(i['date']) == target)
          .map((i) => i['ticker'] as String).toSet();

      for (var item in _aiPredictions) {
        DateTime d = DateTime.parse(item['predicted_date']);
        if (DateFormat('MM/yyyy').format(d) == target && _assetBalances.containsKey(item['ticker']) && _assetBalances[item['ticker']]! > 0) {
          if (!officialTickers.contains(item['ticker'])) {
            add(item['ticker'], (item['predicted_amount'] as num).toDouble());
          }
        }
      }
    } else {
      for (var item in _allPast) {
        if (DateFormat('MM/yyyy').format(item['date']) == target && _assetBalances.containsKey(item['ticker']) && _assetBalances[item['ticker']]! > 0) {
          add(item['ticker'], (item['total_value'] as num).toDouble());
        }
      }
    }

    if (totals.isEmpty) return {'ticker': '-', 'value': 0.0};

    var sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {'ticker': sorted.first.key, 'value': sorted.first.value};
  }

  List<MapEntry<DateTime, double>> _getChartData() {
    bool isFuture = _tabController.index == 1;
    List<Map<String, dynamic>> source = [];

    if (isFuture) {
      for (var f in _allFuture) {
        if (_assetBalances.containsKey(f['ticker']) && _assetBalances[f['ticker']]! > 0) {
          source.add(f);
        }
      }
      for (var ai in _aiPredictions) {
        if (_assetBalances.containsKey(ai['ticker']) && _assetBalances[ai['ticker']]! > 0) {
          source.add({
            'date': DateTime.parse(ai['predicted_date']),
            'total_value': (ai['predicted_amount'] as num).toDouble()
          });
        }
      }
    } else {
      for (var p in _allPast) {
        if (_assetBalances.containsKey(p['ticker']) && _assetBalances[p['ticker']]! > 0) {
          source.add(p);
        }
      }
    }

    Map<String, double> grouped = {};
    Map<String, DateTime> dateReference = {};

    for (var item in source) {
      DateTime d = item['date'];
      DateTime normalizedDate = DateTime(d.year, d.month, 1);
      String key = normalizedDate.toIso8601String();

      grouped[key] = (grouped[key] ?? 0) + (item['total_value'] as num).toDouble();
      dateReference[key] = normalizedDate;
    }

    List<MapEntry<DateTime, double>> entries = [];
    grouped.forEach((key, value) {
      entries.add(MapEntry(dateReference[key]!, value));
    });

    entries.sort((a, b) => a.key.compareTo(b.key));

    if (entries.isNotEmpty) {
      if (isFuture) {
        final now = DateTime.now();
        return entries.where((e) => e.key.isAfter(now.subtract(const Duration(days: 20))))
            .take(12)
            .toList();
      } else {
        if (entries.length > 6) {
          return entries.sublist(entries.length - 6);
        }
        return entries;
      }
    }
    return entries;
  }

  num _getSmartQuantity(String ticker) {
    String t = ticker.toUpperCase().trim();
    return _assetBalances[t] ?? 0;
  }

  // --- CARDS E DIALOGS ---

  Widget _buildListItem(Map<String, dynamic> item, bool isFuture, {Map<String, dynamic>? predictionMatch}) {
    DateTime date = item['date'];
    String day = DateFormat('dd').format(date);
    double total = (item['total_value'] as num).toDouble();
    String ticker = item['ticker'];
    String displayType = item['display_type'] ?? 'Provento';

    return GestureDetector(
      onTap: () => _showDetails(item, isFuture),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.02)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white10, width: 1))),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(day, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(DateFormat('EEE', 'pt_BR').format(date).toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 9)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: isFuture ? Colors.amber.withOpacity(0.1) : AppTheme.cyanNeon.withOpacity(0.1),
                  radius: 16,
                  child: Text(ticker.isNotEmpty ? ticker[0] : '?', style: TextStyle(color: isFuture ? Colors.amber : AppTheme.cyanNeon, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ticker, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(displayType, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
                Text(_formatMoney(total), style: TextStyle(color: isFuture ? Colors.amber : AppTheme.cyanNeon, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            if (predictionMatch != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 52),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 10, color: Colors.purpleAccent),
                    const SizedBox(width: 4),
                    Text(
                      "IA previu ${_formatMoney((predictionMatch['predicted_amount'] as num).toDouble())} • Confirmado!",
                      style: const TextStyle(color: Colors.purpleAccent, fontSize: 10, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> item, bool isFuture) {
    DateTime date = item['date'];
    double total = (item['total_value'] as num).toDouble();
    String ticker = item['ticker'];
    double unitPrice = (item['unit_value'] as num?)?.toDouble() ?? 0.0;
    num currentQty = _getSmartQuantity(ticker);
    String displayType = (item['display_type'] ?? 'PROVENTO').toUpperCase();

    if (currentQty > 0) {
      if (unitPrice == 0) unitPrice = total / currentQty;
    } else {
      if (unitPrice > 0) currentQty = (total / unitPrice).round();
    }

    _showGenericDialog(ticker, displayType, date, unitPrice, currentQty, total, isFuture ? Colors.amber : AppTheme.cyanNeon);
  }

  void _showAiDetails(Map<String, dynamic> item) {
    DateTime date = DateTime.parse(item['predicted_date']);
    double total = (item['predicted_amount'] as num).toDouble();
    String ticker = item['ticker'];
    num currentQty = _getSmartQuantity(ticker);
    double estimatedUnit = currentQty > 0 ? total / currentQty : 0.0;

    _showGenericDialog(ticker, "PREVISÃO IA", date, estimatedUnit, currentQty, total, Colors.purpleAccent, isAi: true);
  }

  void _showGenericDialog(String ticker, String type, DateTime date, double unit, num qty, double total, Color color, {bool isAi = false}) {
    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E1E24).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: color.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)
                  ]
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: color.withOpacity(0.1),
                    child: Text(ticker.isNotEmpty ? (ticker.length > 4 ? ticker.substring(0,4) : ticker) : '?',
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(ticker, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isAi) const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 12),
                      if (isAi) const SizedBox(width: 4),
                      Text(type, style: const TextStyle(color: Colors.white54, letterSpacing: 1.5, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildDetailRow(isAi ? "Data Estimada" : "Data do Pagamento", DateFormat('dd/MM/yyyy').format(date)),
                  const Divider(color: Colors.white10),
                  _buildDetailRow("Valor Unitário", _formatMoney(unit)),
                  const Divider(color: Colors.white10),
                  _buildDetailRow("Posição em Carteira", "$qty ações"),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isAi ? "TOTAL ESTIMADO" : "TOTAL RECEBIDO", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(_formatMoney(total), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12)
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Fechar", style: TextStyle(color: Colors.white)),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// --- CLASSES AUXILIARES ---

class AiPredictionCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const AiPredictionCard({Key? key, required this.item, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    DateTime date = DateTime.parse(item['predicted_date']);
    double amount = (item['predicted_amount'] as num).toDouble();
    double confidence = (item['confidence_score'] as num).toDouble();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: CustomPaint(
          painter: DashedRectPainter(color: Colors.purpleAccent, strokeWidth: 1.0, gap: 4),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Text(DateFormat('dd').format(date), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(DateFormat('MMM', 'pt_BR').format(date).toUpperCase().replaceAll('.', ''), style: const TextStyle(color: Colors.white38, fontSize: 9)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(item['ticker'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(color: Colors.purpleAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                            child: const Text("ESTIMATIVA", style: TextStyle(fontSize: 8, color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                      Text("Confiança: ${(confidence * 100).toInt()}%", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
                Text("~ ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(amount)}",
                    style: const TextStyle(
                        color: Colors.purpleAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontStyle: FontStyle.italic
                    )
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashedRectPainter extends CustomPainter {
  final double strokeWidth;
  final Color color;
  final double gap;

  DashedRectPainter({this.strokeWidth = 1.0, this.color = Colors.red, this.gap = 5.0});

  @override
  void paint(Canvas canvas, Size size) {
    Paint dashedPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    double x = size.width;
    double y = size.height;

    Path _topPath = getDashedPath(a: const Offset(0, 0), b: Offset(x, 0), gap: gap);
    Path _rightPath = getDashedPath(a: Offset(x, 0), b: Offset(x, y), gap: gap);
    Path _bottomPath = getDashedPath(a: Offset(0, y), b: Offset(x, y), gap: gap);
    Path _leftPath = getDashedPath(a: const Offset(0, 0), b: Offset(0, y), gap: gap);

    canvas.drawPath(_topPath, dashedPaint);
    canvas.drawPath(_rightPath, dashedPaint);
    canvas.drawPath(_bottomPath, dashedPaint);
    canvas.drawPath(_leftPath, dashedPaint);
  }

  Path getDashedPath({required Offset a, required Offset b, required double gap}) {
    Path path = Path();
    path.moveTo(a.dx, a.dy);
    bool shouldDraw = true;
    Offset currentPoint = a;

    double radians = atan2(b.dy - a.dy, b.dx - a.dx);
    double dx = gap * cos(radians);
    double dy = gap * sin(radians);

    while ((b.dx - currentPoint.dx).abs() > gap || (b.dy - currentPoint.dy).abs() > gap) {
      if (shouldDraw) {
        path.lineTo(currentPoint.dx + dx, currentPoint.dy + dy);
      } else {
        path.moveTo(currentPoint.dx + dx, currentPoint.dy + dy);
      }
      shouldDraw = !shouldDraw;
      currentPoint = Offset(currentPoint.dx + dx, currentPoint.dy + dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}