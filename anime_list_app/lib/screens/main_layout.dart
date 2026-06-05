import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'home_screen.dart';
import 'my_list_screen.dart';
import 'friends_tab_screen.dart';
import 'groups_tab_screen.dart';
import '../repositories/anime_repository.dart';
import '../utils/image_utils.dart';

/// Contenedor principal y esqueleto de la aplicación una vez logueado.
/// Administra el menú de navegación inferior (BottomNavigationBar) y el cambio de pestañas.
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  // Índice actual de la pestaña seleccionada (0: Home, 1: List, 2: Friends, 3: Groups).
  int _currentIndex = 0;
  final _animeRepo = AnimeRepository();

  final List<ScrollController> _scrollControllers = [
    ScrollController(), // HomeScreen
    ScrollController(), // MyListScreen
    ScrollController(), // FriendsTabScreen
    ScrollController(), // GroupsTabScreen
  ];

  late final List<Widget> _views = [
    HomeScreen(scrollController: _scrollControllers[0]),
    MyListScreen(scrollController: _scrollControllers[1]),
    FriendsTabScreen(scrollController: _scrollControllers[2]),
    GroupsTabScreen(scrollController: _scrollControllers[3]),
  ];

  @override
  void dispose() {
    for (var controller in _scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // OPTIMIZACIÓN DE RENDIMIENTO:
    // [addPostFrameCallback] nos permite retrasar las peticiones pesadas y precargas de imágenes
    // hasta que el primer frame de la pantalla se haya dibujado. Así se evita cualquier tipo de "lag" o tirones
    // visuales en la transición de la pantalla de login a esta interfaz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfileAndPrecache();
    });
  }

  /// Función asíncrona encargada de cargar los datos de perfil y realizar precarga en caché
  /// de imágenes pesadas para lograr transiciones instantáneas.
  Future<void> _loadProfileAndPrecache() async {
    // 1. Carga el perfil del usuario actual desde la caché local o Supabase.
    final profile = await _animeRepo.getCurrentUserProfile();
    
    // 2. Si el usuario tiene un avatar configurado, lo precargamos en la GPU del dispositivo.
    // De este modo, cuando el AppBar o el perfil intenten mostrar el avatar, aparecerá al instante sin parpadeos.
    if (profile != null && profile['avatar_url'] != null) {
      final String url = profile['avatar_url'];
      if (url.isNotEmpty && mounted) {
        // Soporta tanto URLs remotas (HTTP) como imágenes codificadas en Base64.
        if (url.startsWith('http')) {
          precacheImage(getImageProvider(url), context);
        } else if (url.startsWith('data:image')) {
          final String base64String = url.split(',').last;
          precacheImage(MemoryImage(base64Decode(base64String)), context);
        }
      }
    }

    // 3. Pre-cargamos el catálogo completo de avatares prediseñados de anime.
    // Esto asegura que cuando el usuario pulse en "Cambiar avatar", todas las opciones se rendericen instantáneamente.
    await Future.delayed(const Duration(milliseconds: 500)); // Pequeña espera por seguridad.
    
    try {
      final catalog = await _animeRepo.fetchAvatarCatalog();
      if (mounted) {
        for (var item in catalog) {
          final url = item['url'];
          if (url != null && url.startsWith('http')) {
            precacheImage(getImageProvider(url), context).catchError((_) => null);
          }
        }
      }
    } catch (e) {
      print('Error pre-cargando catálogo: $e');
    }
  }

  // Las vistas correspondientes a cada pestaña del menú inferior.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // [extendBody] a true permite que el cuerpo de la pantalla se extienda por debajo
      // de la barra de navegación inferior. Esto es fundamental para lograr el efecto visual
      // traslúcido y difuminado (Glassmorphism).
      extendBody: true,
      
      // [IndexedStack] es una optimización clave:
      // A diferencia de un operador ternario simple (que destruye y recrea las páginas al cambiar de tab),
      // IndexedStack mantiene vivas las 4 pantallas simultáneamente en memoria.
      // Esto significa que si estás haciendo scroll en el catálogo y cambias a tu lista,
      // al volver al catálogo estarás exactamente en la misma posición de scroll y con los datos cargados.
      body: IndexedStack(
        index: _currentIndex,
        children: _views,
      ),
      
      // Barra de navegación con efecto esmerilado de vidrio (Glassmorphism)
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          // [BackdropFilter] aplica un filtro de desenfoque gaussiano en tiempo real
          // sobre todo el contenido que pase por debajo de la barra.
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withOpacity(0.7), // Fondo oscuro semitransparente.
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (i) {
                if (_currentIndex == i) {
                  final controller = _scrollControllers[i];
                  if (controller.hasClients) {
                    controller.animateTo(
                      0.0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                    );
                  }
                } else {
                  setState(() => _currentIndex = i);
                }
              },
              backgroundColor: Colors.transparent, // Transparente para ver el desenfoque del BackdropFilter.
              type: BottomNavigationBarType.fixed,
              selectedItemColor: const Color(0xFFD095FF), // Color morado/neón del tema.
              unselectedItemColor: Colors.grey,
              showSelectedLabels: false,   // Ocultamos textos para un diseño minimalista premium.
              showUnselectedLabels: false,
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: _buildIcon(Icons.home, 0),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: _buildIcon(Icons.format_list_bulleted, 1),
                  label: 'List',
                ),
                BottomNavigationBarItem(
                  icon: _buildIcon(Icons.group, 2),
                  label: 'Friends',
                ),
                BottomNavigationBarItem(
                  icon: _buildIcon(Icons.diversity_3, 3),
                  label: 'Groups',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Construye un icono personalizado para la barra inferior.
  /// Genera un efecto de botón redondo iluminado si la pestaña está seleccionada.
  Widget _buildIcon(IconData iconData, int index) {
    bool isSelected = _currentIndex == index;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // Si está seleccionado, añade un fondo circular con el color de acento y baja opacidad.
        color: isSelected ? const Color(0xFFD095FF).withOpacity(0.2) : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(iconData),
    );
  }
}

