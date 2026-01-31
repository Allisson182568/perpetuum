import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null && mounted) {
        // Redireciona apenas se já não estiver navegando
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
  }

  // ============================
  // LOGIN COM GOOGLE (CORRIGIDO PARA WEB)
  // ============================


  // ============================
  // LOGIN COM EMAIL / SENHA
  // ============================
  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showIosNotification("Preencha e-mail e senha", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name},
        );
        _showIosNotification("Verifique seu e-mail para confirmar a conta", isError: false);
        setState(() => _isLogin = true);
        return;
      }
    } on AuthException catch (e) {
      _showIosNotification(e.message, isError: true);
    } catch (e) {
      _showIosNotification("Erro inesperado: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showIosNotification(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 60, left: 20, right: 20,
        child: Material(
          color: Colors.transparent,
          child: _IosNotificationWidget(message: message, isError: isError),
        ),
      ),
    );
    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 4), overlayEntry.remove);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned(
            top: -100, right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.cyanNeon.withOpacity(0.15))),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.cyanNeon.withOpacity(0.5), width: 2),
                      boxShadow: [BoxShadow(color: AppTheme.cyanNeon.withOpacity(0.2), blurRadius: 20)],
                    ),
                    child: const Icon(Icons.fingerprint, size: 50, color: AppTheme.cyanNeon),
                  ),
                  const SizedBox(height: 30),
                  Text("PERPETUUM", style: AppTheme.titleStyle.copyWith(fontSize: 24, letterSpacing: 4)),
                  const SizedBox(height: 40),
                  GlassCard(
                    opacity: 0.05, padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        if (!_isLogin) ...[
                          _buildTextField("Nome", _nameController, false, Icons.person_outline),
                          const SizedBox(height: 16),
                        ],
                        _buildTextField("E-mail", _emailController, false, Icons.email_outlined),
                        const SizedBox(height: 16),
                        _buildTextField("Senha", _passwordController, true, Icons.lock_outline),
                        const SizedBox(height: 24),
                        if (_isLoading)
                          const CircularProgressIndicator(color: AppTheme.cyanNeon)
                        else ...[
                          SizedBox(
                            width: double.infinity, height: 50,
                            child: ElevatedButton(
                              onPressed: _submit,
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cyanNeon, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              child: Text(_isLogin ? "ENTRAR" : "CRIAR CONTA"),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Row(children: [Expanded(child: Divider(color: Colors.white10)), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("OU", style: TextStyle(color: Colors.white24, fontSize: 12))), Expanded(child: Divider(color: Colors.white10))]),
                          const SizedBox(height: 16),

                          const SizedBox(height: 24),
                          GestureDetector(
                            onTap: () => setState(() => _isLogin = !_isLogin),
                            child: Text.rich(TextSpan(text: _isLogin ? "Não tem conta? " : "Já tem conta? ", style: const TextStyle(color: Colors.white54, fontSize: 14), children: [TextSpan(text: _isLogin ? "Cadastre-se" : "Faça Login", style: const TextStyle(color: AppTheme.cyanNeon, fontWeight: FontWeight.bold))])),
                          ),
                        ],
                      ],
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

  Widget _buildTextField(String label, TextEditingController controller, bool isPassword, IconData icon) {
    return TextField(
      controller: controller, obscureText: isPassword, style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white24, size: 20),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.cyanNeon)),
        filled: true, fillColor: Colors.black12,
      ),
    );
  }
}


class _IosNotificationWidget extends StatelessWidget {
  final String message;
  final bool isError;

  const _IosNotificationWidget({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(color: isError ? Colors.red.withOpacity(0.2) : AppTheme.cyanNeon.withOpacity(0.2), borderRadius: BorderRadius.circular(24), border: Border.all(color: isError ? Colors.red.withOpacity(0.3) : AppTheme.cyanNeon.withOpacity(0.3))),
          child: Row(children: [Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: isError ? Colors.redAccent : AppTheme.cyanNeon, size: 24), const SizedBox(width: 12), Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14, decoration: TextDecoration.none)))]),
        ),
      ),
    );
  }
}