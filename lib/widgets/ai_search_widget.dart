import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/ai/AiEngineService.dart';
import '../theme.dart';

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

    try {
      // Adicionamos um timeout para não ficar rodando infinito se a internet falhar
      final result = await _aiService.processQuery(query).timeout(
        const Duration(seconds: 10),
        onTimeout: () => {
          "type": "text",
          "content": "O servidor demorou muito para responder. Tente novamente."
        },
      );

      if (mounted) {
        setState(() => _isAnalyzing = false);
        _showAiResult(query, result);
      }
    } catch (e) {
      debugPrint("Erro no Chat IA: $e");
      if (mounted) {
        setState(() => _isAnalyzing = false);
        _showAiResult(query, {
          "type": "text",
          "content": "Tive um problema técnico ao processar sua dúvida. Mas já avisei os desenvolvedores!"
        });
      }
    }
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.withOpacity(0.1), AppTheme.cyanNeon.withOpacity(0.05)],
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
                  "Como posso ajudar sua carteira hoje?",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              if (_isAnalyzing)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyanNeon))
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            onSubmitted: (_) => _submitQuery(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Ex: Qual meu melhor ativo para vender?",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
              filled: true,
              fillColor: Colors.black26,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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