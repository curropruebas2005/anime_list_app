import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'dart:async';
import '../theme.dart';
import '../models/anime.dart';
import '../repositories/anime_repository.dart';
import 'anime_detail_screen.dart';
import 'profile_screen.dart';
import '../utils/image_utils.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/web_safe_image.dart';

class HomeScreen extends StatefulWidget {
  final ScrollController? scrollController;
  const HomeScreen({super.key, this.scrollController});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Anime>? _animes;
  bool _isLoading = true;
  bool _isOffline = false;
  final _animeRepo = AnimeRepository();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<State> _searchKey = GlobalKey<State>();
  
  // Custom Filters as dictated by the image
  String _selectedDemographic = 'Todos';
  String _selectedGenre = 'Todos';
  String _selectedTheme = 'Todos';
  String _selectedStatus = 'Todos';
  String _selectedOrder = 'Puntuación';
  String _selectedEra = 'Todos';
  String _selectedScore = 'Todos';
  bool _hideMyList = false;
  StreamSubscription<int>? _updateSubscription;
  Timer? _searchDebounce;
  
  // Paginación
  late final ScrollController _scrollController;
  final ScrollController _localScrollController = ScrollController();
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  final int _pageSize = 20;
  int _totalResults = 0;

  // Sincronizado con el esquema de la base de datos (ej: Naruto usa 'Shounen')
  final List<String> listDemographics = ['Todos', 'Shounen', 'Seinen', 'Shoujo', 'Josei', 'Kodomo'];
  final List<String> listGenres = ['Todos', 'Acción', 'Aventura', 'Comedia', 'Deportes', 'Drama', 'Fantasía', 'Ciencia Ficción', 'Terror', 'Romance', 'Misterio', 'Suspense', 'Psicológico', 'Recuentos de la vida', 'Gore', 'Harén'];
  final List<String> listThemes = ['Todos', 'Escolar', 'Artes Marciales', 'Deportes', 'Mecha', 'Isekai', 'Histórico', 'Sobrenatural', 'Superpoderes', 'Música'];
  final List<String> listStatuses = ['Todos', 'En emisión', 'Finalizado', 'Próximamente'];
  final List<String> listOrders = ['Puntuación', 'Nombre', 'Año', 'Episodios'];
  final List<String> listEras = ['Todos', 'Moderno', 'Clásico', 'Retro'];
  final List<String> listScores = ['Todos', 'Joyas', 'Recomendados'];

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? _localScrollController;
    _fetchData();
    
    // Suscribirse a actualizaciones globales de animes
    _updateSubscription = AnimeRepository.onAnimeUpdated.listen((malId) {
      _updateSingleAnime(malId);
    });

    // Búsqueda en tiempo real
    _searchController.addListener(_onSearchChanged);

    // Listener de Scroll Infinito
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
        if (!_isLoadingMore && _hasMore && !_isLoading) {
          _loadMore();
        }
      }
    });

    // Escuchar cambios de conexión (Fase 3 Refinada)
    _animeRepo.connectionStatus.addListener(_onConnectionChanged);
    _isOffline = !_animeRepo.connectionStatus.value;
  }

  void _onConnectionChanged() {
    if (mounted) {
      setState(() {
        _isOffline = !_animeRepo.connectionStatus.value;
      });
    }
  }

  /// Algoritmo de "Debouncing":
  /// Evita lanzar peticiones API innecesarias cada vez que el usuario pulsa una letra.
  /// Cancela el temporizador activo actual y abre uno nuevo de 500 milisegundos.
  /// Si el usuario no teclea nada más durante ese medio segundo, se ejecuta la búsqueda real.
  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _fetchData();
    });
  }

  @override
  void dispose() {
    _animeRepo.connectionStatus.removeListener(_onConnectionChanged);
    _updateSubscription?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    if (widget.scrollController == null) {
      _localScrollController.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchData({bool refresh = true}) async {
    if (refresh) {
      setState(() {
        _isLoading = _animes == null; // Solo cargador central si la lista está vacía
        _currentPage = 0;
        _hasMore = true;
        // No vaciamos _animes aquí para evitar que la pantalla "salte"
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final result = await AnimeRepository().fetchAnimes(
        statusFilter: _selectedStatus,
        demographicFilter: _selectedDemographic,
        genreFilter: _selectedGenre,
        themeFilter: _selectedTheme,
        orderFilter: _selectedOrder,
        eraFilter: _selectedEra,
        scoreFilter: _selectedScore,
        hideMyList: _hideMyList,
        search: _searchController.text.trim(),
        page: _currentPage,
        pageSize: _pageSize,
      );
      
      final List<Anime> data = result['list'];
      final int totalCount = result['total'];
      
      if (mounted) {
        setState(() {
          _totalResults = totalCount;
          if (refresh) {
            _animes = data;
          } else {
            // Deduplicación manual por malId para seguridad total
            final existingIds = _animes!.map((a) => a.malId).toSet();
            final newItems = data.where((a) => !existingIds.contains(a.malId)).toList();
            _animes!.addAll(newItems);
          }

          _hasMore = data.length == _pageSize;
        });
        
        // Precarga de imágenes de la nueva página (especialmente eficaz en móvil)
        if (data.isNotEmpty) {
          _precacheAnimeImages(data);
        }

        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _loadMore() async {
    _currentPage++;
    await _fetchData(refresh: false);
  }

  void _precacheAnimeImages(List<Anime> animes) {
    for (var anime in animes.take(10)) {
      String? url = anime.imageUrl;
      if (url != null && url.isNotEmpty) {
        precacheImage(getImageProvider(url), context).catchError((_) => null);
      }
    }
  }

  // Actualiza un solo anime en la lista para evitar recargas completas
  Future<void> _updateSingleAnime(int malId) async {
    if (_animes == null) return;
    
    final index = _animes!.indexWhere((a) => a.malId == malId);
    if (index != -1) {
      final updatedAnime = await AnimeRepository().fetchAnimeById(malId);
      if (updatedAnime != null && mounted) {
        setState(() {
          _animes![index] = updatedAnime;
        });
      }
    }
  }

  /// PATRÓN DE DISEÑO AVANZADO: Actualizaciones Optimistas (Optimistic UI)
  /// Esta técnica actualiza la interfaz de usuario de forma instantánea asumiendo que la petición
  /// de red a Supabase tendrá éxito. Si la petición falla, la app "rebobina" el cambio.
  Future<void> _quickSaveAnime(Anime anime) async {
    // Almacenamos el estado anterior por si tenemos que revertir el cambio en caso de fallo de red.
    final String? oldStatus = anime.myStatus;

    // Caso A: El anime ya está en la lista. Preguntamos al usuario si desea eliminarlo de su colección.
    if (anime.myStatus != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Gestionar Anime', style: TextStyle(color: Colors.white)),
          content: Text('¿Quieres quitar "${anime.title}" de tu lista personal?', style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Quitar de la lista', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        // 1. ACTUALIZACIÓN OPTIMISTA: Eliminamos visualmente el anime de inmediato (localmente).
        setState(() {
          final index = _animes?.indexWhere((a) => a.malId == anime.malId);
          if (index != null && index != -1) {
            _animes![index] = anime.copyWith(myStatus: null);
          }
        });

        try {
          // 2. Ejecutamos la petición asíncrona real en segundo plano.
          await AnimeRepository().removeFromUserList(anime.malId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Anime eliminado de tu lista'), backgroundColor: Colors.redAccent)
            );
          }
        } catch (e) {
          // 3. REVERSIÓN (Rollback): Si la petición a Supabase falla, restauramos el estado previo con [oldStatus].
          setState(() {
            final index = _animes?.indexWhere((a) => a.malId == anime.malId);
            if (index != null && index != -1) {
              _animes![index] = anime.copyWith(myStatus: oldStatus);
            }
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red),
            );
          }
        }
      }
      return;
    }

    // Caso B: El anime no está en la lista.
    // 1. ACTUALIZACIÓN OPTIMISTA: Lo marcamos como "Pendiente" de inmediato en la UI local.
    setState(() {
      final index = _animes?.indexWhere((a) => a.malId == anime.malId);
      if (index != null && index != -1) {
        _animes![index] = Anime(
          malId: anime.malId, title: anime.title, imageUrl: anime.imageUrl,
          score: anime.score, synopsis: anime.synopsis, status: anime.status,
          genres: anime.genres, demographic: anime.demographic,
          year: anime.year, episodes: anime.episodes,
          myStatus: 'Pendiente', // Guardado local instantáneo.
        );
      }
    });

    try {
      // 2. Ejecutamos la petición remota real en segundo plano.
      await AnimeRepository().updateUserAnimeStatus(anime.malId, 'Pendiente');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.black),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${anime.title} añadido a tu lista como Pendiente',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(20),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // 3. REVERSIÓN (Rollback): Si falla, volvemos a ponerlo como null (sin guardar).
      setState(() {
        final index = _animes?.indexWhere((a) => a.malId == anime.malId);
        if (index != null && index != -1) {
          _animes![index] = Anime(
            malId: anime.malId, title: anime.title, imageUrl: anime.imageUrl,
            score: anime.score, synopsis: anime.synopsis, status: anime.status,
            genres: anime.genres, demographic: anime.demographic,
            year: anime.year, episodes: anime.episodes,
            myStatus: null,
          );
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildFilterChipsSection({
    required String title, 
    required List<String> options, 
    required String selectedOption, 
    required Function(String) onSelect
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title.toUpperCase(), 
            style: TextStyle(
              fontWeight: FontWeight.w900, 
              fontSize: 11, 
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
            )
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options.map((option) {
            final isSelected = selectedOption == option;
            return GestureDetector(
              onTap: () => onSelect(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: isSelected 
                    ? LinearGradient(
                        colors: [
                          const Color(0xFFD095FF), // AppTheme.primary
                          const Color(0xFFD095FF).withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ) 
                    : null,
                  color: isSelected 
                    ? null 
                    : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.1),
                  border: Border.all(
                    color: isSelected 
                      ? const Color(0xFFD095FF).withOpacity(0.5)
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                    width: 1.5,
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: const Color(0xFFD095FF).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ] : [],
                ),
                margin: const EdgeInsets.only(left: 4, right: 4, bottom: 4), // Para evitar el recorte de la sombra
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Theme.of(context).colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            return Container(
              padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      Text('Filtros', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          setModalState(() {
                            setState(() {
                              _selectedDemographic = 'Todos';
                              _selectedGenre = 'Todos';
                              _selectedTheme = 'Todos';
                              _selectedStatus = 'Todos';
                              _selectedOrder = 'Puntuación';
                              _selectedEra = 'Todos';
                              _selectedScore = 'Todos';
                              _hideMyList = false;
                            });
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.redAccent),
                        label: const Text('Restablecer', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFilterChipsSection(
                            title: 'Tipo de público', 
                            options: listDemographics, 
                            selectedOption: _selectedDemographic, 
                            onSelect: (val) => setModalState(() => setState(() => _selectedDemographic = val)),
                          ),
                          _buildFilterChipsSection(
                            title: 'Géneros', 
                            options: listGenres, 
                            selectedOption: _selectedGenre, 
                            onSelect: (val) => setModalState(() => setState(() => _selectedGenre = val)),
                          ),
                          _buildFilterChipsSection(
                            title: 'Temáticas', 
                            options: listThemes, 
                            selectedOption: _selectedTheme, 
                            onSelect: (val) => setModalState(() => setState(() => _selectedTheme = val)),
                          ),
                          _buildFilterChipsSection(
                            title: 'Estado de emisión', 
                            options: listStatuses, 
                            selectedOption: _selectedStatus, 
                            onSelect: (val) => setModalState(() => setState(() => _selectedStatus = val)),
                          ),
                          _buildFilterChipsSection(
                            title: 'Época de emisión', 
                            options: listEras, 
                            selectedOption: _selectedEra, 
                            onSelect: (val) => setModalState(() => setState(() => _selectedEra = val)),
                          ),
                          _buildFilterChipsSection(
                            title: 'Calidad / Puntuación', 
                            options: listScores, 
                            selectedOption: _selectedScore, 
                            onSelect: (val) => setModalState(() => setState(() => _selectedScore = val)),
                          ),
                          _buildFilterChipsSection(
                            title: 'Ordenar por', 
                            options: listOrders, 
                            selectedOption: _selectedOrder, 
                            onSelect: (val) => setModalState(() => setState(() => _selectedOrder = val)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Configuración Personal al final
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ocultar animes en mi lista', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Solo verás animes que no has guardado', style: TextStyle(fontSize: 11)),
                      value: _hideMyList,
                      activeColor: const Color(0xFFD095FF),
                      onChanged: (val) => setModalState(() => setState(() => _hideMyList = val)),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Apply Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C4FF), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                      ),
                      onPressed: () {
                        _fetchData();
                        Navigator.pop(context);
                      },
                      child: const Text('Aplicar y Buscar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = (screenWidth * 0.05).clamp(16.0, 32.0);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlobalAppBar(
        titleWidget: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppTheme.primary, Color(0xFF00E0FF)],
          ).createShader(bounds),
          child: const Text('Tomodachi', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white)),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchData(refresh: true);
        },
        color: AppTheme.primary,
        edgeOffset: MediaQuery.of(context).padding.top + 100,
        displacement: 150,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 80, 
              bottom: 125, 
              left: horizontalPadding, 
              right: horizontalPadding
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
            if (_isOffline)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Modo Offline: Algunos datos pueden ser una versión guardada.',
                        style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // SEARCH AND FILTER BANNER
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: _searchKey,
                    controller: _searchController,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                      hintText: 'Buscar anime por título...',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF00C4FF))),
                      contentPadding: const EdgeInsets.symmetric(vertical: 20)
                    ),
                    onSubmitted: (_) => _fetchData(),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _showFilterModal,
                  icon: Icon(Icons.tune, color: Theme.of(context).colorScheme.onSurface, size: 20),
                  label: Text('Filtros', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                    side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    backgroundColor: Theme.of(context).colorScheme.surface,
                  ),
                )
              ],
            ),
            const SizedBox(height: 32),

            // DYNAMIC COMPRESSED LIST (STABLE SCROLL)
            Builder(
              builder: (context) {
                if (_isLoading) {
                   return const Center(child: Padding(padding: EdgeInsets.only(top: 160), child: CircularProgressIndicator(color: AppTheme.primary)));
                }
                
                final animes = _animes ?? [];
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _searchController.text.isEmpty && _selectedGenre == 'Todos' && _selectedStatus == 'Todos'
                        ? 'Explora toda la colección ($_totalResults animes)'
                        : 'Encontrados $_totalResults animes',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                      ),
                    ),
                    const SizedBox(height: 16),
                     if (animes.isNotEmpty)
                      Column(
                         children: [
                           ...animes.map((anime) => Padding(
                             padding: const EdgeInsets.only(bottom: 16),
                             child: _buildAnimeFeedCard(
                               context: context,
                               anime: anime,
                             ),
                           )).toList(),
                           if (_isLoadingMore)
                             const Padding(
                               padding: EdgeInsets.symmetric(vertical: 24),
                               child: Center(child: CircularProgressIndicator(color: Color(0xFF00C4FF))),
                             ),
                           if (!_hasMore && animes.length > 5)
                             Padding(
                               padding: const EdgeInsets.symmetric(vertical: 32),
                               child: Center(
                                 child: Text(
                                   "Has llegado al final de la colección ✨",
                                   style: TextStyle(
                                     color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                                     fontSize: 12,
                                     fontWeight: FontWeight.bold
                                   )
                                 ),
                               ),
                             ),
                         ],
                      )
                    else 
                      const Center(child: Text("No se encontraron animes.", style: TextStyle(color: Colors.grey))),
                  ],
                );
              },
            ),
            ]),
          ),
        ),
      ],
    ),
  ),
);
}

  Widget _buildAnimeFeedCard({required BuildContext context, required Anime anime, bool isDuplicateHero = false}) {
    final cardContent = SizedBox(
      width: 110,
      height: 160,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
        child: WebSafeImage(
          url: anime.imageUrl,
          fit: BoxFit.cover,
          width: 110,
          height: 160,
        ),
      ),
    );

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime))),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05)),
          boxShadow: [
             BoxShadow(color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 5))
          ]
        ),
        child: Row(
          children: [
            cardContent,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            anime.title,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text(anime.score.toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${anime.genres.join(', ')} - ${anime.demographic}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: anime.status == 'En emisión' ? const Color(0xFF4AC2F5).withOpacity(0.15) : const Color(0xFF26FEDC).withOpacity(0.15),
                            border: Border.all(color: anime.status == 'En emisión' ? const Color(0xFF4AC2F5).withOpacity(0.5) : const Color(0xFF26FEDC).withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            anime.status,
                            style: TextStyle(color: anime.status == 'En emisión' ? const Color(0xFF4AC2F5) : const Color(0xFF26FEDC), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "${anime.episodes} Eps • ${anime.year}",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        // Acción de guardado rápido y botón Ver más en la misma fila
                        Row(
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _quickSaveAnime(anime),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: anime.myStatus != null 
                                        ? AppTheme.primary.withOpacity(0.2) 
                                        : AppTheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: anime.myStatus != null 
                                        ? Border.all(color: AppTheme.primary.withOpacity(0.5)) 
                                        : null,
                                  ),
                                  child: Icon(
                                    anime.myStatus != null ? Icons.bookmark_added_rounded : Icons.bookmark_add_rounded, 
                                    color: AppTheme.primary, 
                                    size: 18
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF9147FF).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                "Ver más",
                                style: TextStyle(color: Color(0xFF9147FF), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
