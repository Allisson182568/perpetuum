import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'login_screen.dart';
import 'rebalance_screen.dart'; // Importação da nova tela estratégica
import '../theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Estado local
  bool _notificationsEnabled = false;
  bool _biometricsEnabled = false;
  bool _isSettingsExpanded = false;
  bool _isSecurityExpanded = false;
  bool _isUploading = false;

  // Dados do Usuário
  String _userName = "Investidor";
  String _userEmail = "Carregando...";
  String? _avatarUrl;

  final ImagePicker _picker = ImagePicker();
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // Recarrega sessão para garantir dados atualizados
      try {
        await Supabase.instance.client.auth.refreshSession();
        final updatedUser = Supabase.instance.client.auth.currentUser!;

        if (mounted) {
          setState(() {
            _userEmail = updatedUser.email ?? "Email desconhecido";
            _userName = updatedUser.userMetadata?['full_name'] ?? "Investidor";
            _avatarUrl = updatedUser.userMetadata?['avatar_url'];

            // Carrega preferências salvas
            _notificationsEnabled = updatedUser.userMetadata?['pref_notifications'] ?? false;
            _biometricsEnabled = updatedUser.userMetadata?['pref_biometrics'] ?? false;
          });
        }
      } catch (e) {
        debugPrint("Erro ao carregar perfil: $e");
      }
    }
  }

  // --- UPLOAD DE FOTO ---
  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 60,
        maxWidth: 600,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      final imageBytes = await image.readAsBytes();
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final fileExt = image.path.split('.').last;
      final fileName = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // Upload
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
        fileName,
        imageBytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

      // Pega URL pública com timestamp para evitar cache
      final imageUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      final urlWithCacheBust = "$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}";

      // Atualiza perfil
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'avatar_url': urlWithCacheBust}),
      );

      if (mounted) {
        setState(() {
          _avatarUrl = urlWithCacheBust;
          _isUploading = false;
        });
        _showIOSNotification("Foto de perfil atualizada!", isError: false);
      }

    } catch (e) {
      debugPrint("Erro upload: $e");
      if (mounted) {
        setState(() => _isUploading = false);
        _showIOSNotification("Erro no upload. Verifique sua conexão.", isError: true);
      }
    }
  }

  // --- BIOMETRIA ---
  Future<void> _toggleBiometrics(bool value) async {
    if (value) {
      // Se está tentando ATIVAR, pede autenticação real
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        _showIOSNotification("Seu dispositivo não suporta biometria.", isError: true);
        return;
      }

      try {
        final bool didAuthenticate = await _localAuth.authenticate(
          localizedReason: 'Confirme sua identidade para ativar o FaceID/TouchID.',
          options: const AuthenticationOptions(biometricOnly: true),
        );

        if (!didAuthenticate) return; // Cancelou ou falhou
      } catch (e) {
        _showIOSNotification("Erro na autenticação: $e", isError: true);
        return;
      }
    }

    // Salva preferência no banco
    _updatePreference('pref_biometrics', value);
  }

  Future<void> _updatePreference(String key, bool value) async {
    setState(() {
      if (key == 'pref_notifications') _notificationsEnabled = value;
      if (key == 'pref_biometrics') _biometricsEnabled = value;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {key: value}),
      );
    } catch (e) {
      debugPrint("Erro ao salvar: $e");
    }
  }

  // --- NOTIFICAÇÃO ESTILO IOS (TOPO) ---
  void _showIOSNotification(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: isError ? const Color(0xFFFF3B30).withOpacity(0.9) : const Color(0xFF34C759).withOpacity(0.9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                      isError ? CupertinoIcons.exclamationmark_circle_fill : CupertinoIcons.checkmark_circle_fill,
                      color: Colors.white,
                      size: 24
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        message,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 160, // Força aparição no topo
            left: 16,
            right: 16
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // --- DIALOGS E AÇÕES ---
  Future<void> _updateName() async {
    final controller = TextEditingController(text: _userName);
    await showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text("Editar Nome"),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
            placeholder: "Seu nome",
          ),
        ),
        actions: [
          CupertinoDialogAction(child: const Text("Cancelar"), onPressed: () => Navigator.pop(context)),
          CupertinoDialogAction(
            child: const Text("Salvar"),
            onPressed: () async {
              try {
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(data: {'full_name': controller.text}),
                );
                setState(() => _userName = controller.text);
                if (mounted) Navigator.pop(context);
              } catch (e) {
                print(e);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData() async {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text("Apagar Tudo?"),
        content: const Text("Isso apagará permanentemente todo o seu histórico de bens. Essa ação não pode ser desfeita."),
        actions: [
          CupertinoDialogAction(child: const Text("Cancelar"), onPressed: () => Navigator.pop(context)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text("Apagar"),
            onPressed: () async {
              Navigator.pop(context);
              try {
                final userId = Supabase.instance.client.auth.currentUser?.id;
                if (userId != null) {
                  await Supabase.instance.client.from('assets').delete().eq('user_id', userId);
                  _showIOSNotification("Histórico limpo com sucesso.");
                }
              } catch (e) {
                _showIOSNotification("Erro ao limpar dados.", isError: true);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text("Excluir Conta"),
        content: const Text("Sua conta será desconectada. Para exclusão definitiva (GDPR/LGPD), entre em contato com o suporte."),
        actions: [
          CupertinoDialogAction(child: const Text("Cancelar"), onPressed: () => Navigator.pop(context)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text("Sair e Excluir"),
            onPressed: () async {
              Navigator.pop(context);
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Fundo Aurora
          Positioned(
            top: -100, right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 300, height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.cyanNeon.withOpacity(0.1),
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // AppBar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text("Perfil", style: TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // FOTO DE PERFIL
                  GestureDetector(
                    onTap: _pickAndUploadImage,
                    child: Stack(
                      children: [
                        Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.cyanNeon, width: 2),
                              color: const Color(0xFF1E1E1E),
                              image: _avatarUrl != null
                                  ? DecorationImage(image: NetworkImage(_avatarUrl!), fit: BoxFit.cover)
                                  : null,
                              boxShadow: [
                                BoxShadow(color: AppTheme.cyanNeon.withOpacity(0.3), blurRadius: 20)
                              ]
                          ),
                          // Ícone fallback se não tiver foto
                          child: _isUploading
                              ? const CircularProgressIndicator(color: AppTheme.cyanNeon)
                              : (_avatarUrl == null ? const Icon(Icons.person, size: 60, color: Colors.white54) : null),
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: AppTheme.cyanNeon, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.black),
                          ),
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Nome e Email
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_userName, style: AppTheme.titleStyle.copyWith(fontSize: 24)),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: AppTheme.cyanNeon),
                        onPressed: _updateName,
                      )
                    ],
                  ),
                  Text(_userEmail, style: AppTheme.bodyStyle.copyWith(color: Colors.white54)),

                  const SizedBox(height: 40),

                  // MENU DE OPÇÕES (ACORDEÃO)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GlassCard(
                      opacity: 0.05,
                      child: Column(
                        children: [
                          // NOVO: Módulo de Estratégia IA
                          ListTile(
                            leading: const Icon(Icons.auto_awesome, color: AppTheme.cyanNeon),
                            title: Text("Rebalanceamento IA", style: AppTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold)),
                            subtitle: const Text("Análise de riscos e diversificação", style: TextStyle(color: Colors.white38, fontSize: 12)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.cyanNeon),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RebalanceScreen())),
                          ),
                          const Divider(color: Colors.white10, height: 1),

                          _buildExpandableTile(
                              icon: Icons.settings,
                              title: "Configurações",
                              isExpanded: _isSettingsExpanded,
                              onTap: () => setState(() => _isSettingsExpanded = !_isSettingsExpanded),
                              children: [
                                _buildSwitchTile(
                                    "Notificações",
                                    _notificationsEnabled,
                                        (val) => _updatePreference('pref_notifications', val)
                                )
                              ]
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildExpandableTile(
                              icon: Icons.security,
                              title: "Segurança",
                              isExpanded: _isSecurityExpanded,
                              onTap: () => setState(() => _isSecurityExpanded = !_isSecurityExpanded),
                              children: [
                                _buildSwitchTile(
                                    "FaceID / Biometria",
                                    _biometricsEnabled,
                                    _toggleBiometrics
                                )
                              ]
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          ListTile(
                            leading: const Icon(Icons.help_outline, color: Colors.white70),
                            title: Text("Ajuda e Suporte", style: AppTheme.bodyStyle),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white24),
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ZONA DE PERIGO
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        _buildDangerButton("Limpar Histórico", Icons.delete_outline, _clearAllData),
                        const SizedBox(height: 12),
                        _buildDangerButton("Sair da Conta", Icons.logout, _deleteAccount),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildSwitchTile(String title, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          CupertinoSwitch( // Switch estilo iOS
            value: value,
            activeColor: AppTheme.cyanNeon,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableTile({required IconData icon, required String title, required bool isExpanded, required VoidCallback onTap, required List<Widget> children}) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: Colors.white70),
          title: Text(title, style: AppTheme.bodyStyle),
          trailing: Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white24),
          onTap: onTap,
        ),
        AnimatedCrossFade(
          firstChild: Container(),
          secondChild: Container(
            color: Colors.white.withOpacity(0.05),
            child: Column(children: children),
          ),
          crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        )
      ],
    );
  }

  Widget _buildDangerButton(String text, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.red.withOpacity(0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}