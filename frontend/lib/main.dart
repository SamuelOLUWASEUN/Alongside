import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/theme_controller.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  // google_fonts needs the Flutter engine's ServicesBinding ready before it
  // can fetch/cache fonts - must come before any font calls.
  WidgetsFlutterBinding.ensureInitialized();

  // Kick off font downloads before the first frame that needs them, so the
  // Fraunces/Manrope swap-in ("flash of unstyled text") is less noticeable.
  GoogleFonts.fraunces();
  GoogleFonts.manrope();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: const AlongsideApp(),
    ),
  );
}

class AlongsideApp extends StatefulWidget {
  const AlongsideApp({super.key});

  @override
  State<AlongsideApp> createState() => _AlongsideAppState();
}

class _AlongsideAppState extends State<AlongsideApp> {
  late final Future<void> _startupFuture;

  @override
  void initState() {
    super.initState();
    // Check for a token already in storage on startup, so a page refresh
    // (or relaunching the app) doesn't force a logged-in user back through
    // onboarding just because a fresh AuthService defaults to logged-out.
    // Also restore the saved theme preference before the first frame.
    _startupFuture = Future.wait([
      context.read<AuthService>().tryAutoLogin(),
      context.read<ThemeController>().load(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Watching ThemeController here means every time it changes, MaterialApp
    // rebuilds and re-reads AppTheme.light (which reflects whatever palette
    // AppColors currently holds), cascading a fresh build down through every
    // screen so they all pick up the new colors.
    context.watch<ThemeController>();

    return MaterialApp(
      title: 'Alongside',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: FutureBuilder<void>(
        future: _startupFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return Consumer<AuthService>(
            builder: (_, auth, __) => auth.isLoggedIn ? const HomeScreen() : const OnboardingScreen(),
          );
        },
      ),
    );
  }
}
