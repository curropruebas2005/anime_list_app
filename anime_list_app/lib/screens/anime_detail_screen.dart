import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../models/anime.dart';
import '../utils/image_utils.dart';
import '../repositories/anime_repository.dart';
import 'user_profile_screen.dart';
import 'profile_screen.dart';
import '../widgets/web_safe_image.dart';

class AnimeDetailScreen extends StatefulWidget {
  final Anime anime;
  
  const AnimeDetailScreen({super.key, required this.anime});

  @override
  _AnimeDetailScreenState createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends State<AnimeDetailScreen> {
  bool _isFavorite = false;
  Map<String, dynamic>? _listEntry;
  final _animeRepo = AnimeRepository();
  StreamSubscription<int>? _updateSubscription;

  @override
  void initState() {
    super.initState();
    _myRating = widget.anime.myRating; // Carga instantánea
    _listEntry = widget.anime.myStatus != null ? {'status': widget.anime.myStatus} : null; // Carga instantánea
    _isFavorite = widget.anime.isFavorite; // Carga instantánea
    _averageScore = AnimeRepository.getAverageRatingFromCache(widget.anime.malId); 
    _loadAllData();

    // Escuchar actualizaciones globales para este anime específico
    _updateSubscription = AnimeRepository.onAnimeUpdated.listen((malId) {
      if (malId == widget.anime.malId) {
        _loadAllData();
      }
    });
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precargar imagen para evitar parpadeo en Web
    precacheImage(getImageProvider(widget.anime.imageUrl), context);
  }

  Future<void> _loadAllData() async {
    if (mounted) {
      setState(() {
        _reviews = [];
        _averageScore = AnimeRepository.getAverageRatingFromCache(widget.anime.malId);
        // NO reseteamos _myRating, _listEntry ni _isFavorite para evitar flicker (vienen de initState)
      });
    }

    await Future.wait([
      _loadReviews(),
      _loadListEntry(),
      _loadFavoriteStatus(),
    ]);
  }

  Future<void> _loadFavoriteStatus() async {
    final fav = await _animeRepo.isFavorite(widget.anime.malId);
    if (mounted && fav != _isFavorite) {
      setState(() {
        _isFavorite = fav;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    HapticFeedback.lightImpact();
    // Optimistic UI update
    setState(() {
      _isFavorite = !_isFavorite;
    });

    try {
      await _animeRepo.toggleFavorite(widget.anime.malId);
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          _isFavorite = !_isFavorite;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al modificar favoritos: $e')),
        );
      }
    }
  }

  Future<void> _loadListEntry() async {
    final entry = await _animeRepo.getUserListEntry(widget.anime.malId);
    if (mounted) {
      // Solo actualizar si el estado es diferente al que ya tenemos precargado
      final currentStatus = _listEntry?['status'];
      final newStatus = entry?['status'];
      if (newStatus != currentStatus) {
        setState(() {
          _listEntry = entry;
        });
      } else if (entry != null && _listEntry == null) {
         setState(() {
          _listEntry = entry;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;
    final currentStatus = _listEntry?['status'];
    
    final screenHeight = MediaQuery.of(context).size.height;
    final headerHeight = (screenHeight * 0.5).clamp(320.0, 500.0);

    final theme = Theme.of(context);
    final appBarTextColor = theme.brightness == Brightness.dark ? AppTheme.primary : AppTheme.primaryDark;
    final appBarBgColor = theme.brightness == Brightness.dark ? Colors.black.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.7);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: appBarBgColor,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: appBarTextColor),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                anime.title,
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: appBarTextColor,
                  letterSpacing: -1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              height: headerHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WebSafeImage(
                    key: ValueKey("detail_header_${anime.malId}"),
                    url: anime.imageUrl,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).scaffoldBackgroundColor,
                          Theme.of(context).scaffoldBackgroundColor.withOpacity(0.4),
                          Colors.transparent
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                            ...anime.genres.map((g) {
                              final textCol = Theme.of(context).brightness == Brightness.dark ? AppTheme.primary : AppTheme.primaryDark;
                              return Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: textCol.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                                child: Text(g, style: TextStyle(color: textCol, fontSize: 10, fontWeight: FontWeight.bold)),
                              );
                            }).toList(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF26FEDC) : const Color(0xFF008080)).withOpacity(0.15), 
                                borderRadius: BorderRadius.circular(16)
                              ),
                              child: Text(
                                anime.status, 
                                style: TextStyle(
                                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF26FEDC) : const Color(0xFF008080), 
                                  fontSize: 10, 
                                  fontWeight: FontWeight.bold
                                )
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (Theme.of(context).brightness == Brightness.dark ? Colors.orangeAccent : Colors.deepOrange).withOpacity(0.15), 
                                borderRadius: BorderRadius.circular(16)
                              ),
                              child: Text(
                                anime.demographic, 
                                style: TextStyle(
                                  color: Theme.of(context).brightness == Brightness.dark ? Colors.orangeAccent : Colors.deepOrange, 
                                  fontSize: 10, 
                                  fontWeight: FontWeight.bold
                                )
                              ),
                            ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                          child: Text("${anime.episodes} Episodios • ${anime.year}", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          anime.title, 
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans', 
                            fontSize: MediaQuery.of(context).size.width < 400 ? 24 : 32, 
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          )
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const Icon(Icons.star, color: AppTheme.secondary, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                anime.score.toString(), 
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  "VALORACIÓN PÚBLICA", 
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 8, fontWeight: FontWeight.bold)
                                ),
                              ),
                              const SizedBox(width: 12),
                              Opacity(
                                opacity: _averageScore != null ? 1.0 : 0.5,
                                child: Row(
                                  children: [
                                    Icon(Icons.star, color: _averageScore != null ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.primary : AppTheme.primaryDark) : Colors.grey, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      _averageScore?.toStringAsFixed(1) ?? "?.?", 
                                      style: TextStyle(
                                        color: _averageScore != null 
                                            ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.primary : AppTheme.primaryDark) 
                                            : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                                        fontWeight: FontWeight.bold, 
                                        fontSize: 16
                                      )
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _averageScore != null 
                                            ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.primary : AppTheme.primaryDark).withOpacity(0.15) 
                                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.02), 
                                        borderRadius: BorderRadius.circular(4)
                                      ),
                                      child: Text(
                                        "VALORACIÓN DE LOS USUARIOS", 
                                        style: TextStyle(
                                          color: _averageScore != null 
                                              ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.primary : AppTheme.primaryDark) 
                                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.2), 
                                          fontSize: 8, 
                                          fontWeight: FontWeight.bold
                                        )
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: currentStatus != null ? AppTheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                            foregroundColor: currentStatus != null ? Colors.black : Theme.of(context).colorScheme.onSurface,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () => _showListStatusModal(context),
                          icon: Icon(currentStatus != null ? Icons.check_circle : Icons.add_circle_outline),
                          label: Text(currentStatus ?? 'Añadir', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _toggleFavorite,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: _isFavorite ? Colors.red.withOpacity(0.1) : Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _isFavorite ? Colors.red.withOpacity(0.5) : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              _isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: _isFavorite ? Colors.red : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _myRating != null ? Theme.of(context).colorScheme.onSurface.withOpacity(0.05) : AppTheme.primary,
                            foregroundColor: _myRating != null ? AppTheme.primary : Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            side: _myRating != null ? const BorderSide(color: AppTheme.primary) : BorderSide.none,
                          ),
                          onPressed: () => _showRatingModal(context),
                          icon: Icon(_myRating != null ? Icons.star : Icons.star_rate_rounded),
                          label: Text(_myRating != null ? '${_myRating!.toStringAsFixed(1)}' : 'Valorar', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.1)),
                      boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.05), blurRadius: 20)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Sinopsis", 
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans', 
                            fontSize: 20, 
                            fontWeight: FontWeight.bold, 
                            color: Theme.of(context).brightness == Brightness.dark ? AppTheme.primary : AppTheme.primaryDark
                          )
                        ),
                        const SizedBox(height: 12),
                        Text(
                          anime.synopsis,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text("Opiniones de la comunidad", style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Column(
                    children: _reviews.map((review) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () => _showFullReview(context, review),
                          child: _buildFriendOpinionCard(review),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _reviews = [];
  double? _myRating;
  double? _averageScore;


  Future<void> _loadReviews() async {
    final reviews = await _animeRepo.fetchReviewsWithProfiles(widget.anime.malId);
    final avg = await _animeRepo.getAverageRating(widget.anime.malId);
    
    reviews.sort((a, b) {
      if (a['isMe'] == true || a['isFriend'] == true) return -1;
      if (b['isMe'] == true || b['isFriend'] == true) return 1;
      return 0;
    });

    if (mounted) {
      setState(() {
        _reviews = reviews;
        _averageScore = avg > 0 ? avg : null;
        try {
          final myReview = reviews.firstWhere((r) => r['isMe'] == true);
          final double newRating = (myReview['rating'] as num).toDouble();
          if (newRating != _myRating) {
            _myRating = newRating;
          }
        } catch (e) {
          // Si no hay reseña propia (se ha borrado), resetear la nota local
          if (_myRating != null) {
            _myRating = null;
          }
        }
      });
    }
  }

  void _showListStatusModal(BuildContext context) {
    String? selectedStatus = _listEntry?['status'] ?? 'Pendiente';
    int episodes = _listEntry?['episodes_watched'] ?? 0;
    int restoredEpisodes = episodes; // Keep track of progress before 'Visto' auto-fill
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24, 
            top: 24, left: 24, right: 24
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mi Lista', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                children: ['Pendiente', 'Viendo', 'Visto'].map((status) {
                  bool isSel = selectedStatus == status;
                  return ChoiceChip(
                    label: Text(status),
                    selected: isSel,
                    onSelected: (val) {
                      setModalState(() {
                        if (status == 'Visto' && selectedStatus != 'Visto') {
                          // Save current progress before auto-filling max
                          restoredEpisodes = episodes;
                          episodes = widget.anime.episodes;
                        } else if (status != 'Visto' && selectedStatus == 'Visto') {
                          // Restore previous progress when moving away from 'Visto'
                          episodes = restoredEpisodes;
                        }
                        selectedStatus = status;
                      });
                    },
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(color: isSel ? Colors.black : Theme.of(context).colorScheme.onSurface),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              if (selectedStatus != null) ...[
                const Text('Episodios vistos', style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    _buildRapidCounterButton(
                      icon: Icons.remove_circle_outline,
                      onPressed: () async {
                        if (episodes > 0) {
                          if (selectedStatus == 'Visto' && _myRating != null) {
                            // La nota ya no se borra automáticamente
                          }
                          setModalState(() {
                            episodes--;
                            if (episodes == 0) selectedStatus = 'Pendiente';
                            else if (episodes < widget.anime.episodes) selectedStatus = 'Viendo';
                            if (selectedStatus != 'Visto') restoredEpisodes = episodes;
                          });
                        }
                      },
                      onLongPress: () async {
                        if (selectedStatus == 'Visto' && _myRating != null) {
                          // La nota ya no se borra automáticamente
                        }
                        _startRapidCounter(
                          decrement: true,
                          maxEpisodes: widget.anime.episodes,
                          currentEpisodes: () => episodes,
                          onUpdate: (newVal, newStatus) {
                            setModalState(() {
                              episodes = newVal;
                              selectedStatus = newStatus;
                              if (selectedStatus != 'Visto') restoredEpisodes = episodes;
                            });
                          },
                        );
                      },
                      onLongPressEnd: _stopRapidCounter,
                    ),
                    const SizedBox(width: 8),
                    Text('$episodes / ${widget.anime.episodes}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    _buildRapidCounterButton(
                      icon: Icons.add_circle_outline,
                      onPressed: () {
                        if (widget.anime.episodes > 0 && episodes < widget.anime.episodes) {
                          setModalState(() {
                            episodes++;
                            if (episodes == widget.anime.episodes) {
                              selectedStatus = 'Visto';
                            } else {
                              selectedStatus = 'Viendo';
                            }
                            if (selectedStatus != 'Visto') restoredEpisodes = episodes;
                          });
                        }
                      },
                      onLongPress: () {
                        _startRapidCounter(
                          decrement: false,
                          maxEpisodes: widget.anime.episodes,
                          currentEpisodes: () => episodes,
                          onUpdate: (newVal, newStatus) {
                            setModalState(() {
                              episodes = newVal;
                              selectedStatus = newStatus;
                              if (selectedStatus != 'Visto') restoredEpisodes = episodes;
                            });
                          },
                        );
                      },
                      onLongPressEnd: _stopRapidCounter,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  if (_listEntry != null)
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: Theme.of(context).colorScheme.surface,
                              title: const Text('¿Quitar de tu lista?'),
                              content: Text('Esto eliminará también tu valoración y reseña para "${widget.anime.title}". Esta acción no se puede deshacer.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text('Cancelar', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await _animeRepo.removeFromUserList(widget.anime.malId);
                            if (mounted) {
                              Navigator.pop(context);
                              _loadListEntry();
                            }
                          }
                        },
                        child: const Text('Quitar de la lista'),
                      ),
                    ),
                  if (_listEntry != null) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isSaving ? null : () async {
                        HapticFeedback.mediumImpact();
                        setModalState(() => isSaving = true);
                        try {
                          await _animeRepo.updateUserListStatus(widget.anime.malId, selectedStatus!, episodes: episodes);
                          

                          if (mounted) {
                            Navigator.pop(context);
                            _loadListEntry();
                            _loadReviews(); // Recargar para limpiar el estado de la estrella
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('¡Lista actualizada!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                backgroundColor: AppTheme.primary,
                                duration: Duration(seconds: 2),
                              )
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            setModalState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
                            );
                          }
                        }
                      },
                      child: isSaving 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('Guardar cambios', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullReview(BuildContext context, Map<String, dynamic> review) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context); // Cerrar modal primero
                    if (review['isMe'] == true) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                    } else {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: {
                        'id': review['id'],
                        'full_name': review['full_name'],
                        'username': review['username'],
                        'avatar_url': review['imageUrl'],
                      })));
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: WebSafeImage(url: review['imageUrl'] ?? ''),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          if (review['isMe'] == true) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                          } else {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: {
                              'id': review['id'],
                              'full_name': review['full_name'],
                              'username': review['username'],
                              'avatar_url': review['imageUrl'],
                            })));
                          }
                        },
                        child: Text(review['name'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                      ),
                      if (review['isFriend']) 
                        Row(
                          children: [
                            const Icon(Icons.people, color: AppTheme.primary, size: 14),
                            const SizedBox(width: 4),
                            const Text('Amigo', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.secondary, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Colors.black, size: 16),
                      const SizedBox(width: 4),
                      Text(review['rating'].toString(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('OPINIÓN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5))),
            const SizedBox(height: 12),
            Text(
              (review['opinion']?.toString().isEmpty ?? true) ? 'Sin comentarios.' : review['opinion'],
              style: TextStyle(fontSize: 16, height: 1.5, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showRatingModal(BuildContext context) {
    double currentRating = _myRating ?? 5.0; 
    String existingOpinion = "";
    try {
      final myReview = _reviews.firstWhere((r) => r['isMe'] == true);
      existingOpinion = myReview['opinion'] ?? "";
    } catch (_) {}
    TextEditingController opinionController = TextEditingController(text: existingOpinion);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24, top: 24, left: 24, right: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_myRating != null ? 'Editar Valoración' : 'Puntuar Anime', style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: AppTheme.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: AppTheme.primary,
                      overlayColor: AppTheme.primary.withOpacity(0.2),
                      valueIndicatorColor: AppTheme.primary,
                      valueIndicatorTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    child: Slider(
                      value: currentRating,
                      min: 0, max: 10, divisions: 100, 
                      label: currentRating % 1 == 0 ? currentRating.toInt().toString() : currentRating.toStringAsFixed(1),
                      onChanged: (value) => setModalState(() => currentRating = value),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${currentRating % 1 == 0 ? currentRating.toInt() : currentRating.toStringAsFixed(1)} / 10', 
                      style: const TextStyle(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)
                    )
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: opinionController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Escribe tu opinión aquí...',
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (_myRating != null)
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            onPressed: () async {
                              await _animeRepo.removeReview(widget.anime.malId);
                              if (mounted) {
                                Navigator.pop(context);
                                _loadReviews();
                              }
                            },
                            child: const Text('Quitar nota'),
                          ),
                        ),
                      if (_myRating != null) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () async {
                            await _animeRepo.addReview(widget.anime.malId, currentRating, opinionController.text.isNotEmpty ? opinionController.text : "Sin comentarios.");
                            if (mounted) {
                              Navigator.pop(context);
                              _loadReviews(); 
                            }
                          },
                          child: Text(_myRating != null ? 'Guardar' : 'Publicar', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFriendOpinionCard(Map<String, dynamic> review) {
    final name = review['name'];
    final opinion = review['opinion'] ?? "";
    final rating = review['rating'].toString();
    final imageUrl = review['imageUrl'] ?? "";
    final isFriend = review['isFriend'] ?? false;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              if (review['isMe'] == true) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: {
                  'id': review['id'],
                  'full_name': review['full_name'],
                  'username': review['username'],
                  'avatar_url': review['imageUrl'],
                })));
              }
            },
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                     width: 40,
                     height: 40,
                     child: WebSafeImage(
                       url: imageUrl.isNotEmpty ? imageUrl : "https://www.gravatar.com/avatar/0?d=mp&f=y", 
                       fit: BoxFit.cover,
                     ),
                  ),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.secondary, borderRadius: BorderRadius.circular(8)),
                    child: Text(rating, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (review['isMe'] == true) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                        } else {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: {
                            'id': review['id'],
                            'full_name': review['full_name'],
                            'username': review['username'],
                            'avatar_url': review['imageUrl'],
                          })));
                        }
                      },
                      child: Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                    ),
                    if (isFriend) ...[ const SizedBox(width: 6), const Icon(Icons.people, color: AppTheme.primary, size: 14) ]
                  ]
                ),
                const SizedBox(height: 4),
                Text(
                  opinion.isEmpty ? '"Sin comentarios."' : '"$opinion"', 
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontStyle: FontStyle.italic), 
                  maxLines: 2, 
                  overflow: TextOverflow.ellipsis
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.24)),
        ],
      ),
    );
  }

  Timer? _fastUpdateTimer;
  int _fastUpdateCount = 0;

  void _startRapidCounter({
    required bool decrement,
    required int maxEpisodes,
    required int Function() currentEpisodes,
    required Function(int, String) onUpdate,
  }) {
    _stopRapidCounter();
    _fastUpdateCount = 0;
    
    _fastUpdateTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      int current = currentEpisodes();
      if (decrement) {
        if (current <= 0) {
          _stopRapidCounter();
          return;
        }
        current--;
      } else {
        if (current >= maxEpisodes) {
          _stopRapidCounter();
          return;
        }
        current++;
      }

      String newStatus = 'Viendo';
      if (current == 0) newStatus = 'Pendiente';
      else if (current == maxEpisodes && maxEpisodes > 0) newStatus = 'Visto';

      onUpdate(current, newStatus);
      _fastUpdateCount++;

      if (_fastUpdateCount == 10) {
        _restartTimer(timer, 80, decrement, maxEpisodes, currentEpisodes, onUpdate);
      } else if (_fastUpdateCount == 30) {
        _restartTimer(timer, 40, decrement, maxEpisodes, currentEpisodes, onUpdate);
      }
    });
  }

  void _restartTimer(Timer oldTimer, int ms, bool decrement, int maxEpisodes, int Function() currentEpisodes, Function(int, String) onUpdate) {
    oldTimer.cancel();
    _fastUpdateTimer = Timer.periodic(Duration(milliseconds: ms), (timer) {
      int current = currentEpisodes();
      if (decrement) {
        if (current <= 0) {
          _stopRapidCounter();
          return;
        }
        current--;
      } else {
        if (current >= maxEpisodes) {
          _stopRapidCounter();
          return;
        }
        current++;
      }

      String newStatus = 'Viendo';
      if (current == 0) newStatus = 'Pendiente';
      else if (current == maxEpisodes && maxEpisodes > 0) newStatus = 'Visto';

      onUpdate(current, newStatus);
      _fastUpdateCount++;
    });
  }

  void _stopRapidCounter() {
    _fastUpdateTimer?.cancel();
    _fastUpdateTimer = null;
  }

  Widget _buildRapidCounterButton({
    required IconData icon,
    required VoidCallback onPressed,
    required VoidCallback onLongPress,
    required VoidCallback onLongPressEnd,
  }) {
    return GestureDetector(
      onTap: onPressed,
      onLongPress: onLongPress,
      onLongPressUp: onLongPressEnd,
      onLongPressEnd: (_) => onLongPressEnd(),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.primary, size: 24),
      ),
    );
  }
}
