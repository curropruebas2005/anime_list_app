import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../utils/image_utils.dart';
import '../widgets/global_app_bar.dart';
import '../repositories/anime_repository.dart';
import '../models/anime.dart';
import 'anime_detail_screen.dart';
import '../widgets/web_safe_image.dart';

class MyListScreen extends StatefulWidget {
  final ScrollController? scrollController;
  const MyListScreen({super.key, this.scrollController});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  int _selectedTab = 0; // Default to 'Pendiente'
  final _animeRepo = AnimeRepository();
  List<Map<String, dynamic>> _userAnimes = [];
  bool _isLoading = true;
  bool _isOffline = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  StreamSubscription<int>? _updateSubscription;
  Timer? _searchDebounce;

  late final ScrollController _scrollController;
  final ScrollController _localScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? _localScrollController;
    _loadList();
    _searchController.addListener(_onSearchChanged);

    // Escuchar cambios globales y refrescar la lista completa
    _updateSubscription = AnimeRepository.onAnimeUpdated.listen((_) {
      _loadList();
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

  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase();
        });
      }
    });
  }

  Future<void> _loadList() async {
    setState(() => _isLoading = true);
    final user = AnimeRepository().supabase.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final statusMap = {0: 'Pendiente', 1: 'Viendo', 2: 'Visto', 3: 'Favoritos'};
    final targetStatus = statusMap[_selectedTab] ?? 'Pendiente';
    
    // Obtenemos la lista detallada
    List<Map<String, dynamic>> allData = [];
    bool isOfflineMode = false;
    
    try {
      allData = await _animeRepo.fetchUserDetailedList(user.id);
      // Si el repo nos devolvió datos pero hubo un error de red interno (que el repo capturó),
      // no sabemos si es offline a menos que comprobemos la conectividad o el repo nos avise.
      // Pero para simplificar Fase 3, asumiremos que si tarda o falla el backend real, el repo da caché.
      // Podríamos añadir un flag en el repo, pero por ahora comprobaremos si el repo falló internamente.
    } catch (e) {
      isOfflineMode = true;
    }

    if (allData.isEmpty) {
      // Intentar cargar de nuevo pero forzando a pensar que podríamos estar offline si el repo retornó nada
      // En realidad el repo ya maneja el try-catch de Supabase y retorna caché.
    }
    
    if (mounted) {
      setState(() {
        // 1. Filtramos por el estado de la pestaña actual
        // 1. Filtramos por el estado de la pestaña actual o por favorito
        if (targetStatus == 'Favoritos') {
          _userAnimes = allData.where((item) => item['is_favorite'] == true).toList();
        } else {
          _userAnimes = allData.where((item) => item['status'] == targetStatus).toList();
        }

        // 2. Aplicamos la lógica de ordenación
        if (targetStatus == 'Visto') {
          // Orden por valoración (Personal > Pública)
          _userAnimes.sort((a, b) {
            final aPersonal = (a['review']?['rating'] as num?)?.toDouble();
            final aPublic = (a['anime']?['score'] as num?)?.toDouble() ?? 0.0;
            final aEffective = aPersonal ?? aPublic;

            final bPersonal = (b['review']?['rating'] as num?)?.toDouble();
            final bPublic = (b['anime']?['score'] as num?)?.toDouble() ?? 0.0;
            final bEffective = bPersonal ?? bPublic;

            return bEffective.compareTo(aEffective); // Descendente
          });
        } else {
          // Orden por fecha de actualización (ya viene así del repo, pero aseguramos)
          _userAnimes.sort((a, b) {
            final aDate = DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime(2000);
            final bDate = DateTime.tryParse(b['updated_at'] ?? '') ?? DateTime(2000);
            return bDate.compareTo(aDate);
          });
        }
        
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredList {
    if (_searchQuery.isEmpty) return _userAnimes;
    
    // 1. Filtrar los que contienen el texto
    final filtered = _userAnimes.where((item) {
      final title = (item['anime']?['title'] as String?)?.toLowerCase() ?? "";
      return title.contains(_searchQuery);
    }).toList();
    
    // 2. Ordenar: primero los que EMPIEZAN por el texto, luego el resto
    filtered.sort((a, b) {
      final aTitle = (a['anime']?['title'] as String?)?.toLowerCase() ?? "";
      final bTitle = (b['anime']?['title'] as String?)?.toLowerCase() ?? "";
      
      final aStarts = aTitle.startsWith(_searchQuery);
      final bStarts = bTitle.startsWith(_searchQuery);
      
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      
      // Si ambos empiezan igual (o ninguno), mantenemos el orden original o alfabético
      return aTitle.compareTo(bTitle);
    });
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlobalAppBar(
        titleWidget: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppTheme.primary, Color(0xFFD095FF)],
          ).createShader(bounds),
          child: const Text('Colección', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white)),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadList,
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
              bottom: 135, 
              left: 16, 
              right: 16
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
              if (_isOffline)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Modo Offline: Viendo versión guardada',
                        style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _buildTabButton("Pendientes", 0)),
                      Expanded(child: _buildTabButton("Viendo", 1)),
                      Expanded(child: _buildTabButton("Vistos", 2)),
                      Expanded(child: _buildTabButton("Favoritos", 3)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Buscador de Animes
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar en mi lista...',
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                    prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                    suffixIcon: _searchQuery.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged();
                          },
                        )
                      : null,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8), 
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2))
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8), 
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2))
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8), 
                      borderSide: const BorderSide(color: Color(0xFF00C4FF))
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                const Center(child: Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ))
              else if (_filteredList.isEmpty)
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 60),
                      Icon(Icons.search_off_rounded, size: 64, color: AppTheme.onSurfaceVariant.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty ? 'Aún no tienes animes en esta sección' : 'No se encontraron resultados para tu búsqueda',
                        style: TextStyle(color: AppTheme.onSurfaceVariant.withOpacity(0.5)),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: _filteredList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _filteredList[index];
                    final animeData = item['anime'] as Map<String, dynamic>;
                    final anime = Anime.fromMap(animeData);
                    final myRating = (item['review']?['rating'] as num?)?.toDouble();
                    final publicScore = (animeData['score'] as num?)?.toDouble() ?? 0.0;
                    
                    return GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)),
                        );
                        _loadList(); // Refrescar al volver
                      },
                      child: _buildListItem(
                        anime: anime,
                        status: item['status'],
                        episodesWatched: item['episodes_watched'],
                        rating: myRating ?? publicScore,
                        isPersonalRating: myRating != null,
                      ),
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

  Widget _buildTabButton(String title, int index) {
    bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedTab = index);
        _loadList();
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelected ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildListItem({
    required Anime anime,
    required String status,
    required int episodesWatched,
    required double rating,
    required bool isPersonalRating,
  }) {
    final progress = anime.episodes > 0 ? episodesWatched / anime.episodes : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          // Portada
          WebSafeImage(
            url: anime.imageUrl,
            width: 50,
            height: 70,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(width: 16),
          // Info Central
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anime.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "Ep. $episodesWatched / ${anime.episodes}",
                  style: TextStyle(color: AppTheme.onSurfaceVariant.withOpacity(0.7), fontSize: 11),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Nota a la derecha
          Column(
            children: [
              Icon(Icons.star_rounded, color: isPersonalRating ? Colors.amber : AppTheme.onSurfaceVariant.withOpacity(0.3), size: 18),
              const SizedBox(height: 2),
              Text(
                rating % 1 == 0 ? rating.toInt().toString() : rating.toStringAsFixed(1),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isPersonalRating ? AppTheme.primary : AppTheme.onSurfaceVariant,
                ),
              ),
              if (isPersonalRating)
                const Text("TUYA", style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: AppTheme.primary)),
            ],
          ),
        ],
      ),
    );
  }
}
