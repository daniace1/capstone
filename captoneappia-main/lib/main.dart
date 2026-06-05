import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// 1. IMPORTAS TU NUEVA PANTALLA
import 'detector_view.dart'; 


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 2. CONFIGURAS TU CONEXIÓN (usa tus llaves reales)
  await Supabase.initialize(
    url: 'https://hciwfzwcgwfvrhmiixew.supabase.co',
    anonKey: 'sb_publishable_HvQI-SW7dq-p34InoIna1A_eIolKyeN',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override

  
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IronLens',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.orangeAccent,
        scaffoldBackgroundColor: const Color(0xFF121212), // Fondo negro oscuro
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orangeAccent,
          foregroundColor: Colors.black, // Texto negro sobre botón naranja resalta más
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      cardTheme: CardTheme( // <--- Agrega 'Data' aquí
        color: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      ),

      // 3. AQUÍ LE DICES QUE LA PANTALLA PRINCIPAL ES TU TEST DE GYM
      home: GymTestView(), 
    );
  }
}