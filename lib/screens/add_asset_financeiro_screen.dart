import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme.dart';

class AddAssetFinanceiroScreen extends StatefulWidget {
  final String assetType; // 'financeiro', 'carros', 'motos', 'imoveis', 'terrenos'

  const AddAssetFinanceiroScreen({Key? key, required this.assetType}) : super(key: key);

  @override
  State<AddAssetFinanceiroScreen> createState() => _AddAssetFinanceiroScreenState();
}

class _AddAssetFinanceiroScreenState extends State<AddAssetFinanceiroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _tickerController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _institutionController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  // Define o subtipo baseado no que foi clicado na Home
  late String _dbType;

  @override
  void initState() {
    super.initState();
    _resolveAssetType();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tickerController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _institutionController.dispose();
    super.dispose();
  }

  void _resolveAssetType() {
    switch (widget.assetType) {
      case 'financeiro':
        _dbType = 'STOCK'; // Padrão inicial
        break;
      case 'carros':
      case 'motos':
        _dbType = 'VEHICLE';
        break;
      case 'imoveis':
      case 'terrenos':
        _dbType = 'REAL_ESTATE';
        break;
      default:
        _dbType = 'OTHER';
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.cyanNeon,
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E24),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'Usuário não autenticado';

      final name = _nameController.text.trim();
      final ticker = widget.assetType == 'financeiro'
          ? _tickerController.text.trim().toUpperCase()
          : name;

      final quantity = double.tryParse(_quantityController.text.replaceAll(',', '.')) ?? 1.0;
      final price = double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0.0;

      final assetData = {
        'user_id': user.id,
        'name': name,
        'ticker': ticker,
        'type': _dbType,
        'quantity': quantity,
        'purchase_price': price,
        'average_price': price,
        'institution': _institutionController.text.trim().isEmpty ? 'Manual' : _institutionController.text.trim(),
        'purchase_date': _selectedDate.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      };

      await Supabase.instance.client.from('assets').insert(assetData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ativo financeiro cadastrado!"), backgroundColor: AppTheme.cyanNeon),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao salvar: $e"), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isFinance = widget.assetType == 'financeiro';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("Novo Ativo Financeiro", style: AppTheme.titleStyle.copyWith(fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -50, left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.cyanNeon.withOpacity(0.1)),
              ),
            ),
          ),

          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "DETALHES DA OPERAÇÃO",
                    style: AppTheme.titleStyle.copyWith(fontSize: 10, color: Colors.white38, letterSpacing: 2),
                  ),
                  const SizedBox(height: 20),

                  GlassCard(
                    opacity: 0.05,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        if (isFinance) ...[
                          _buildTextField(
                            label: "Ticker / Símbolo",
                            controller: _tickerController,
                            hint: "Ex: ITUB4, IVVB11, ETH",
                            icon: Icons.qr_code_rounded,
                            validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                          ),
                          const SizedBox(height: 16),
                        ],

                        _buildTextField(
                          label: "Nome / Descrição",
                          controller: _nameController,
                          hint: "Ex: Itaú Unibanco PN",
                          icon: Icons.info_outline,
                          validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                        ),

                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                label: "Quantidade",
                                controller: _quantityController,
                                hint: "0.00",
                                icon: Icons.numbers_rounded,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTextField(
                                label: "Valor Pago (R\$)",
                                controller: _priceController,
                                hint: "0,00",
                                icon: Icons.payments_outlined,
                                keyboardType: TextInputType.number,
                                validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        _buildTextField(
                          label: "Corretora / Carteira",
                          controller: _institutionController,
                          hint: "Ex: XP, NuInvest, MetaMask",
                          icon: Icons.account_balance_rounded,
                        ),

                        const SizedBox(height: 16),

                        GestureDetector(
                          onTap: () => _selectDate(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, color: Colors.white24, size: 20),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Data da Compra", style: TextStyle(color: Colors.white54, fontSize: 10)),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('dd/MM/yyyy').format(_selectedDate),
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                const Icon(Icons.edit_calendar_rounded, color: AppTheme.cyanNeon, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cyanNeon,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : Text(
                        "ADICIONAR À CARTEIRA",
                        style: AppTheme.titleStyle.copyWith(color: Colors.black, fontSize: 14, letterSpacing: 1.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
            prefixIcon: Icon(icon, color: Colors.white24, size: 18),
            filled: true,
            fillColor: Colors.white.withOpacity(0.03),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.cyanNeon, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1),
            ),
          ),
        ),
      ],
    );
  }
}