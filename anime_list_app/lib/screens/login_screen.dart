import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme.dart';
import 'main_layout.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  bool _isSignUp = false;

  String _errorMessage(dynamic e) {
    if (e is AuthException) {
      switch (e.code) {
        case 'invalid_credentials':
          return 'Email o contraseña incorrectos';
        case 'email_not_confirmed':
          return 'Debes confirmar tu email antes de entrar';
        case 'user_already_exists':
          return 'Ya hay una cuenta con este email';
        case 'invalid_email':
          return 'El formato del email no es válido';
        case 'weak_password':
          return 'La contraseña es demasiado débil (mín. 6 caracteres)';
        default:
          return e.message;
      }
    }
    return 'Ocurrió un error inesperado: $e';
  }

  Future<void> _nativeGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      const webClientId = '497297504460-692oqncgrg2b23maao6fa48iomknkuon.apps.googleusercontent.com';
      
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: webClientId,
        serverClientId: webClientId,
        // Eliminamos scopes manuales por ahora para usar los por defecto (email, profile)
      );

      print('Limpiando sesión previa para forzar el selector...');
      await googleSignIn.signOut();

      print('Iniciando Google Sign In...');
      final googleUser = await googleSignIn.signIn();
      
      if (googleUser == null) {
        print('Google Sign In cancelado por el usuario.');
        setState(() => _isLoading = false);
        return;
      }

      print('Google Sign In exitoso. Obteniendo autenticación...');
      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      print('ID Token: ${idToken != null ? 'Obtenido' : 'NULL'}');

      if (idToken == null) {
        throw Exception('Google no ha devuelto el ID Token. Revisa que el Web Client ID sea correcto y que la pantalla de consentimiento esté configurada.');
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      // Navegación inmediata tras éxito (para no tener que reiniciar la app)
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainLayout()));
      }
    } on PlatformException catch (e) {
      print('DEBUG PLATFORM ERROR: ${e.code} - ${e.message}');
      if (mounted) {
        String errorMsg = 'Error: ${e.code}';
        if (e.code == 'sign_in_failed') errorMsg = 'Error 10/12500: Fallo de configuración o de Google Play Services. Revisa el SHA-1.';
        if (e.code == 'network_error') errorMsg = 'Error de conexión a internet.';
        
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Error de Google'),
            content: Text(errorMsg + '\n\nDetalle: ${e.message}'),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))],
          ),
        );
      }
    } catch (e) {
      print('ERROR CRÍTICO GOOGLE: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Error Inesperado'),
            content: Text(e.toString()),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAuth() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) return;
    if (_isSignUp && _usernameController.text.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, indica un nombre de usuario')));
       return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        // Sign Up
        final redirectUrl = kIsWeb ? null : 'tomodachi://login-callback';
        await _supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          data: {'full_name': _usernameController.text.trim()},
          emailRedirectTo: redirectUrl,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cuenta creada. Revisa tu email para verificarla.'),
            backgroundColor: AppTheme.primary,
          ));
          setState(() => _isSignUp = false);
        }
      } else {
        // Sign In
        await _supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainLayout()));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorMessage(e)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              themeProvider.isDarkMode ? const Color(0xFF1A0033) : colors.primary.withOpacity(0.05),
              Theme.of(context).scaffoldBackgroundColor,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'TOMODACHI', 
                  style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 36, fontWeight: FontWeight.w900, color: AppTheme.primary)
                ),
                const SizedBox(height: 8),
                Text(_isSignUp ? 'Crea tu cuenta de Tomodachi' : 'Bienvenido de nuevo', 
                     style: TextStyle(color: colors.onSurface.withOpacity(0.7))),
                const SizedBox(height: 48),
                
                if (_isSignUp) ...[
                  TextField(
                    controller: _usernameController,
                    style: TextStyle(color: colors.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Nombre de usuario',
                      labelStyle: TextStyle(color: colors.onSurface.withOpacity(0.5)),
                      filled: true,
                      fillColor: colors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.outlineVariant.withOpacity(0.1))),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                TextField(
                  controller: _emailController,
                  style: TextStyle(color: colors.onSurface),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(color: colors.onSurface.withOpacity(0.5)),
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.outlineVariant.withOpacity(0.1))),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  style: TextStyle(color: colors.onSurface),
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    labelStyle: TextStyle(color: colors.onSurface.withOpacity(0.5)),
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.outlineVariant.withOpacity(0.1))),
                  ),
                ),
                const SizedBox(height: 32),
                
                if (_isLoading) ...[
                  const CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 16),
                  Text("Iniciando sesión...", style: TextStyle(color: colors.onSurface.withOpacity(0.5))),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                        elevation: 0,
                      ),
                      onPressed: _handleAuth,
                      child: Text(_isSignUp ? 'Crear Cuenta' : 'Iniciar Sesión', 
                                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp ? '¿Ya tienes cuenta? Inicia sesión' : '¿No tienes cuenta? Regístrate gratis',
                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(child: Divider(color: colors.onSurface.withOpacity(0.1))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text("O continúa con", style: TextStyle(color: colors.onSurface.withOpacity(0.5))),
                      ),
                      Expanded(child: Divider(color: colors.onSurface.withOpacity(0.1))),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: colors.surface,
                        foregroundColor: colors.onSurface,
                        side: BorderSide(color: colors.outlineVariant.withOpacity(0.1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                      ),
                      icon: Image.network("https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png", width: 22, height: 22, errorBuilder: (c, e, s) => const Icon(Icons.g_mobiledata, size: 28)), 
                      label: const Text('Google', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      onPressed: _nativeGoogleSignIn,
                    ),
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
