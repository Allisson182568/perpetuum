import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:ui'; // Necessário para o Blur (Efeito de vidro)
import 'package:flutter/foundation.dart'; // Para kIsWeb
import 'package:crypto/crypto.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../../services/cloud_service.dart';

// Imports das Estratégias
import 'strategies/import_strategy.dart';
import 'strategies/irpf_strategy.dart';
import 'strategies/b3_strategy.dart';
import 'strategies/print_strategy.dart';
import 'strategies/avenue_strategy.dart';

import 'import_dialog.dart';

enum ImportType { irpf, b3, usa, print }

class ImportScreen extends StatefulWidget {
  final ImportType importType;
  const ImportScreen({Key? key, required this.importType}) : super(key: key);

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final CloudService _cloud = CloudService();
  PlatformFile? _pickedFile;
  bool _isLoading = false;
  String _loadingText = "Processando..."; // Texto dinâmico para o loading
  late ImportStrategy _strategy;

  @override
  void initState() {
    super.initState();
    switch (widget.importType) {
      case ImportType.irpf: _strategy = IrpfStrategy(); break;
      case ImportType.b3: _strategy = B3Strategy(); break;
      case ImportType.print: _strategy = PrintStrategy(); break;
      case ImportType.usa: _strategy = AvenueStrategy(); break;
      default: _strategy = B3Strategy();
    }
  }

  Future<void> _pickFile() async {
    // Não bloqueia a tela inteira aqui, só mostra spinner no botão se quiser
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _strategy.allowedExtensions,
        withData: true,
      );
      if (result != null) setState(() => _pickedFile = result.files.single);
    } catch (e) {
      debugPrint("Erro pick: $e");
    }
  }

  Future<void> _processFile() async {
    if (_pickedFile == null) return;

    // 1. Ativa o Loading Overlay
    setState(() {
      _isLoading = true;
      _loadingText = "Lendo arquivo...";
    });

    // TRUQUE CRUCIAL: Pequeno delay para permitir que o Flutter desenhe o Loading na tela
    // antes de travar a CPU com a leitura do Excel.
    await Future.delayed(const Duration(milliseconds: 150));

    try {
      Uint8List fileBytes = kIsWeb ? _pickedFile!.bytes! : await File(_pickedFile!.path!).readAsBytes();

      setState(() => _loadingText = "Analisando dados...");
      await Future.delayed(const Duration(milliseconds: 50)); // Outro respiro para UI atualizar

      // 2. Executa a Estratégia (Pesada)
      List<ImportResult> items = await _strategy.parse(_pickedFile!, fileBytes);

      if (items.isEmpty) {
        _showToast("Nenhum dado encontrado.", isError: true);
      } else {
        if (mounted) {
          setState(() => _loadingText = "Preparando revisão...");

          List<Map<String, dynamic>> rawData = items.map((e) => {
            'ticker': e.ticker,
            'qty': e.qty,
            'price': e.price,
            'type': e.type,
            'asset_type': e.assetType,
            'cnpj': e.cnpj,
            'is_earning': e.isEarning,
            'fees': e.fees,
            'date': e.date,
            'broker': e.broker,
            'enrichment': e.enrichment
          }).toList();

          // Abre o Dialog
          showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => ImportReviewDialog(
                  assets: rawData,
                  fileName: _pickedFile!.name,
                  onConfirm: (finalData) async {
                    // Ao confirmar no dialog, usamos a lógica de salvar
                    String hash = sha256.convert(fileBytes).toString();
                    return await _reconcileAndSave(finalData, hash);
                  }
              )
          );
        }
      }

    } catch (e) {
      _showToast("Erro: $e", isError: true);
    } finally {
      // Desativa o Loading Overlay
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _reconcileAndSave(List<Map<String, dynamic>> newItems, String fileHash) async {
    // Reativamos o loading caso tenha fechado o dialog e esteja salvando
    setState(() {
      _isLoading = true;
      _loadingText = "Salvando no banco...";
    });

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showToast("Usuário deslogado.", isError: true);
      setState(() => _isLoading = false);
      return false;
    }

    try {
      final dbAssets = await Supabase.instance.client.from('assets').select().eq('user_id', user.id);

      int count = 0;
      int currentYear = DateTime.now().year;

      for (var item in newItems) {
        String ticker = _cleanTicker(item['ticker']);
        String isoDate = _parseDateSafe(item['date'].toString()) ?? DateTime.now().toIso8601String();

        double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
        double price = double.tryParse(item['price'].toString()) ?? 0.0;
        double fees = double.tryParse(item['fees']?.toString() ?? '0') ?? 0.0;
        double totalValue = qty * price;

        String type = (item['type'] ?? 'C').toString();
        String assetType = (item['asset_type'] ?? 'OUTROS').toString();
        if (assetType.isEmpty) assetType = 'OUTROS';

        String broker = (item['broker'] ?? 'Importado').toString();
        String companyName = item['enrichment']?['name'] ?? ticker;

        if (item['is_earning'] == true) {
          await Supabase.instance.client.from('earnings').insert({
            'user_id': user.id,
            'ticker': ticker,
            'total_value': price,
            'type': type,
            'date': isoDate,
            'description': item['enrichment']?['original_desc'] ?? 'Dividendo Importado'
          });
        } else {
          Map<String, dynamic> upsertData = {
            'user_id': user.id,
            'name': companyName,
            'type': assetType,
            'value': totalValue,
            'year': currentYear,
            'ticker': ticker,
            'quantity': qty,
            'purchase_price': price,
            'current_price': price,
            'average_price': price,
            'purchase_date': isoDate,
            'operation_date': isoDate,
            'is_audited': widget.importType == ImportType.irpf,
            'last_audit_source': widget.importType.toString(),
            'last_audit_date': DateTime.now().toIso8601String(),
            'cnpj': item['cnpj'],
            'metadata': {
              'original_desc': item['enrichment']?['original_desc'],
              'location': item['enrichment']?['location'] ?? 'BR',
              'broker': broker,
              'fees': fees,
              'import_hash': fileHash
            }
          };

          var existing = dbAssets.firstWhere(
                  (a) => _cleanTicker(a['ticker']) == ticker && a['year'] == currentYear,
              orElse: () => {'id': null}
          );

          if (existing['id'] != null) {
            upsertData.remove('current_price');
            upsertData.remove('name');
            await Supabase.instance.client.from('assets').update(upsertData).eq('id', existing['id']);
          } else {
            await Supabase.instance.client.from('assets').insert(upsertData);
          }
          count++;
        }
      }

      await _cloud.logImport(fileHash, _pickedFile!.name);

      if (mounted) _showToast("Sucesso! $count registros salvos.", isError: false);
      return true;

    } catch (e) {
      debugPrint("ERRO DB: $e");
      if (e.toString().contains('null value in column')) {
        final col = RegExp(r'column "(\w+)"').firstMatch(e.toString())?.group(1);
        _showToast("Erro: Campo obrigatório '$col' vazio.", isError: true);
      } else {
        _showToast("Erro ao salvar.", isError: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _parseDateSafe(String raw) {
    if (raw.isEmpty) return null;
    try {
      if (raw.contains('/')) {
        var parts = raw.split('/');
        if (parts.length == 3) {
          return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0])).toIso8601String();
        }
      }
      if (raw.contains('-')) return DateTime.parse(raw).toIso8601String();
      return null;
    } catch (e) { return null; }
  }

  String _cleanTicker(String? t) {
    if (t == null) return "";
    String s = t.toUpperCase().trim();
    if (s.length > 4 && s.endsWith('F') && RegExp(r'\d').hasMatch(s[s.length-2])) return s.substring(0, s.length - 1);
    return s;
  }

  void _showToast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.transparent, elevation: 0,
        content: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: isError ? Colors.red : AppTheme.cyanNeon)),
            child: Row(children: [Icon(isError ? Icons.error : Icons.check_circle, color: isError ? Colors.red : AppTheme.cyanNeon), const SizedBox(width: 12), Expanded(child: Text(msg, style: const TextStyle(color: Colors.white)))])
        )
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(_strategy.title, style: AppTheme.titleStyle), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white), onPressed: () => Navigator.pop(context))),

      // USAMOS STACK PARA O LOADING FICAR POR CIMA DE TUDO
      body: Stack(
        children: [
          // 1. CONTEÚDO ORIGINAL
          Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Text("Selecione o Arquivo", style: AppTheme.titleStyle.copyWith(fontSize: 24)),
                    const SizedBox(height: 12),
                    Text(_strategy.description, style: AppTheme.bodyStyle, textAlign: TextAlign.center),
                    const SizedBox(height: 40),
                    GestureDetector(
                        onTap: _pickFile,
                        child: DottedBorder(
                            borderType: BorderType.RRect, radius: const Radius.circular(24), dashPattern: const [8, 8], color: AppTheme.cyanNeon.withOpacity(0.3),
                            child: Container(
                                width: double.infinity, height: 200, alignment: Alignment.center, color: Colors.white.withOpacity(0.02),
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(_strategy.icon, size: 50, color: AppTheme.cyanNeon),
                                      const SizedBox(height: 10),
                                      Text(_pickedFile?.name ?? "Toque para selecionar", style: const TextStyle(color: Colors.white70))
                                    ]
                                )
                            )
                        )
                    ),
                    const Spacer(),
                    SizedBox(
                        width: double.infinity, height: 56,
                        child: ElevatedButton(
                            onPressed: _isLoading ? null : _processFile, // Desabilita botão se carregando
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cyanNeon, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            child: Text("PROCESSAR", style: AppTheme.titleStyle.copyWith(color: Colors.black, fontSize: 16))
                        )
                    ),
                  ]
              )
          ),

          // 2. LOADING OVERLAY (A Mágica acontece aqui)
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7), // Fundo escuro translúcido
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), // Efeito Blur (Vidro)
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.5), width: 1),
                        boxShadow: [
                          BoxShadow(color: AppTheme.cyanNeon.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)
                        ]
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.cyanNeon),
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 20),
                        Text(
                            _loadingText,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5
                            )
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}