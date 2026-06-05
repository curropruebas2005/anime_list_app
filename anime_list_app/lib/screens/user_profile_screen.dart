import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import '../theme.dart';
import '../models/anime.dart';
import 'anime_detail_screen.dart';
import '../repositories/anime_repository.dart';
import '../utils/image_utils.dart';
import '../widgets/web_safe_image.dart';
import '../widgets/smart_marquee.dart';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const UserProfileScreen({super.key, required this.userProfile});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _animeRepo = AnimeRepository();
  bool _isLoading = true;
  List<Anime> _favorites = [];
  List<Anime> _recentActivity = [];
  List<Map<String, dynamic>> _detailedList = [];
  int _totalVistos = 0;
  int _totalCapitulos = 0;
  String _sortOrder = 'recent'; // 'desc', 'asc', 'recent'
  bool _isFavorite = false;
  bool _isFriend = false;
  String _friendshipStatus = 'none'; // 'none', 'friends', 'pending_sent', 'pending_received'
  int? _requestId;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final userId = widget.userProfile['id'];
    final isMe = userId == _animeRepo.currentUser?.id;

    // Carga instantánea desde caché SOLO si es mi propio perfil
    if (isMe && AnimeRepository.cachedUserStats != null) {
      final cachedStats = AnimeRepository.cachedUserStats!;
      _totalVistos = cachedStats['vistos'] ?? 0;
      _totalCapitulos = cachedStats['capitulos'] ?? 0;
      _favorites = AnimeRepository.cachedFavorites ?? [];
      _isLoading = false; // Ya podemos mostrar algo inmediatamente
    } else {
      // Si no es mi perfil, nos aseguramos de estar en estado de carga y resetear estados previos
      setState(() {
        _isLoading = true;
        _isFriend = false;
        _friendshipStatus = 'none';
        _isFavorite = false;
      });
    }
    final results = await Future.wait<dynamic>([
      _animeRepo.fetchFavorites(userId: userId),
      _animeRepo.fetchRecentActivity(userId: userId),
      _animeRepo.fetchUserStats(userId: userId),
      _animeRepo.fetchUserDetailedList(userId),
    ]);

    if (mounted) {
      final stats = results[2] as Map<String, int>;
      
      // Verificar estado de amistad detallado
      String fStatus = 'none';
      int? rId;
      bool favorite = false;

      try {
        final rel = await _animeRepo.fetchFriendshipStatus(widget.userProfile['id']);
        fStatus = rel['status'] ?? 'none';
        favorite = rel['isFavorite'] ?? false;
        rId = rel['requestId'];
      } catch (_) {}

      setState(() {
        _favorites = results[0] as List<Anime>;
        _recentActivity = results[1] as List<Anime>;
        _totalVistos = stats['vistos'] ?? 0;
        _totalCapitulos = stats['capitulos'] ?? 0;
        _detailedList = results[3] as List<Map<String, dynamic>>;
        _isFavorite = favorite;
        _friendshipStatus = fStatus;
        _isFriend = fStatus == 'friends';
        _requestId = rId;
        _isLoading = false;
      });
    }
  }

  void _applySort(String criteria) {
    setState(() {
      _sortOrder = criteria;
      if (_sortOrder == 'recent') {
        _loadAllData(); // Recarga para obtener el orden por defecto de la DB
      } else {
        _detailedList.sort((a, b) {
          final aRating = (a['review']?['rating'] as num?)?.toDouble() ?? -1.0;
          final bRating = (b['review']?['rating'] as num?)?.toDouble() ?? -1.0;

          if (_sortOrder == 'desc') {
            return bRating.compareTo(aRating);
          } else {
            if (aRating == -1.0) return 1;
            if (bRating == -1.0) return -1;
            return aRating.compareTo(bRating);
          }
        });
      }
    });
  }

  Future<void> _handleRemoveFriend() async {
    final displayName = widget.userProfile['full_name'] ?? widget.userProfile['username'] ?? 'Usuario';
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Eliminar Amigo', style: TextStyle(color: Colors.white)),
        content: Text('¿Estás seguro de que quieres eliminar a $displayName de tu lista de amigos?', style: const TextStyle(color: Colors.white70)),
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
        await _animeRepo.removeFriend(widget.userProfile['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Amistad eliminada con $displayName'), backgroundColor: Colors.redAccent)
          );
          Navigator.pop(context); // Volver atrás ya que la relación cambió
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

  Future<void> _handleSendRequest() async {
    try {
      await _animeRepo.sendFriendRequest(widget.userProfile['id']);
      setState(() => _friendshipStatus = 'pending_sent');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud de amistad enviada'))
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  Future<void> _handleAcceptRequest() async {
    if (_requestId == null) return;
    try {
      await _animeRepo.respondToFriendRequest(_requestId!, true);
      setState(() {
        _friendshipStatus = 'friends';
        _isFriend = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Ahora sois amigos!'), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  Widget _buildFriendshipButton() {
    if (widget.userProfile['id'] == _animeRepo.currentUser?.id) return const SizedBox.shrink();

    switch (_friendshipStatus) {
      case 'none':
        return ElevatedButton.icon(
          onPressed: _handleSendRequest,
          icon: const Icon(Icons.person_add_rounded, size: 18),
          label: const Text("Añadir amigo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      case 'pending_sent':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty_rounded, size: 16, color: Colors.white54),
              SizedBox(width: 8),
              Text("Solicitud enviada", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      case 'pending_received':
        return ElevatedButton.icon(
          onPressed: _handleAcceptRequest,
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: const Text("Aceptar solicitud", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.userProfile;
    final displayName = profile['full_name'] ?? profile['username'] ?? 'Usuario';
    final username = profile['username'];
    final avatarUrl = profile['avatar_url'] ?? "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp&f=y";
    
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = (screenWidth * 0.06).clamp(16.0, 32.0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Perfil de $displayName', style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (!_isLoading && 
              widget.userProfile['id'] != _animeRepo.currentUser?.id && 
              _isFriend && 
              _friendshipStatus == 'friends')
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _isFavorite ? Colors.amber : Colors.white70,
                size: 26,
              ),
              onPressed: () async {
                final newStatus = !_isFavorite;
                try {
                  await _animeRepo.toggleFavoriteFriend(widget.userProfile['id'], newStatus);
                  setState(() => _isFavorite = newStatus);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'))
                    );
                  }
                }
              },
            ),
          if (_isFriend)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: const Color(0xFF2A2A2A),
              onSelected: (val) {
                if (val == 'remove') _handleRemoveFriend();
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
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Container
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.primary, width: 2),
                          ),
                          child: WebSafeImage(
                            url: avatarUrl,
                            borderRadius: BorderRadius.circular(40),
                            useFadeIn: false,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SmartMarquee(
                                text: displayName,
                                style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                              ),
                              if (username != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  "@$username", 
                                  style: TextStyle(color: AppTheme.primary.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              // Estado actual (Viendo)
                              if (!_isLoading && _detailedList.any((e) => e['status'] == 'Viendo')) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.play_circle_outline_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: SmartMarquee(
                                        text: () {
                                          final entry = _detailedList.firstWhere((e) => e['status'] == 'Viendo');
                                          final title = entry['anime']['title'] ?? 'Anime';
                                          final ep = entry['episodes_watched'] ?? 0;
                                          return "Viendo: $title - Ep. $ep";
                                        }(),
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold),
                                        height: 18,
                                        blankSpace: 30.0,
                                        pauseAfterRound: const Duration(seconds: 1),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                Center(
                  child: _buildFriendshipButton(),
                ),
                
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatColumn(_totalVistos.toString(), 'Animes vistos'),
                    Container(width: 1, height: 40, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2), margin: const EdgeInsets.symmetric(horizontal: 20)),
                    _buildStatColumn(_totalCapitulos.toString(), 'Capítulos vistos'),
                  ],
                ),
                
                const SizedBox(height: 32),

                // Favorites Section
                _buildHorizontalSection('FAVORITOS DE $displayName', _favorites, horizontalPadding),
                
                const SizedBox(height: 24),

                // Recent Activity Section
                _buildHorizontalSection('ACTIVIDAD RECIENTE', _recentActivity, horizontalPadding),

                const SizedBox(height: 32),
                
                // Detailed List Section
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('TODA SU LISTA', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: AppTheme.primary)),
                      PopupMenuButton<String>(
                        onSelected: _applySort,
                        color: Theme.of(context).colorScheme.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        offset: const Offset(0, 40),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _sortOrder != 'recent' ? AppTheme.primary.withOpacity(0.1) : Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _sortOrder != 'recent' ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 14,
                                color: _sortOrder != 'recent' ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _sortOrder == 'desc' ? 'Mayor nota' : (_sortOrder == 'asc' ? 'Menor nota' : 'Más reciente'),
                                style: TextStyle(
                                  fontSize: 11, 
                                  fontWeight: FontWeight.bold,
                                  color: _sortOrder != 'recent' ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: _sortOrder != 'recent' ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
                            ],
                          ),
                        ),
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'recent', child: Text('Más reciente')),
                          const PopupMenuItem(value: 'desc', child: Text('Mayor nota')),
                          const PopupMenuItem(value: 'asc', child: Text('Menor nota')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_detailedList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text('Aún no tiene animes en su lista'),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    itemCount: _detailedList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final item = _detailedList[index];
                      final animeMap = item['anime'] as Map<String, dynamic>;
                      final anime = Anime.fromMap(animeMap);
                      final review = item['review'] as Map<String, dynamic>?;
                      
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime))),
                        child: _buildDetailCard(anime, item['status'], item['episodes_watched'], review),
                      );
                    },
                  ),
                const SizedBox(height: 48),
              ],
            ),
          ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.primary)),
        Text(label.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _buildHorizontalSection(String title, List<Anime> animes, double horizontalPadding) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: AppTheme.primary)),
        ),
        const SizedBox(height: 16),
        if (animes.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Text('Nada por aquí...', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5))),
          )
        else
          SizedBox(
            height: 170,
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding - 8),
              scrollDirection: Axis.horizontal,
              itemCount: animes.length,
              itemBuilder: (context, index) {
                final anime = animes[index];
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime))),
                  child: Container(
                    width: 100,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: WebSafeImage(
                              url: anime.imageUrl,
                              height: 130,
                              width: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(anime.title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDetailCard(Anime anime, String status, int episodes, Map<String, dynamic>? review) {
    Color statusColor;
    switch (status) {
      case 'Viendo': statusColor = Colors.blue; break;
      case 'Visto': statusColor = Colors.green; break;
      case 'Pendiente': statusColor = Colors.orange; break;
      default: statusColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08)), // Borde más visible para separación
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WebSafeImage(url: wrapImageProxy(anime.imageUrl), width: 60, height: 80, fit: BoxFit.cover),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(anime.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status, 
                        style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('$episodes / ${anime.episodes} episodios', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              if (review != null)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppTheme.secondary, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Colors.black, size: 14),
                      const SizedBox(width: 2),
                      Text(review['rating'].toString(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          if (review != null && review['opinion'] != null && review['opinion'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                review['opinion'],
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
