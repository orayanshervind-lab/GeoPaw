import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'Pages/login.dart';
import 'Pages/home.dart';
import 'services/pet_provider.dart';
import 'services/notification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => PetProvider(),
      child: const GeoPawApp(),
    ),
  );
}

class GeoPawApp extends StatelessWidget {
  const GeoPawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoPaw',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
      colorSchemeSeed: const Color(0xFFFF9B4A),
      useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            // Load pets as soon as user is confirmed logged in
            Future.microtask(() =>
                context.read<PetProvider>().loadPets());
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}