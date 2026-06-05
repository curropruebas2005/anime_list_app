import 'package:flutter/material.dart';
import 'dart:async';
import 'theme.dart';
import 'package:flutter/services.dart';
import 'screens/main_layout.dart';
import 'screens/login_screen.dart';
import 'repositories/anime_repository.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Punto de entrada principal de la aplicación Flutter.
/// Se declara como asíncrona [async] ya que realiza inicializaciones de servicios externos
/// antes de renderizar la interfaz gráfica.
void main() async {
  // Asegura que los canales de comunicación nativos de Flutter (Platform Channels)
  // estén completamente inicializados antes de realizar cualquier llamada asíncrona.
  WidgetsFlutterBinding.ensureInitialized();
  
  // Fuerza a la aplicación a ejecutarse únicamente en orientación vertical (portrait),
  // garantizando una consistencia visual de la UI en cualquier dispositivo móvil.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  // Inicialización global del cliente de Supabase (Base de datos remota, Autenticación y Almacenamiento).
  // Se configuran las credenciales del proyecto (URL y clave pública anónima).
  await Supabase.initialize(
    url: 'https://sfmjafaxhwhpemrcmtzg.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNmbWphZmF4aHdocGVtcmNtdHpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0NTY4MjEsImV4cCI6MjA5MTAzMjgyMX0.JHWd7d8Q-Ezuj90RmL1A0bgMAtEJn5MXnWRn3ZtVg14',
  );

  // Inicializa el proveedor de tema persistente (carga si el usuario prefiere Modo Claro u Oscuro).
  await themeProvider.init();
  // Inicializa el repositorio local de datos (Base de datos SQLite local para soporte Offline y Caché).
  await AnimeRepository.init();

  // Arranca el árbol de widgets de la aplicación.
  runApp(const MyApp());
}

/// Widget raíz de la aplicación ([StatelessWidget] porque su estructura no cambia por sí misma).
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // [ListenableBuilder] escucha los cambios reactivos en [themeProvider].
    // Cada vez que el usuario cambia a Modo Oscuro/Claro, este widget reconstruye automáticamente
    // el [MaterialApp] para aplicar las nuevas propiedades visuales de inmediato.
    return ListenableBuilder(
      listenable: themeProvider,
      builder: (context, _) {
        return MaterialApp(
          title: 'Tomodachi',
          theme: AppTheme.lightTheme,      // Configuración de colores del tema claro.
          darkTheme: AppTheme.darkTheme,    // Configuración de colores del tema oscuro.
          themeMode: themeProvider.themeMode, // Modo actual (claro, oscuro o del sistema).
          home: const AuthGate(),          // Portal de autenticación reactivo (decide qué pantalla mostrar).
          debugShowCheckedModeBanner: false, // Desactiva la banda de depuración visual en la esquina.
        );
      },
    );
  }
}

/// [AuthGate] actúa como el guardián de rutas principal de la aplicación.
/// Escucha en tiempo real si el usuario tiene una sesión válida abierta en Supabase.
/// Si tiene sesión, le redirige al menú principal (`MainLayout`). Si no, le muestra la pantalla de `LoginScreen`.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Suscripción al flujo dinámico (Stream) del estado de autenticación de Supabase.
  late final StreamSubscription<AuthState> _authSubscription;
  Session? _session;
  bool _isLoading = true; // Control de estado de carga inicial.

  @override
  void initState() {
    super.initState();
    // 1. Escucha de forma activa y reactiva los cambios de sesión (inicios, cierres de sesión, expiración de tokens).
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          _session = data.session;
          _isLoading = false;
        });
      }
    });

    // 2. Hace una verificación síncrona/inmediata del token de sesión que pueda estar almacenado localmente.
    _checkInitialSession();
  }

  /// Recupera de forma instantánea la sesión actual guardada en el dispositivo.
  Future<void> _checkInitialSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (mounted) {
      setState(() {
        _session = session;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    // IMPORTANTE: Se cancela la suscripción al Stream para evitar fugas de memoria (Memory Leaks)
    // cuando el widget se destruye de la jerarquía de Flutter.
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Si todavía estamos comprobando el estado de la sesión, mostramos un indicador de carga centrado.
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.primary)));
    }

    final user = _session?.user;

    // Si el usuario tiene sesión activa, comprobamos que el correo electrónico esté verificado
    // o que haya iniciado sesión mediante proveedores de terceros verificados como Google.
    if (_session != null) {
      final bool isGoogle = user?.appMetadata['provider'] == 'google';
      final bool isConfirmed = user?.emailConfirmedAt != null;
      
      if (isGoogle || isConfirmed) {
        return const MainLayout(); // Usuario logueado y verificado -> Dashboard principal.
      }
    }
    
    // Si no hay sesión válida -> Pantalla de login.
    return const LoginScreen();
  }
}
