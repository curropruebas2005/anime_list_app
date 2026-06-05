import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/web_safe_image.dart';
import '../repositories/anime_repository.dart';
import '../models/anime.dart';
import 'anime_detail_screen.dart';
import 'user_profile_screen.dart';
import '../utils/image_utils.dart';
import 'full_activity_screen.dart';

class FriendsTabScreen extends StatefulWidget {
  final ScrollController? scrollController;
  const FriendsTabScreen({super.key, this.scrollController});

  @override
  State<FriendsTabScreen> createState() => _FriendsTabScreenState();
}

class _FriendsTabScreenState extends State<FriendsTabScreen> {
  int _selectedTab = 0; // 0: Amigos, 1: Actividad
  final _animeRepo = AnimeRepository();
  bool _isLoading = true;

  // Datos sociales
  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> _sentFriendRequests = []; // Solicitudes enviadas por MÍ
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _animeActivity = [];
  List<Map<String, dynamic>> _reviewActivity = [];

  // Buscador de actividad
  final TextEditingController _activitySearchController = TextEditingController();
  String _activitySearchQuery = "";
  StreamSubscription<void>? _friendsSubscription;

  late final ScrollController _scrollController;
  final ScrollController _localScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? _localScrollController;
    _loadSocialData();
    _animeRepo.profileUpdateNotifier.addListener(_loadSocialData);
    _activitySearchController.addListener(() {
      setState(() => _activitySearchQuery = _activitySearchController.text.toLowerCase());
    });

    // Escuchar actualizaciones de amigos en tiempo real
    _friendsSubscription = AnimeRepository.onFriendsUpdated.listen((_) {
      _loadSocialData();
    });
  }

  @override
  void dispose() {
    _friendsSubscription?.cancel();
    _animeRepo.profileUpdateNotifier.removeListener(_loadSocialData);
    _activitySearchController.dispose();
    if (widget.scrollController == null) {
      _localScrollController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSocialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final results = await Future.wait([
        _animeRepo.fetchFriendRequests(),
        _animeRepo.fetchSentFriendRequests(), // Nueva llamada
        _animeRepo.fetchFriendsWithWatchingStatus(),
        _animeRepo.fetchFriendsAnimeActivity(),
        _animeRepo.fetchFriendsReviewActivity(),
      ]);

      if (mounted) {
        setState(() {
          _friendRequests = results[0] as List<Map<String, dynamic>>;
          _sentFriendRequests = results[1] as List<Map<String, dynamic>>;
          _friends = results[2] as List<Map<String, dynamic>>;
          _animeActivity = results[3] as List<Map<String, dynamic>>;
          _reviewActivity = results[4] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error cargando datos sociales: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlobalAppBar(
        titleWidget: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppTheme.primary, AppTheme.primary],
          ).createShader(bounds),
          child: const Text('Social', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white)),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSocialData,
        color: AppTheme.primary,
        edgeOffset: MediaQuery.of(context).padding.top + 100,
        displacement: 150,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 80, 
            bottom: 200, 
            left: (MediaQuery.of(context).size.width * 0.05).clamp(16.0, 32.0), 
            right: (MediaQuery.of(context).size.width * 0.05).clamp(16.0, 32.0)
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabSelector(),
              const SizedBox(height: 32),
              _isLoading 
                ? const Center(child: Padding(padding: EdgeInsets.only(top: 200), child: CircularProgressIndicator(color: AppTheme.primary)))
                : _selectedTab == 0 ? _buildFriendsView() : _buildActivityView(),
            ],
          ),
        ),
      ),
      floatingActionButton: _selectedTab != 0 ? null : Padding(
        padding: const EdgeInsets.only(bottom: 125),
        child: FloatingActionButton(
          onPressed: _showAddFriendModal,
          backgroundColor: AppTheme.primary,
          child: const Icon(Icons.person_add, color: Colors.black),
        ),
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTabButton("Amigos", 0)),
          Expanded(child: _buildTabButton("Actividad", 1)),
        ],
      ),
    );
  }

  Widget _buildFriendsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Solicitudes RECIBIDAS
        if (_friendRequests.isNotEmpty) ...[
          _buildSectionHeader("Peticiones de amistad", "${_friendRequests.length} Pendientes", color: AppTheme.primary),
          const SizedBox(height: 16),
          SizedBox(
            height: 155,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _friendRequests.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final req = _friendRequests[index];
                final sender = req['sender'] as Map<String, dynamic>;
                return _buildFriendRequestCard(
                  id: req['id'],
                  name: sender['full_name'] ?? sender['username'] ?? 'Usuario',
                  imageUrl: sender['avatar_url'] ?? '',
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],

        // 🆕 Solicitudes ENVIADAS (Las que bloquean al usuario si no las ve)
        if (_sentFriendRequests.isNotEmpty) ...[
          _buildSectionHeader("Solicitudes Enviadas", "${_sentFriendRequests.length} Esperando", color: Colors.blueAccent),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sentFriendRequests.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final req = _sentFriendRequests[index];
                final receiver = req['receiver'] as Map<String, dynamic>;
                return _buildSentRequestCard(
                  id: req['id'],
                  name: receiver['full_name'] ?? receiver['username'] ?? 'Usuario',
                  imageUrl: receiver['avatar_url'] ?? '',
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],

        // Amigos Favoritos
        if (_friends.any((f) => f['isFavorite'] == true)) ...[
          _buildSectionHeader("Amigos Favoritos", "Destacados", color: Colors.amber),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _friends.where((f) => f['isFavorite'] == true).length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final favorites = _friends.where((f) => f['isFavorite'] == true).toList();
                final f = favorites[index];
                final profile = f['profile'] as Map<String, dynamic>;
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: profile))),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.amber, width: 2),
                        ),
                        child: WebSafeImage(
                          url: profile['avatar_url'] ?? '',
                          borderRadius: BorderRadius.circular(30),
                          useFadeIn: false,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 110,
                        child: Text(
                          profile['full_name'] ?? profile['username'] ?? 'Usuario',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Lista de amigos
        _buildSectionHeader("Mis Amigos", "${_friends.length} Amigos"),
        const SizedBox(height: 12),
        if (_friends.isEmpty)
          _buildEmptyState(Icons.people_outline, "Aún no tienes amigos")
        else
          ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero, // Eliminamos el padding por defecto que causaba el hueco
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _friends.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final friendData = _friends[index];
              final profile = friendData['profile'] as Map<String, dynamic>;
              final watching = friendData['watching'] as Map<String, dynamic>?;

              String statusText = "No está viendo nada";
              if (watching != null) {
                final anime = watching['animes'] as Map<String, dynamic>;
                statusText = "Viendo: ${anime['title']} - Ep. ${watching['episodes_watched']}";
              }

              return _buildConnectedFriendRow(
                name: profile['full_name'] ?? profile['username'] ?? 'Usuario',
                statusText: statusText,
                imageUrl: profile['avatar_url'] ?? '',
                isWatching: watching != null,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: profile))),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppTheme.onSurfaceVariant, size: 20),
                  color: const Color(0xFF2A2A2A),
                  onSelected: (val) {
                    if (val == 'remove') {
                      _handleRemoveFriend(profile['id'], profile['full_name'] ?? profile['username'] ?? 'Usuario');
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(Icons.person_remove, color: Colors.redAccent, size: 20),
                          SizedBox(width: 12),
                          Text('Eliminar Amigo', style: TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  List<Map<String, dynamic>> get _filteredAnimeActivity {
    if (_activitySearchQuery.isEmpty) return _animeActivity;
    return _animeActivity.where((act) {
      final profile = act['profile'] as Map<String, dynamic>;
      final fullName = (profile['full_name'] as String?)?.toLowerCase() ?? "";
      final username = (profile['username'] as String?)?.toLowerCase() ?? "";
      return fullName.contains(_activitySearchQuery) || username.contains(_activitySearchQuery);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredReviewActivity {
    if (_activitySearchQuery.isEmpty) return _reviewActivity;
    return _reviewActivity.where((rev) {
      final profile = rev['profile'] as Map<String, dynamic>;
      final fullName = (profile['full_name'] as String?)?.toLowerCase() ?? "";
      final username = (profile['username'] as String?)?.toLowerCase() ?? "";
      return fullName.contains(_activitySearchQuery) || username.contains(_activitySearchQuery);
    }).toList();
  }

  Widget _buildActivityView() {
    final filteredAnime = _filteredAnimeActivity;
    final filteredReview = _filteredReviewActivity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Buscador de Amigos
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: TextField(
            controller: _activitySearchController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar por amigo...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.primary),
              suffixIcon: _activitySearchQuery.isNotEmpty 
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => _activitySearchController.clear(),
                  )
                : null,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppTheme.outlineVariant.withOpacity(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppTheme.outlineVariant.withOpacity(0.1)),
              ),
            ),
          ),
        ),

        // Actualizaciones de Animes
        _buildSectionHeader("Actualizaciones", "${filteredAnime.length} Recientes"),
        const SizedBox(height: 16),
        if (filteredAnime.isEmpty)
          _buildEmptyState(Icons.update, _activitySearchQuery.isEmpty ? "No hay actualizaciones recientes" : "No hay actividad de este amigo")
        else ...[
        ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredAnime.length > 10 ? 10 : filteredAnime.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final act = filteredAnime[index];
            final profile = act['profile'] as Map<String, dynamic>;
            final anime = act['animes'] as Map<String, dynamic>;
            
            return _buildActivityRow(
              name: profile['full_name'] ?? profile['username'] ?? 'Usuario',
              animeTitle: anime['title'],
              status: act['status'],
              episode: act['episodes_watched'],
              imageUrl: profile['avatar_url'] ?? '',
              animeImageUrl: anime['image_url'] ?? '',
              onAnimeTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: Anime.fromMap(anime)))),
              onUserTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: profile))),
            );
          },
        ),
        if (filteredAnime.length > 10)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _navigateToFullActivity("Actualizaciones", _animeActivity, "activity"),
              child: const Text("Ver todas las actualizaciones", style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
        
        const SizedBox(height: 32),

        // Valoraciones y Reseñas
        _buildSectionHeader("Valoraciones", "${filteredReview.length} Opiniones"),
        const SizedBox(height: 16),
        if (filteredReview.isEmpty)
          _buildEmptyState(Icons.star_outline, _activitySearchQuery.isEmpty ? "No hay valoraciones recientes" : "No hay reseñas de este amigo")
        else ...[
        ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredReview.length > 10 ? 10 : filteredReview.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final rev = filteredReview[index];
            final profile = rev['profile'] as Map<String, dynamic>;
            final anime = rev['animes'] as Map<String, dynamic>;
            
            return _buildReviewCard(
              name: profile['full_name'] ?? profile['username'] ?? 'Usuario',
              animeTitle: anime['title'],
              rating: (rev['rating'] as num).toDouble(),
              opinion: rev['opinion'] ?? '',
              imageUrl: profile['avatar_url'] ?? '',
              animeImageUrl: anime['image_url'] ?? '',
              onAnimeTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: Anime.fromMap(anime)))),
              onUserTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: profile))),
            );
          },
        ),
        if (filteredReview.length > 10)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _navigateToFullActivity("Valoraciones", _reviewActivity, "review"),
              child: const Text("Ver todas las valoraciones", style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
      ],
    );
  }

  // --- WIDGET HELPERS ---

  Widget _buildSectionHeader(String title, String count, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (color ?? AppTheme.onSurfaceVariant).withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(count, style: TextStyle(color: color ?? AppTheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(icon, size: 48, color: AppTheme.onSurfaceVariant.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: AppTheme.onSurfaceVariant.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.black : AppTheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildFriendRequestCard({required int id, required String name, required String imageUrl}) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          WebSafeImage(url: wrapImageProxy(imageUrl), width: 48, height: 48, borderRadius: BorderRadius.circular(24)),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: IconButton(
                  icon: const Icon(Icons.check_circle, color: AppTheme.primary),
                  onPressed: () async {
                    await _animeRepo.respondToFriendRequest(id, true);
                    _loadSocialData();
                  },
                ),
              ),
              Expanded(
                child: IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                  onPressed: () async {
                    await _animeRepo.respondToFriendRequest(id, false);
                    _loadSocialData();
                  },
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSentRequestCard({required int id, required String name, required String imageUrl}) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          WebSafeImage(url: wrapImageProxy(imageUrl), width: 44, height: 44, borderRadius: BorderRadius.circular(22)),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          const Text("En espera...", style: TextStyle(fontSize: 10, color: Colors.white38)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => _handleCancelRequest(id, name),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                foregroundColor: Colors.redAccent.withOpacity(0.8),
              ),
              child: const Text("Cancelar", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _handleCancelRequest(int requestId, String name) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Cancelar Solicitud', style: TextStyle(color: Colors.white)),
        content: Text('¿Quieres retirar la solicitud de amistad enviada a $name?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Mantener', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar Petición', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _animeRepo.cancelFriendRequest(requestId);
        _loadSocialData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Solicitud cancelada'))
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  Future<void> _handleRemoveFriend(String friendId, String name) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Eliminar Amigo', style: TextStyle(color: Colors.white)),
        content: Text('¿Estás seguro de que quieres eliminar a $name de tu lista de amigos?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _animeRepo.removeFriend(friendId);
        _loadSocialData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Amistad eliminada con $name'), backgroundColor: Colors.redAccent)
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  Widget _buildConnectedFriendRow({
    required String name, 
    required String statusText, 
    required String imageUrl, 
    bool isWatching = false, 
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            WebSafeImage(url: wrapImageProxy(imageUrl), width: 44, height: 44, borderRadius: BorderRadius.circular(22), useFadeIn: false),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(statusText, style: TextStyle(color: isWatching ? AppTheme.primary : AppTheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right, color: AppTheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityRow({
    required String name, 
    required String animeTitle, 
    required String status, 
    required int episode, 
    required String imageUrl,
    required String animeImageUrl,
    VoidCallback? onUserTap,
    VoidCallback? onAnimeTap,
  }) {
    String actionStr = status == 'Viendo' ? 'está viendo' : 'ha terminado';
    String detailStr = status == 'Viendo' ? 'Episodio $episode' : '¡Visto!';

    return GestureDetector(
      onTap: onAnimeTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onUserTap,
              child: WebSafeImage(url: wrapImageProxy(imageUrl), width: 40, height: 40, borderRadius: BorderRadius.circular(20), useFadeIn: false),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                      children: [
                        TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: " $actionStr ", style: const TextStyle(color: AppTheme.onSurfaceVariant)),
                        TextSpan(text: animeTitle, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detailStr, 
                    style: const TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            WebSafeImage(url: wrapImageProxy(animeImageUrl), width: 40, height: 56, borderRadius: BorderRadius.circular(8)),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewCard({
  required String name,
  required String animeTitle,
  required double rating,
  required String opinion,
  required String imageUrl,
  required String animeImageUrl,
  VoidCallback? onUserTap,
  VoidCallback? onAnimeTap,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onUserTap,
                child: WebSafeImage(url: wrapImageProxy(imageUrl), width: 28, height: 28, borderRadius: BorderRadius.circular(14), useFadeIn: false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: onUserTap,
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                      children: [
                        TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(text: " ha valorado ", style: TextStyle(color: AppTheme.onSurfaceVariant)),
                        TextSpan(text: animeTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onAnimeTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: WebSafeImage(url: wrapImageProxy(animeImageUrl), width: 28, height: 38, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.secondary, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  rating % 1 == 0 ? rating.toInt().toString() : rating.toStringAsFixed(1), 
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)
                ),
              )
            ],
          ),
          if (opinion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                "\"$opinion\"",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

  void _navigateToFullActivity(String title, List<Map<String, dynamic>> items, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullActivityScreen(
          title: title,
          items: items,
          type: type,
        ),
      ),
    );
  }

  void _showAddFriendModal() {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    List<Map<String, dynamic>> suggestedUsers = [];
    bool isSearching = false;
    bool isLoadingSuggestions = true;
    Timer? debounce;

    final List<String> sentRequests = [];
    
    // Preparar lista de IDs a excluir (yo, admin, amigos, peticiones enviadas/recibidas)
    final List<String> excludeIds = [
      _animeRepo.currentUser?.id ?? '',
      'faedee87-29a1-4cc5-bcfe-127aab5b9998', // Admin tests
    ];
    for (var f in _friends) {
      if (f['profile'] != null) excludeIds.add(f['profile']['id']);
    }
    for (var r in _friendRequests) {
      if (r['profile'] != null) excludeIds.add(r['profile']['id']);
    }
    for (var s in _sentFriendRequests) {
      if (s['profile'] != null) excludeIds.add(s['profile']['id']);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Cargar sugerencias al abrir (solo una vez)
          if (isLoadingSuggestions && suggestedUsers.isEmpty) {
            _animeRepo.fetchSuggestedUsers(excludeIds: excludeIds).then((users) {
              if (context.mounted) {
                setModalState(() {
                  suggestedUsers = users;
                  isLoadingSuggestions = false;
                });
              }
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const Text("Añadir Amigos", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(
                  controller: searchController,
                  autofocus: true,
                  onChanged: (val) {
                    if (debounce?.isActive ?? false) debounce?.cancel();
                    debounce = Timer(const Duration(milliseconds: 500), () async {
                      if (val.trim().isEmpty) {
                        setModalState(() {
                          searchResults = [];
                          isSearching = false;
                        });
                        return;
                      }

                      setModalState(() => isSearching = true);
                      final users = await _animeRepo.searchUsers(val);
                      setModalState(() {
                        searchResults = users;
                        isSearching = false;
                      });
                    });
                  },
                  decoration: AppTheme.inputDecoration("Escribe un nombre...", Icons.search),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: isSearching 
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : (searchController.text.isEmpty)
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isLoadingSuggestions)
                              const Center(child: Padding(
                                padding: EdgeInsets.all(20.0),
                                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                              ))
                            else if (suggestedUsers.isNotEmpty) ...[
                              const Text("Sugerencias para ti", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary, letterSpacing: 1.2)),
                              const SizedBox(height: 16),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: suggestedUsers.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final user = suggestedUsers[index];
                                    return _buildUserSearchTile(user, sentRequests, setModalState);
                                  },
                                ),
                              ),
                            ] else
                              _buildEmptyState(Icons.person_search_rounded, "Usa el buscador para encontrar a alguien"),
                          ],
                        )
                      : searchResults.isEmpty
                        ? _buildEmptyState(Icons.person_off, "No se han encontrado usuarios")
                        : ListView.separated(
                            itemCount: searchResults.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final user = searchResults[index];
                              return _buildUserSearchTile(user, sentRequests, setModalState);
                            },
                          ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) => debounce?.cancel());
  }

  Widget _buildUserSearchTile(Map<String, dynamic> user, List<String> sentRequests, StateSetter setModalState) {
    final bool isAlreadyFriend = _friends.any((f) => f['profile']['id'] == user['id']);
    final bool isRequestSent = sentRequests.contains(user['id']);

    return ListTile(
      leading: WebSafeImage(url: user['avatar_url'] ?? '', width: 40, height: 40, borderRadius: BorderRadius.circular(20)),
      title: Text(user['full_name'] ?? user['username'] ?? 'Usuario', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: (user['username'] != null && user['username'] != user['full_name']) 
        ? Text("@${user['username']}", style: const TextStyle(fontSize: 12)) 
        : null,
      trailing: isAlreadyFriend
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.onSurfaceVariant.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text("Amigos", style: TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
          )
        : isRequestSent
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text("Enviada", style: TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.bold)),
            )
          : ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black, elevation: 0),
              onPressed: () async {
                try {
                  await _animeRepo.sendFriendRequest(user['id']);
                  setModalState(() {
                    sentRequests.add(user['id']);
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Petición enviada!')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text("Añadir"),
            ),
    );
  }
}
