import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/fipe_service.dart';
import '../services/cloud_service.dart';

class AddAssetScreen extends StatefulWidget {
  // Recebe o tipo direto da Home (carros, motos, imoveis, terrenos)
  final String assetType;

  const AddAssetScreen({Key? key, required this.assetType}) : super(key: key);

  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> with SingleTickerProviderStateMixin {
  final _fipeService = FipeService();
  final _cloudService = CloudService();

  late AnimationController _animController;
  late Animation<Offset> _slideAnimation; // Para formulário
  late Animation<double> _fadeAnimation;

  // Animação Específica do Ícone
  late Animation<Offset> _iconSlideAnim; // Carro andando
  late Animation<double> _iconScaleAnim; // Casa crescendo

  // Variáveis FIPE
  String? _selectedBrandId;
  String? _selectedModelId;
  String? _selectedYearId;
  List<Map<String, String>> _brands = [];
  List<Map<String, dynamic>> _models = [];
  List<Map<String, String>> _years = [];
  double? _fipeValue;
  String? _fipeCode;
  String? _fullModelName;

  // Variáveis Manuais
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _marketValueCtrl = TextEditingController();

  final _purchasePriceCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Entrada do Formulário (baixo para cima)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);

    // Animação do Ícone (Carro vem da esquerda)
    _iconSlideAnim = Tween<Offset>(
      begin: const Offset(-2.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.elasticOut));

    // Animação do Ícone (Casa escala do zero)
    _iconScaleAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOutBack);

    _animController.forward();

    // Já carrega dados se for veículo
    if (_isVehicle) {
      _loadBrands();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _marketValueCtrl.dispose();
    _purchasePriceCtrl.dispose();
    super.dispose();
  }

  bool get _isVehicle => widget.assetType == 'carros' || widget.assetType == 'motos';

  // --- LÓGICA FIPE ---
  Future<void> _loadBrands() async {
    try {
      final brands = await _fipeService.getBrands(widget.assetType);
      if (mounted) setState(() => _brands = brands);
    } catch (e) {
      debugPrint("Erro marcas: $e");
    }
  }

  Future<void> _loadModels(String brandId) async {
    setState(() {
      _selectedBrandId = brandId;
      _selectedModelId = null;
      _selectedYearId = null;
      _models = [];
      _years = [];
      _fipeValue = null;
      _isLoadingModels = true;
    });

    try {
      final models = await _fipeService.getModels(widget.assetType, brandId);
      if (mounted) setState(() => _models = models);
    } catch (e) {
      debugPrint("Erro modelos: $e");
    } finally {
      if (mounted) setState(() => _isLoadingModels = false);
    }
  }

  Future<void> _loadYears(String modelId) async {
    setState(() {
      _selectedModelId = modelId;
      _selectedYearId = null;
      _years = [];
      _fipeValue = null;
    });

    try {
      final years = await _fipeService.getYears(widget.assetType, _selectedBrandId!, modelId);
      if (mounted) setState(() => _years = years);
    } catch (e) {
      debugPrint("Erro anos: $e");
    }
  }

  Future<void> _fetchFipeData(String yearId) async {
    setState(() {
      _selectedYearId = yearId;
      _isLoading = true;
    });

    try {
      final details = await _fipeService.getFipeDetails(widget.assetType, _selectedBrandId!, _selectedModelId!, yearId);
      String priceStr = details['Valor'].toString();
      // Parse robusto de valor FIPE
      double price = _parseValue(priceStr);

      if (mounted) {
        setState(() {
          _fipeValue = price;
          _fipeCode = details['CodigoFipe'];
          _fullModelName = "${details['Marca']} ${details['Modelo']} ${details['AnoModelo']}";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- PARSER INTELIGENTE DE VALORES ---
  double _parseValue(String text) {
    if (text.isEmpty) return 0.0;
    // Remove R$ e espaços
    String clean = text.replaceAll('R\$', '').replaceAll(' ', '').trim();

    // Lógica para detectar padrão brasileiro (ponto milhar, vírgula decimal)
    if (clean.contains('.') && clean.contains(',')) {
      // Ex: 50.000,00 -> remove ponto, troca vírgula por ponto
      clean = clean.replaceAll('.', '').replaceAll(',', '.');
    }
    // Apenas ponto (pode ser milhar ou decimal, depende do contexto)
    else if (clean.contains('.')) {
      // Se tiver mais de um ponto (ex: 1.000.000) ou exatamente 3 casas decimais (padrão milhar comum), remove
      // Assumindo que input manual "50.000" é 50 mil
      if (clean.indexOf('.') != clean.lastIndexOf('.') || (clean.length - clean.indexOf('.') - 1) == 3) {
        clean = clean.replaceAll('.', '');
      }
    }
    // Apenas vírgula (padrão decimal BR)
    else if (clean.contains(',')) {
      clean = clean.replaceAll(',', '.');
    }

    return double.tryParse(clean) ?? 0.0;
  }

  // --- SALVAR ---
  Future<void> _save() async {
    setState(() => _isLoading = true);

    // Usa o parser inteligente para o preço de compra e valor de mercado
    final purchasePrice = _parseValue(_purchasePriceCtrl.text);

    try {
      String brandName = "";
      String modelName = "";
      String yearName = "";
      double currentValue = 0.0;
      String typeCode = "";

      if (_isVehicle) {
        if (_fipeValue == null) return;
        brandName = _brands.firstWhere((e) => e['codigo'] == _selectedBrandId)['nome']!;
        modelName = _models.firstWhere((e) => e['codigo'] == _selectedModelId)['nome'].toString();
        yearName = _years.firstWhere((e) => e['codigo'] == _selectedYearId)['nome']!;
        currentValue = _fipeValue!;
        typeCode = widget.assetType == 'carros' ? 'CARRO' : 'MOTO';
      } else {
        if (_nameCtrl.text.isEmpty || _marketValueCtrl.text.isEmpty) return;
        brandName = _locationCtrl.text.isEmpty ? "Localização não inf." : _locationCtrl.text;
        modelName = _nameCtrl.text;
        yearName = DateTime.now().year.toString();
        currentValue = _parseValue(_marketValueCtrl.text);
        typeCode = widget.assetType == 'imoveis' ? 'IMOVEL' : 'TERRENO';
      }

      // CORREÇÃO: Usando o método saveVehicle que já existe no seu serviço.
      // Passamos fipeCode vazio se não tiver, para evitar null error no Dart.
      // Se der erro de banco, é porque a coluna não existe e precisa ser criada.
      await _cloudService.saveVehicle(
        type: typeCode,
        brand: brandName,
        model: modelName,
        year: yearName,
        purchasePrice: purchasePrice,
        currentFipePrice: currentValue,
        fipeCode: _fipeCode ?? '', // Passa vazio se não tiver
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("${_isVehicle ? 'Veículo' : 'Bem'} salvo com sucesso!", style: const TextStyle(color: Colors.white)),
                backgroundColor: AppTheme.cyanNeon.withOpacity(0.8)
            )
        );
      }
    } catch (e) {
      debugPrint("Erro salvar: $e");
      if (mounted) {
        // Mensagem amigável explicando o provável problema de banco
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erro de banco: A coluna 'fipe_code' pode estar faltando."), backgroundColor: Colors.redAccent)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double variation = 0.0;
    Color variationColor = Colors.white;

    // Parse em tempo real para cálculo de variação
    double currentVal = _isVehicle ? (_fipeValue ?? 0) : _parseValue(_marketValueCtrl.text);
    double purchaseVal = _parseValue(_purchasePriceCtrl.text);

    if (currentVal > 0 && purchaseVal > 0) {
      variation = ((currentVal - purchaseVal) / purchaseVal) * 100;
      variationColor = variation >= 0 ? AppTheme.cyanNeon : Colors.redAccent;
    }

    // Configuração do Título e Ícone
    String title = "";
    IconData headerIcon = Icons.help;
    if (widget.assetType == 'carros') { title = "Novo Carro"; headerIcon = Icons.directions_car; }
    else if (widget.assetType == 'motos') { title = "Nova Moto"; headerIcon = Icons.two_wheeler; }
    else if (widget.assetType == 'imoveis') { title = "Novo Imóvel"; headerIcon = Icons.home_work_rounded; }
    else { title = "Novo Terreno"; headerIcon = Icons.landscape_rounded; }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Fundo Aurora
          Positioned(
            top: -100, left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 300, height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.cyanNeon.withOpacity(0.15),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header com Botão Voltar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(title,
                          style: AppTheme.titleStyle.copyWith(fontSize: 20),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 40), // Balance
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ÍCONE ANIMADO TEMÁTICO
                SizedBox(
                  height: 100,
                  child: Center(
                    child: _isVehicle
                        ? SlideTransition(
                      position: _iconSlideAnim,
                      child: Icon(headerIcon, size: 80, color: AppTheme.cyanNeon),
                    )
                        : ScaleTransition(
                      scale: _iconScaleAnim,
                      child: Icon(headerIcon, size: 80, color: AppTheme.cyanNeon),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Formulário
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isVehicle) _buildVehicleForm() else _buildRealEstateForm(),

                            const SizedBox(height: 40),

                            // Card de Resultado (Se houver valor)
                            if ((_isVehicle && _fipeValue != null) || (!_isVehicle)) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                                    ),
                                    child: Column(
                                      children: [
                                        if (_isVehicle) ...[
                                          Text(_fullModelName ?? "", style: AppTheme.titleStyle.copyWith(fontSize: 16), textAlign: TextAlign.center),
                                          const SizedBox(height: 10),
                                          Text("Valor Tabela FIPE", style: AppTheme.bodyStyle.copyWith(fontSize: 12)),
                                          Text(
                                            NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(_fipeValue),
                                            style: AppTheme.titleStyle.copyWith(fontSize: 32, color: AppTheme.cyanNeon),
                                          ),
                                          const Divider(color: Colors.white12, height: 30),
                                        ],

                                        TextField(
                                          controller: _purchasePriceCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true), // Teclado numérico melhorado
                                          style: const TextStyle(color: Colors.white),
                                          onChanged: (v) => setState((){}),
                                          decoration: const InputDecoration(
                                            labelText: "Quanto você pagou?",
                                            hintText: "Ex: 50.000",
                                            hintStyle: TextStyle(color: Colors.white12),
                                            labelStyle: TextStyle(color: Colors.white54),
                                            prefixText: "R\$ ",
                                            prefixStyle: TextStyle(color: AppTheme.cyanNeon),
                                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.cyanNeon)),
                                          ),
                                        ),

                                        if (purchaseVal > 0 && currentVal > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 16),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(variation >= 0 ? Icons.trending_up : Icons.trending_down, color: variationColor, size: 16),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "${variation.toStringAsFixed(1)}% ${variation >= 0 ? 'Valorização' : 'Desvalorização'}",
                                                  style: TextStyle(color: variationColor, fontWeight: FontWeight.bold),
                                                )
                                              ],
                                            ),
                                          ),

                                        const SizedBox(height: 24),

                                        GestureDetector(
                                          onTap: _isLoading ? null : _save,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(16),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                              child: Container(
                                                width: double.infinity,
                                                height: 56,
                                                decoration: BoxDecoration(
                                                  color: AppTheme.cyanNeon.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.5)),
                                                ),
                                                alignment: Alignment.center,
                                                child: _isLoading
                                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                    : Text("SALVAR BEM", style: AppTheme.titleStyle.copyWith(color: Colors.white, fontSize: 16)),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ]
                          ],
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

  // --- FORMULÁRIOS ---

  Widget _buildVehicleForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdown("Marca", _brands, _selectedBrandId, (val) => _loadModels(val!)),
        const SizedBox(height: 16),
        Stack(
          children: [
            _buildDropdown("Modelo", _models, _selectedModelId, (val) => _loadYears(val!)),
            if (_isLoadingModels)
              Positioned(right: 16, top: 16, child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyanNeon)))
          ],
        ),
        const SizedBox(height: 16),
        _buildDropdown("Ano", _years, _selectedYearId, (val) => _fetchFipeData(val!)),
      ],
    );
  }

  Widget _buildRealEstateForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(controller: _nameCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration("Nome / Descrição (Ex: Apto Centro)")),
        const SizedBox(height: 16),
        TextField(controller: _locationCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration("Localização (Cidade/Bairro)")),
        const SizedBox(height: 16),
        TextField(
          controller: _marketValueCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white),
          onChanged: (v) => setState((){}), decoration: _inputDecoration("Valor de Mercado Atual (Estimado)"),
        ),
        const SizedBox(height: 8),
        Text("Insira uma estimativa baseada no mercado local.", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white.withOpacity(0.05),
      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white12), borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.cyanNeon), borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildDropdown(String label, List<dynamic> items, String? currentValue, Function(String?) onChanged) {
    final bool valueExists = items.any((item) => item['codigo'] == currentValue);
    final validValue = valueExists ? currentValue : null;

    return DropdownButtonFormField<String>(
      value: validValue, dropdownColor: const Color(0xFF1E1E1E), style: AppTheme.bodyStyle,
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white12), borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.cyanNeon), borderRadius: BorderRadius.circular(12)),
      ),
      items: items.map<DropdownMenuItem<String>>((item) {
        return DropdownMenuItem<String>(
          value: item['codigo'],
          child: Text(item['nome'].length > 30 ? item['nome'].substring(0, 27) + '...' : item['nome'], overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}