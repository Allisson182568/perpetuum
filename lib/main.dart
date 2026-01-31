import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'theme.dart';
import 'screens/home_screen.dart';

void main() async {
  // Garante que o Flutter esteja pronto antes de iniciar o banco
  WidgetsFlutterBinding.ensureInitialized();

  // --- INICIALIZAÇÃO DO SUPABASE ---
  await Supabase.initialize(
    // MANTIVE AS CHAVES QUE VOCÊ ENVIOU NO PROMPT
    url: 'https://xsokpokqgnlfompojicr.supabase.co',
    anonKey: 'sb_publishable_L0Y5szc5k1oE62IXj7s-bA_SpExcSGF',
  );
  // ----------------------------------

  // Garante que a barra de status fique transparente
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const PerpetuumApp());
}

class PerpetuumApp extends StatelessWidget {
  const PerpetuumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Perpetuum',
      debugShowCheckedModeBanner: false,

      // Configuração do Tema Global
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppTheme.background,
        primaryColor: AppTheme.cyanNeon,

        // --- FORÇA ESTILO iOS (CUPERTINO) EM TUDO ---
        platform: TargetPlatform.iOS, // <--- O SEGREDO: Força comportamento de iPhone no Android

        // Remove o efeito "Ripple" (onda de clique) do Android
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent, // Remove fundo cinza ao clicar

        textTheme: GoogleFonts.outfitTextTheme(
          Theme.of(context).textTheme.apply(
            bodyColor: AppTheme.textPrimary,
            displayColor: AppTheme.textPrimary,
          ),
        ),

        colorScheme: const ColorScheme.dark(
          primary: AppTheme.cyanNeon,
          secondary: AppTheme.cyanDim,
          surface: AppTheme.surface,
          background: AppTheme.background,
        ),

        useMaterial3: true,
      ),

      home: Supabase.instance.client.auth.currentUser == null
          ? const LoginScreen()
          : const HomeScreen(),
    );
  }
}