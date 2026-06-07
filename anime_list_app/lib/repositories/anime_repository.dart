import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/anime.dart';

class AnimeRepository {
  static final AnimeRepository _instance = AnimeRepository._internal();
  factory AnimeRepository() => _instance;
  AnimeRepository._internal();

  static Future<void> init() async {
    await _instance._loadProfileFromDisk();
    await _instance._loadPendingActions();
  }

  final _supabase = Supabase.instance.client;
  SupabaseClient get supabase => _supabase;
  User? get currentUser => _supabase.auth.currentUser;
  
  // Memoria rápida para el perfil
  Map<String, dynamic>? _cachedProfile;
  Map<String, dynamic>? get cachedProfile => _cachedProfile;

  Future<void> _saveProfileToDisk() async {
    if (_cachedProfile == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_profile_cache', jsonEncode(_cachedProfile));
    } catch (e) {
      print('Error guardando perfil en disco: $e');
    }
  }

  Future<void> _loadProfileFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString('user_profile_cache');
      if (data != null) {
        _cachedProfile = jsonDecode(data);
        notifyProfileChanged();
      }
    } catch (e) {
      print('Error cargando perfil desde disco: $e');
    }
  }

  // --- PERSISTENCIA ADICIONAL (FASE 3) ---

  Future<void> _saveToDisk(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      print('Error guardando $key en disco: $e');
    }
  }

  Future<dynamic> _loadFromDisk(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(key);
      if (data != null) return jsonDecode(data);
    } catch (e) {
      print('Error cargando $key de disco: $e');
    }
    return null;
  }
  final ValueNotifier<int> profileUpdateNotifier = ValueNotifier<int>(0);

  // Cache estática para persistencia durante la sesión
  static Map<String, int>? _staticUserStats;
  // --- GESTIÓN DE ESTADO GLOBAL (TIPO EVENT BUS) ---
  static final _updateController = StreamController<int>.broadcast();
  static Stream<int> get onAnimeUpdated => _updateController.stream;

  static final _friendsUpdateController = StreamController<void>.broadcast();
  static Stream<void> get onFriendsUpdated => _friendsUpdateController.stream;

  void notifyAnimeUpdate(int malId) {
    _updateController.add(malId);
  }

  void notifyFriendsUpdate() {
    _friendsUpdateController.add(null);
  }

  static List<Anime>? _staticFavorites;
  static List<Anime>? _staticRecentActivity;
  static final Map<int, double> _userRatingCache = {};

  static double? getAverageRatingFromCache(int animeId) {
    return _userRatingCache[animeId];
  }

  void notifyProfileChanged() {
    profileUpdateNotifier.value++;
  }

  void clearCache() async {
    _cachedProfile = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_profile_cache');
    } catch (e) {}
    notifyProfileChanged();
  }

  // --- ESTADO DE CONEXIÓN (FASE 3 REFINADA) ---
  final ValueNotifier<bool> connectionStatus = ValueNotifier<bool>(true);

  void _updateConnection(bool online) {
    if (connectionStatus.value != online) {
      connectionStatus.value = online;
      // Si recuperamos conexión, intentamos sincronizar
      if (online) {
        _syncPendingActions();
      }
    }
  }

  // Comprueba si hay conexión de forma activa (Fase 3 Refinada)
  Future<bool> checkConnection() async {
    try {
      // Intentamos una petición ultra-ligera (ping a Supabase)
      await _supabase.from('animes').select('mal_id').limit(1);
      _updateConnection(true);
      return true;
    } catch (_) {
      _updateConnection(false);
      return false;
    }
  }

  Future<Map<String, dynamic>> fetchAnimes({
    String statusFilter = 'Todos', 
    String demographicFilter = 'Todos',
    String genreFilter = 'Todos',
    String themeFilter = 'Todos',
    String orderFilter = 'Puntuación',
    String eraFilter = 'Todos',
    String scoreFilter = 'Todos',
    bool hideMyList = false,
    String search = '',
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      var filterQuery = _supabase.from('animes').select('*, user_anime_list(status, user_id), reviews(rating, user_id), favorites(user_id)');
      
      final int start = page * pageSize;
      final int end = start + pageSize - 1;
      
      if (search.isNotEmpty) {
        filterQuery = filterQuery.or('title.ilike.%$search%,title_romaji.ilike.%$search%');
      }

      if (statusFilter != 'Todos') {
        filterQuery = filterQuery.eq('status', statusFilter);
      }
      
      if (demographicFilter != 'Todos') {
        filterQuery = filterQuery.eq('demographic', demographicFilter);
      }
      
      if (genreFilter != 'Todos') {
        filterQuery = filterQuery.contains('genres', [genreFilter]);
      }

      if (themeFilter != 'Todos') {
        filterQuery = filterQuery.contains('genres', [themeFilter]);
      }

      // Nuevos Filtros: Época
      if (eraFilter == 'Moderno') {
        filterQuery = filterQuery.gte('release_year', 2020);
      } else if (eraFilter == 'Clásico') {
        filterQuery = filterQuery.gte('release_year', 2010).lte('release_year', 2019);
      } else if (eraFilter == 'Retro') {
        filterQuery = filterQuery.lt('release_year', 2010);
      }

      // Nuevos Filtros: Puntuación
      if (scoreFilter == 'Joyas') {
        filterQuery = filterQuery.gte('score', 8.5);
      } else if (scoreFilter == 'Recomendados') {
        filterQuery = filterQuery.gte('score', 7.5);
      }

      // Filtrado SERVER-SIDE: Obtener IDs de animes ya en la lista del usuario
      // y excluirlos ANTES de paginar para que las páginas sean siempre completas.
      if (hideMyList && user != null) {
        final userListData = await _supabase
            .from('user_anime_list')
            .select('anime_id')
            .eq('user_id', user.id);
        final userAnimeIds = (userListData as List).map((e) => e['anime_id'] as int).toList();
        if (userAnimeIds.isNotEmpty) {
          filterQuery = filterQuery.not('mal_id', 'in', userAnimeIds);
        }
      }

      PostgrestTransformBuilder transformQuery;
      if (orderFilter == 'Puntuación') {
        transformQuery = filterQuery.order('score', ascending: false).order('mal_id', ascending: true);
      } else if (orderFilter == 'Año') {
        transformQuery = filterQuery.order('release_year', ascending: false).order('mal_id', ascending: true);
      } else if (orderFilter == 'Episodios') {
        transformQuery = filterQuery.order('episodes', ascending: false).order('mal_id', ascending: true);
      } else if (orderFilter == 'Nombre') {
        transformQuery = filterQuery.order('title', ascending: true).order('mal_id', ascending: true);
      } else {
        transformQuery = filterQuery.order('score', ascending: false).order('mal_id', ascending: true);
      }

      final response = await transformQuery.range(start, end).count(CountOption.exact);
      final data = response.data as List<dynamic>;
      final totalCount = response.count;
      
      final List<Anime> animeList = _mapAnimeDataList(data);

      // Deduplicación por mal_id para evitar conflictos de Hero tags en la UI
      final seenIds = <int>{};
      var uniqueList = animeList.where((a) => seenIds.add(a.malId)).toList();

      if (search.isNotEmpty) {
        final query = search.trim().toLowerCase();
        final Map<int, int> originalIndices = {
          for (int i = 0; i < uniqueList.length; i++) uniqueList[i].malId: i
        };
        uniqueList.sort((a, b) {
          final scoreTitleA = _calculateSearchRelevance(a.title, query);
          final scoreRomajiA = a.titleRomaji != null ? _calculateSearchRelevance(a.titleRomaji!, query) : 0;
          final scoreA = scoreTitleA > scoreRomajiA ? scoreTitleA : scoreRomajiA;

          final scoreTitleB = _calculateSearchRelevance(b.title, query);
          final scoreRomajiB = b.titleRomaji != null ? _calculateSearchRelevance(b.titleRomaji!, query) : 0;
          final scoreB = scoreTitleB > scoreRomajiB ? scoreTitleB : scoreRomajiB;

          if (scoreA != scoreB) {
            return scoreB.compareTo(scoreA); // Descendente
          }
          return originalIndices[a.malId]!.compareTo(originalIndices[b.malId]!);
        });
      }

      final resultData = {
        'list': uniqueList,
        'total': totalCount
      };

      // Caché para la primera página (Fase 3 Refinada)
      if (page == 0 && search.isEmpty && statusFilter == 'Todos' && demographicFilter == 'Todos' && genreFilter == 'Todos') {
        _saveToDisk('home_animes_cache', {
          'list': uniqueList.map((a) => a.toMap()).toList(),
          'total': totalCount,
        });
      }

      _updateConnection(true);
      return resultData;
    } catch (e) {
      print('Error en fetchAnimes: $e');
      
      // Antes de rendirnos y dar caché, re-probamos la conexión si es un refresh manual (page 0)
      if (page == 0) {
        await checkConnection();
      }

      // Intentar devolver caché para la página 0 si estamos offline
      if (page == 0 && search.isEmpty) {
        final cached = await _loadFromDisk('home_animes_cache');
        if (cached != null) {
          final List<dynamic> listData = cached['list'] ?? [];
          return {
            'list': listData.map<Anime>((e) => Anime.fromMap(e)).toList(),
            'total': cached['total'] ?? 0,
          };
        }
      }
      
      return {'list': <Anime>[], 'total': 0};
    }
  }

  int _calculateSearchRelevance(String title, String query) {
    final cleanTitle = title.trim().toLowerCase();
    final cleanQuery = query.trim().toLowerCase();
    
    if (cleanTitle == cleanQuery) {
      return 100;
    }
    
    if (cleanTitle.startsWith(cleanQuery)) {
      return 80;
    }
    
    // Contiene la query como palabra completa
    final wordRegExp = RegExp(r'\b' + RegExp.escape(cleanQuery) + r'\b');
    if (wordRegExp.hasMatch(cleanTitle)) {
      return 60;
    }
    
    // Empieza una palabra en el título con la query
    final wordStartRegExp = RegExp(r'\b' + RegExp.escape(cleanQuery));
    if (wordStartRegExp.hasMatch(cleanTitle)) {
      return 40;
    }
    
    if (cleanTitle.contains(cleanQuery)) {
      return 20;
    }
    
    return 0;
  }

  // Método centralizado para mapear animes con sus relaciones de usuario
  List<Anime> _mapAnimeDataList(List<dynamic> data) {
    final user = _supabase.auth.currentUser;
    
    return data.map<Anime>((animeData) {
      final dynamicRawList = animeData['user_anime_list'];
      final dynamicReviewsList = animeData['reviews'];
      final dynamicFavsList = animeData['favorites'];
      
      String? myStatus;
      double? myRating;
      bool isFavorite = false;
      
      if (user != null) {
        // Búsqueda de mi estado (myStatus)
        if (dynamicRawList is List && dynamicRawList.isNotEmpty) {
          for (final item in dynamicRawList) {
            if (item['user_id'].toString() == user.id.toString()) {
              myStatus = item['status'];
              break;
            }
          }
        }

        // Búsqueda de mi nota (myRating)
        if (dynamicReviewsList is List && dynamicReviewsList.isNotEmpty) {
          for (final item in dynamicReviewsList) {
            if (item['user_id'].toString() == user.id.toString()) {
              myRating = (item['rating'] as num?)?.toDouble();
              break;
            }
          }
        }

        // Búsqueda de mi favorito (isFavorite)
        if (dynamicFavsList is List && dynamicFavsList.isNotEmpty) {
          for (final item in dynamicFavsList) {
            if (item['user_id'].toString() == user.id.toString()) {
              isFavorite = true;
              break;
            }
          }
        }
      }

      final anime = Anime.fromMap(animeData);
      return anime.copyWith(
        myStatus: myStatus,
        myRating: myRating,
        isFavorite: isFavorite,
      );
    }).toList();
  }
  Future<List<Anime>> searchAnime(String query) async {
    try {
      final data = await _supabase
          .from('animes')
          .select('*, user_anime_list(status, user_id), reviews(rating, user_id), favorites(user_id)')
          .or('title.ilike.%$query%,title_romaji.ilike.%$query%')
          .order('score', ascending: false);
      
      final animeList = _mapAnimeDataList(data);
      
      // Unicidad por mal_id
      final seenIds = <int>{};
      final uniqueList = animeList.where((a) => seenIds.add(a.malId)).toList();

      if (query.isNotEmpty) {
        final cleanQuery = query.trim().toLowerCase();
        final Map<int, int> originalIndices = {
          for (int i = 0; i < uniqueList.length; i++) uniqueList[i].malId: i
        };
        uniqueList.sort((a, b) {
          final scoreTitleA = _calculateSearchRelevance(a.title, cleanQuery);
          final scoreRomajiA = a.titleRomaji != null ? _calculateSearchRelevance(a.titleRomaji!, cleanQuery) : 0;
          final scoreA = scoreTitleA > scoreRomajiA ? scoreTitleA : scoreRomajiA;

          final scoreTitleB = _calculateSearchRelevance(b.title, cleanQuery);
          final scoreRomajiB = b.titleRomaji != null ? _calculateSearchRelevance(b.titleRomaji!, cleanQuery) : 0;
          final scoreB = scoreTitleB > scoreRomajiB ? scoreTitleB : scoreRomajiB;

          if (scoreA != scoreB) {
            return scoreB.compareTo(scoreA); // Descendente por relevancia
          }
          return originalIndices[a.malId]!.compareTo(originalIndices[b.malId]!);
        });
      }

      return uniqueList;
    } catch (e) {
      print('Error en searchAnime: $e');
      throw Exception('Error al buscar anime: $e');
    }
  }

  // Obtiene un solo anime con todas sus relaciones actuales
  Future<Anime?> fetchAnimeById(int malId) async {
    try {
      final data = await _supabase
          .from('animes')
          .select('*, user_anime_list(status, user_id), reviews(rating, user_id), favorites(user_id)')
          .eq('mal_id', malId)
          .single();
      
      final results = _mapAnimeDataList([data]);
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      print('Error en fetchAnimeById: $e');
      return null;
    }
  }

  Future<void> toggleFavorite(int animeId, {bool forceOnline = false}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('El usuario no está autenticado');
      }

      // Comprobar si ya es favorito
      final favorites = await _supabase
          .from('favorites')
          .select()
          .eq('user_id', user.id)
          .eq('anime_id', animeId);

      if (favorites.isNotEmpty) {
        // Si existe, lo borramos (toggle)
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('anime_id', animeId);
        print('Eliminado de favoritos');
      } else {
        // Si no existe, lo insertamos
        await _supabase.from('favorites').insert({
          'user_id': user.id,
          'anime_id': animeId,
          'created_at': DateTime.now().toIso8601String(),
        });
        print('Añadido a favoritos');
      }
      
      notifyAnimeUpdate(animeId);
    } catch (e) {
      print('Error en toggleFavorite: $e');
      if (!forceOnline) {
        // Encolar acción para sincronización posterior
        await _addPendingAction('TOGGLE_FAVORITE', {
          'anime_id': animeId,
        });
        // Feedback virtual de éxito
        notifyAnimeUpdate(animeId);
        return;
      }
      throw Exception('No se pudo modificar el favorito: $e');
    }
  }

  Future<bool> isFavorite(int animeId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final favorites = await _supabase
          .from('favorites')
          .select()
          .eq('user_id', user.id)
          .eq('anime_id', animeId);

      return favorites.isNotEmpty;
    } catch (e) {
      print('Error en isFavorite: $e');
      return false;
    }
  }

  Future<void> addReview(int animeId, double rating, String opinion, {bool forceOnline = false}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('El usuario no está autenticado');
      }

      await _supabase.from('reviews').upsert({
        'anime_id': animeId,
        'user_id': user.id,
        'rating': rating,
        'opinion': opinion,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'anime_id,user_id');
      
      _userRatingCache.remove(animeId);
      notifyAnimeUpdate(animeId);
    } catch (e) {
      print('Error en addReview: $e');
      if (!forceOnline) {
        await _addPendingAction('ADD_REVIEW', {
          'anime_id': animeId,
          'rating': rating,
          'opinion': opinion,
        });
        notifyAnimeUpdate(animeId);
        return;
      }
      throw Exception('Error al publicar valoración: $e');
    }
  }

  Future<void> removeReview(int animeId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('reviews')
          .delete()
          .eq('anime_id', animeId)
          .eq('user_id', user.id);
          
      _userRatingCache.remove(animeId);
      notifyAnimeUpdate(animeId);
    } catch (e) {
      print('Error en removeReview: $e');
      throw Exception('Error al eliminar valoración: $e');
    }
  }

  Future<double> getAverageRating(int animeId) async {
    try {
      if (_userRatingCache.containsKey(animeId)) {
        return _userRatingCache[animeId]!;
      }

      final data = await _supabase
          .from('reviews')
          .select('rating')
          .eq('anime_id', animeId);

      if ((data as List).isEmpty) return 0.0;

      final ratings = (data as List).map((e) => (e['rating'] as num).toDouble()).toList();
      final avg = ratings.reduce((a, b) => a + b) / ratings.length;
      
      _userRatingCache[animeId] = avg;
      return avg;
    } catch (e) {
      print('Error en getAverageRating: $e');
      return 0.0;
    }
  }

  Future<List<Map<String, dynamic>>> fetchReviewsWithProfiles(int animeId) async {
    try {
      final reviews = await _supabase
          .from('reviews')
          .select()
          .eq('anime_id', animeId)
          .order('created_at', ascending: false);

      final userIds = reviews.map((r) => r['user_id']).toSet().toList();

      List<dynamic> profiles = [];
      if (userIds.isNotEmpty) {
        profiles = await _supabase
            .from('profiles')
            .select()
            .filter('id', 'in', userIds);
      }

      final profileMap = {for (var p in profiles) p['id']: p};

      final currentUser = _supabase.auth.currentUser;

      // Obtener lista de amigos para marcar 'isFriend'
      List<String> friendIds = [];
      if (currentUser != null) {
        final friendships = await _supabase
            .from('friendships')
            .select('friend_id')
            .eq('user_id', currentUser.id);
        friendIds = (friendships as List).map((f) => f['friend_id'] as String).toList();
      }

      return reviews.map((review) {
        final profile = profileMap[review['user_id']];
        bool isMe = currentUser != null && review['user_id'] == currentUser.id;
        bool isFriend = friendIds.contains(review['user_id']);
        
        // Prioridad: Full Name > Username > 'Usuario'
        String fullName = (profile?['full_name'] as String? ?? '').trim();
        String username = (profile?['username'] as String? ?? '').trim();
        String displayName = fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : 'Usuario');

        return {
          'id': review['user_id'],
          'name': isMe ? 'Tú' : displayName,
          'full_name': fullName,
          'username': username,
          'opinion': review['opinion'],
          'rating': review['rating'],
          'imageUrl': profile?['avatar_url'] ?? '',
          'isFriend': isFriend,
          'isMe': isMe,
          'created_at': review['created_at'],
        };
      }).toList();
    } catch (e) {
      print('Error en fetchReviewsWithProfiles: $e');
      return [];
    }
  }

  Future<List<Anime>> fetchUserList(String status) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from('user_anime_list')
          .select('*, animes(*, reviews(rating))')
          .eq('user_id', user.id)
          .eq('status', status)
          .order('updated_at', ascending: false);

      final animeList = (data as List)
          .where((item) => item['animes'] != null)
          .map<Anime>((item) {
            final animeData = item['animes'];
            final userRatingData = animeData['reviews'] as List?;
            
            final anime = Anime.fromMap(animeData);
            return anime.copyWith(
              myStatus: item['status'],
              myRating: (userRatingData != null && userRatingData.isNotEmpty) 
                  ? (userRatingData[0]['rating'] as num).toDouble() 
                  : null,
            );
          })
          .toList();
      
      // Asegurar unicidad total por mal_id para evitar conflictos de Hero tags
      final seenIds = <int>{};
      return animeList.where((a) => seenIds.add(a.malId)).toList();
    } catch (e) {
      print('Error en fetchUserList: $e');
      return [];
    }
  }

  Future<void> updateUserListStatus(int animeId, String status, {int episodes = 0, bool forceOnline = false}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      await _supabase.from('user_anime_list').upsert({
        'user_id': user.id,
        'anime_id': animeId,
        'status': status,
        'episodes_watched': episodes,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, anime_id');

      notifyAnimeUpdate(animeId);
    } catch (e) {
      print('Error en updateUserListStatus: $e');
      if (!forceOnline) {
        // Encolar para sincronización
        await _addPendingAction('UPDATE_STATUS', {
          'anime_id': animeId,
          'status': status,
          'episodes': episodes,
        });
        notifyAnimeUpdate(animeId);
        return;
      }
      throw Exception('Error al actualizar la lista: $e');
    }
  }

  Future<void> removeFromUserList(int animeId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      
      await _supabase
          .from('user_anime_list')
          .delete()
          .eq('user_id', user.id)
          .eq('anime_id', animeId);

      // --- CAMBIO: Borrado en Cascada (Borrar reseña al quitar de la lista) ---
      await _supabase.from('reviews').delete()
          .eq('user_id', user.id)
          .eq('anime_id', animeId);

      notifyAnimeUpdate(animeId);
    } catch (e) {
      print('Error en removeFromUserList: $e');
    }
  }

  Future<Map<String, dynamic>?> getUserListEntry(int animeId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final data = await _supabase
          .from('user_anime_list')
          .select()
          .eq('user_id', user.id)
          .eq('anime_id', animeId)
          .maybeSingle();
      
      return data;
    } catch (e) {
      print('Error en getUserListEntry: $e');
      return null;
    }
  }


  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      // Si ya lo tenemos en memoria y coincide con el usuario actual, lo devolvemos rápido
      if (_cachedProfile != null && _cachedProfile!['id'] == user.id) {
        return _cachedProfile;
      }

      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      
      // Si no tiene avatar (nuevo usuario), le asignamos uno aleatorio
      if (data['avatar_url'] == null || (data['avatar_url'] as String).isEmpty) {
        final randomAvatars = [
          'https://www.themoviedb.org/t/p/w600_and_h900_bestv2/7qZz6j3M25JkZ7v4f2mYVz3kY8n.jpg', // Luffy
          'https://www.themoviedb.org/t/p/w600_and_h900_bestv2/8S0e0m6t6BwE2o1Z6J0V1Y5S6vE.jpg', // Goku
          'https://www.themoviedb.org/t/p/w600_and_h900_bestv2/9f9Wc4uWwM8kZ6O0J0k3v7Y0y4n.jpg', // Naruto
          'https://www.themoviedb.org/t/p/w600_and_h900_bestv2/6kX3V5k6M25JkZ7v4f2mYVz3kY8n.jpg', // Deku
          'https://www.themoviedb.org/t/p/w600_and_h900_bestv2/5kX3V5k6M25JkZ7v4f2mYVz3kY8n.jpg', // Tanjiro
        ];
        final randomAvatar = randomAvatars[DateTime.now().millisecond % randomAvatars.length];
        await updateProfile(avatarUrl: randomAvatar);
        data['avatar_url'] = randomAvatar;
      }

      _cachedProfile = data; // Guardamos en memoria
      _saveProfileToDisk(); // Persistir en disco
      return data;
    } catch (e) {
      print('Error en getCurrentUserProfile: $e');
      return null;
    }
  }

  Future<List<Anime>> fetchFavorites({String? userId}) async {
    try {
      final effectiveUserId = userId ?? _supabase.auth.currentUser?.id;
      if (effectiveUserId == null) return [];

      final data = await _supabase
          .from('favorites')
          .select('*, animes!favorites_anime_id_fkey(*)') // Hint explícito de la relación
          .eq('user_id', effectiveUserId)
          .order('created_at', ascending: false);
      
      final animes = (data as List)
          .where((item) => item['animes'] != null)
          .map((item) => Anime.fromMap(item['animes'] as Map<String, dynamic>))
          .toList();

      if (userId == null || userId == _supabase.auth.currentUser?.id) {
        _staticFavorites = animes;
        // Persistencia Fase 3
        _saveToDisk('user_favorites_cache', animes.map((a) => a.toMap()).toList());
      }

      _updateConnection(true);
      return animes;
    } catch (e) {
      print('Error en fetchFavorites: $e');
      _updateConnection(false);
      // Solo devolvemos caché si es para el mismo usuario
      if (userId == null || userId == _supabase.auth.currentUser?.id) {
        if (_staticFavorites != null && _staticFavorites!.isNotEmpty) return _staticFavorites!;
        final cached = await _loadFromDisk('user_favorites_cache');
        if (cached != null) {
          final list = (cached as List).map((e) => Anime.fromMap(e)).toList();
          _staticFavorites = list;
          return list;
        }
      }
      return [];
    }
  }

  Future<List<Anime>> fetchRecentActivity({String? userId}) async {
    try {
      final effectiveUserId = userId ?? _supabase.auth.currentUser?.id;
      if (effectiveUserId == null) return [];

      final data = await _supabase
          .from('user_anime_list')
          .select('*, animes(*)')
          .eq('user_id', effectiveUserId)
          .inFilter('status', ['Viendo', 'Visto'])
          .order('updated_at', ascending: false)
          .limit(10);
      
      final animes = (data as List)
          .where((item) => item['animes'] != null)
          .map((item) => Anime.fromMap(item['animes'] as Map<String, dynamic>))
          .toList();

      if (userId == null || userId == _supabase.auth.currentUser?.id) {
        _staticRecentActivity = animes;
      }

      return animes;
    } catch (e) {
      print('Error en fetchRecentActivity: $e');
      // Solo devolvemos caché si es para el mismo usuario
      if (userId == null || userId == _supabase.auth.currentUser?.id) {
        return _staticRecentActivity ?? [];
      }
      return [];
    }
  }

  Future<void> updateProfile({String? fullName, String? username, String? avatarUrl}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      final updates = {
        'id': user.id,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (fullName != null) updates['full_name'] = fullName;
      if (username != null) updates['username'] = username;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await _supabase.from('profiles').upsert(updates);
      
      // Actualizamos la memoria rápida al momento
      if (_cachedProfile != null) {
        _cachedProfile!.addAll(updates);
      } else {
        _cachedProfile = updates;
      }
      
      _saveProfileToDisk(); // Persistir cambio en disco
      notifyProfileChanged(); // Notificamos el cambio correctamente
    } catch (e) {
      print('Error en updateProfile: $e');
      throw Exception('Error al actualizar el perfil: $e');
    }
  }

  Future<void> changePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      print('Error en changePassword: $e');
      throw Exception('Error al cambiar la contraseña: $e');
    }
  }

  Future<Map<String, int>> fetchUserStats({String? userId}) async {
    try {
      final effectiveUserId = userId ?? _supabase.auth.currentUser?.id;
      if (effectiveUserId == null) return {'vistos': 0, 'capitulos': 0};

      // Si es para mí, y tenemos caché, la devolvemos pero seguimos cargando
      final isMe = userId == null || userId == _supabase.auth.currentUser?.id;

      final data = await _supabase
          .from('user_anime_list')
          .select('status, episodes_watched')
          .eq('user_id', effectiveUserId);

      int vistos = 0;
      int capitulos = 0;
      for (var row in data) {
        if (row['status'] == 'Visto') vistos++;
        capitulos += (row['episodes_watched'] as int? ?? 0);
      }
      
      final stats = {'vistos': vistos, 'capitulos': capitulos};
      if (isMe) {
        _staticUserStats = stats;
        _saveToDisk('user_stats_cache', stats);
      }
      
      _updateConnection(true);
      return stats;
    } catch (e) {
      print('Error en fetchUserStats: $e');
      _updateConnection(false);
      // Solo devolvemos caché si es para el mismo usuario
      final isMe = userId == null || userId == _supabase.auth.currentUser?.id;
      if (isMe) {
        if (_staticUserStats != null) return _staticUserStats!;
        final cached = await _loadFromDisk('user_stats_cache');
        if (cached != null) {
          _staticUserStats = Map<String, int>.from(cached);
          return _staticUserStats!;
        }
      }
      return {'vistos': 0, 'capitulos': 0};
    }
  }

  // Getters para acceso instantáneo
  static Map<String, int>? get cachedUserStats => _staticUserStats;
  static List<Anime>? get cachedFavorites => _staticFavorites;
  static List<Anime>? get cachedRecentActivity => _staticRecentActivity;

  Future<String?> uploadAvatar(Uint8List fileBytes, String fileName) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final extension = fileName.split('.').last;
      final path = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      
      await _supabase.storage.from('avatars').uploadBinary(
        path,
        fileBytes,
        fileOptions: FileOptions(upsert: true, contentType: 'image/$extension'),
      );

      final String publicUrl = _supabase.storage.from('avatars').getPublicUrl(path);
      
      // Actualizamos el perfil automáticamente con la nueva URL
      await updateProfile(avatarUrl: publicUrl);
      
      return publicUrl;
    } catch (e) {
      print('Error en uploadAvatar: $e');
      return null;
    }
  }

  static List<Map<String, String>>? _staticAvatarCatalog;

  Future<List<Map<String, String>>> fetchAvatarCatalog({bool forceRefresh = false}) async {
    try {
      if (_staticAvatarCatalog != null && !forceRefresh) {
        return _staticAvatarCatalog!;
      }

      final data = await _supabase
          .from('avatar_catalog')
          .select('name, url')
          .order('name', ascending: true);
      
      final result = (data as List).map((item) => {
        'name': item['name'] as String,
        'url': item['url'] as String,
      }).toList();

      _staticAvatarCatalog = result;
      return result;
    } catch (e) {
      print('Error en fetchAvatarCatalog: $e');
      return _staticAvatarCatalog ?? [];
    }
  }

  static List<Map<String, String>>? get cachedAvatarCatalog => _staticAvatarCatalog;

  // === SOCIAL METHODS (AMIGOS Y ACTIVIDAD) ===

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      // Buscamos en username O en full_name para que los usuarios de Google también salgan
      final data = await _supabase
          .from('profiles')
          .select()
          .or('username.ilike.%$query%,full_name.ilike.%$query%')
          .neq('id', currentUser?.id ?? '')
          .neq('id', 'faedee87-29a1-4cc5-bcfe-127aab5b9998'); // Excluir admin de tests
      
      return (data as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error en searchUsers: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSuggestedUsers({required List<String> excludeIds}) async {
    try {
      // Filtrar por IDs que no queremos (yo, admin, amigos, peticiones)
      final data = await _supabase
          .from('profiles')
          .select()
          .not('id', 'in', excludeIds)
          .limit(10);
      
      return (data as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error en fetchSuggestedUsers: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchFriendshipStatus(String targetUserId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return {'status': 'none'};
      if (user.id == targetUserId) return {'status': 'me'};

      // 1. Verificar si ya son amigos
      final friendship = await _supabase
          .from('friendships')
          .select()
          .eq('user_id', user.id)
          .eq('friend_id', targetUserId)
          .maybeSingle();
      
      if (friendship != null) {
        return {
          'status': 'friends',
          'isFavorite': friendship['is_favorite'] ?? false,
        };
      }

      // 2. Verificar si hay solicitudes pendientes enviadas por MÍ
      final sentRequest = await _supabase
          .from('friend_requests')
          .select()
          .eq('sender_id', user.id)
          .eq('receiver_id', targetUserId)
          .eq('status', 'pending')
          .maybeSingle();
      
      if (sentRequest != null) {
        return {'status': 'pending_sent', 'requestId': sentRequest['id']};
      }

      // 3. Verificar si hay solicitudes pendientes enviadas por EL OTRO
      final receivedRequest = await _supabase
          .from('friend_requests')
          .select()
          .eq('sender_id', targetUserId)
          .eq('receiver_id', user.id)
          .eq('status', 'pending')
          .maybeSingle();
      
      if (receivedRequest != null) {
        return {'status': 'pending_received', 'requestId': receivedRequest['id']};
      }

      return {'status': 'none'};
    } catch (e) {
      print('Error en fetchFriendshipStatus: $e');
      return {'status': 'none'};
    }
  }

  Future<void> sendFriendRequest(String targetUserId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Usamos upsert para que si ya existe un registro (aunque sea viejo/aceptado), 
      // se actualice a 'pending' y permita re-enviar la solicitud.
      await _supabase.from('friend_requests').upsert({
        'sender_id': user.id,
        'receiver_id': targetUserId,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'sender_id, receiver_id');
      
    } on PostgrestException catch (e) {
      print('Error Postgrest en sendFriendRequest: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('Error en sendFriendRequest: $e');
      throw Exception('Hubo un error al enviar la solicitud.');
    }
  }

  Future<List<Map<String, dynamic>>> fetchFriendRequests() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from('friend_requests')
          .select('*, sender:profiles!sender_id(*)')
          .eq('receiver_id', user.id)
          .eq('status', 'pending');
      
      return (data as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error en fetchFriendRequests: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSentFriendRequests() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from('friend_requests')
          .select('*, receiver:profiles!receiver_id(*)')
          .eq('sender_id', user.id)
          .eq('status', 'pending');
      
      return (data as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error en fetchSentFriendRequests: $e');
      return [];
    }
  }

  Future<void> cancelFriendRequest(int requestId) async {
    try {
      await _supabase.from('friend_requests').delete().eq('id', requestId);
    } catch (e) {
      print('Error en cancelFriendRequest: $e');
      throw Exception('No se pudo cancelar la solicitud');
    }
  }

  Future<void> respondToFriendRequest(int requestId, bool accept) async {
    try {
      if (accept) {
        await _supabase.rpc('accept_friend_request', params: {'request_id': requestId});
      } else {
        await _supabase
            .from('friend_requests')
            .update({'status': 'declined'})
            .eq('id', requestId);
      }
    } catch (e) {
      print('Error en respondToFriendRequest: $e');
      throw Exception('No se pudo procesar la petición');
    }
  }

  Future<List<Map<String, dynamic>>> fetchFriendsWithWatchingStatus() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final friendsData = await _supabase
          .from('friendships')
          .select('friend_id, is_favorite, friend:profiles!friend_id(*)')
          .eq('user_id', user.id);
      
      final List<Map<String, dynamic>> result = [];

      for (var f in friendsData) {
        final friendId = f['friend_id'];
        final isFavorite = f['is_favorite'] ?? false;
        final profile = f['friend'] as Map<String, dynamic>;

        final lastWatching = await _supabase
            .from('user_anime_list')
            .select('*, animes(*)')
            .eq('user_id', friendId)
            .eq('status', 'Viendo')
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle();
        
        result.add({
          'profile': profile,
          'watching': lastWatching,
          'isFavorite': isFavorite,
        });
      }
      return result;
    } catch (e) {
      print('Error en fetchFriendsWithWatchingStatus: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchFriendsAnimeActivity() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final friends = await _supabase.from('friendships').select('friend_id').eq('user_id', user.id);
      final friendIds = (friends as List).map((f) => f['friend_id'] as String).toList();

      if (friendIds.isEmpty) return [];

      // 1. Traer la actividad de animes (sin join de perfiles)
      final data = await _supabase
          .from('user_anime_list')
          .select('*, animes(*)')
          .inFilter('user_id', friendIds)
          .inFilter('status', ['Viendo', 'Visto'])
          .order('updated_at', ascending: false)
          .limit(20);
      
      if (data.isEmpty) return [];

      // 2. Traer los perfiles de los amigos involucrados en lote
      final userIds = (data as List).map((e) => e['user_id'] as String).toSet().toList();
      final profiles = await _supabase
          .from('profiles')
          .select()
          .inFilter('id', userIds);
      
      final profileMap = { for (var p in profiles) p['id'] as String: p };

      // 3. Fusionar los datos en Dart
      return data.map((item) {
        final Map<String, dynamic> row = Map<String, dynamic>.from(item);
        row['profile'] = profileMap[row['user_id']];
        return row;
      }).toList();
    } catch (e) {
      print('Error en fetchFriendsAnimeActivity: $e');
      return [];
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      // Eliminamos en ambas direcciones para asegurar consistencia
      await _supabase.from('friendships').delete().match({
        'user_id': user.id,
        'friend_id': friendId,
      });
      
      await _supabase.from('friendships').delete().match({
        'user_id': friendId,
        'friend_id': user.id,
      });

      // También eliminamos el rastro en friend_requests para evitar conflictos futuros
      await _supabase.from('friend_requests').delete().match({
        'sender_id': user.id,
        'receiver_id': friendId,
      });
      await _supabase.from('friend_requests').delete().match({
        'sender_id': friendId,
        'receiver_id': user.id,
      });

      notifyFriendsUpdate();
    } catch (e) {
      print('Error en removeFriend: $e');
      throw Exception('No se pudo eliminar al amigo: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchFriendsReviewActivity() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final friends = await _supabase.from('friendships').select('friend_id').eq('user_id', user.id);
      final friendIds = (friends as List).map((f) => f['friend_id'] as String).toList();

      if (friendIds.isEmpty) return [];

      // 1. Traer las valoraciones (sin join de perfiles)
      final data = await _supabase
          .from('reviews')
          .select('*, animes(*)')
          .inFilter('user_id', friendIds)
          .order('created_at', ascending: false)
          .limit(20);
      
      if (data.isEmpty) return [];

      // 2. Traer los perfiles involucrados en lote
      final userIds = (data as List).map((e) => e['user_id'] as String).toSet().toList();
      final profiles = await _supabase
          .from('profiles')
          .select()
          .inFilter('id', userIds);
      
      final profileMap = { for (var p in profiles) p['id'] as String: p };

      // 3. Fusionar datos
      return data.map((item) {
        final Map<String, dynamic> row = Map<String, dynamic>.from(item);
        row['profile'] = profileMap[row['user_id']];
        return row;
      }).toList();
    } catch (e) {
      print('Error en fetchFriendsReviewActivity: $e');
      return [];
    }
  }

  Future<void> toggleFavoriteFriend(String friendId, bool isFavorite) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('friendships')
          .update({'is_favorite': isFavorite})
          .eq('user_id', user.id)
          .eq('friend_id', friendId);
          
      notifyFriendsUpdate();
    } catch (e) {
      print('Error en toggleFavoriteFriend: $e');
      throw Exception('Error al actualizar favorito');
    }
  }

  Future<List<Map<String, dynamic>>> fetchUserDetailedList(String userId) async {
    try {
      // 1. Obtenemos la lista de animes del usuario
      final listData = await _supabase
          .from('user_anime_list')
          .select('*, animes(*)')
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      // 2. Obtenemos las reviews de ese mismo usuario
      final reviewsData = await _supabase
          .from('reviews')
          .select()
          .eq('user_id', userId);

      final Map<int, Map<String, dynamic>> reviewMap = {
        for (var r in reviewsData) r['anime_id']: r
      };

      // 3. Obtenemos los favoritos para marcar el flag is_favorite
      final favoritesData = await _supabase
          .from('favorites')
          .select('anime_id')
          .eq('user_id', userId);
      
      final Set<int> favoriteIds = (favoritesData as List)
          .map((f) => f['anime_id'] as int)
          .toSet();

      final result = (listData as List).map((item) {
        final animeId = item['anime_id'] as int;
        return {
          'anime': item['animes'],
          'status': item['status'],
          'episodes_watched': item['episodes_watched'],
          'updated_at': item['updated_at'],
          'review': reviewMap[animeId],
          'is_favorite': favoriteIds.contains(animeId),
        };
      }).toList();

      // Persistencia Fase 3
      if (userId == _supabase.auth.currentUser?.id) {
        _saveToDisk('user_detailed_list_cache', result);
      }

      _updateConnection(true);
      return result;
    } catch (e) {
      print('Error en fetchUserDetailedList: $e');
      _updateConnection(false);
      if (userId == _supabase.auth.currentUser?.id) {
        final cached = await _loadFromDisk('user_detailed_list_cache');
        if (cached != null) return List<Map<String, dynamic>>.from(cached);
      }
      return [];
    }
  }

  // --- SISTEMA DE GRUPOS ---

  Future<void> createGroup(String name, String description, String avatarUrl, {bool isPublic = true}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      // 1. Crear el grupo
      final groupData = await _supabase.from('groups').insert({
        'name': name,
        'description': description,
        'avatar_url': avatarUrl,
        'creator_id': user.id,
        'is_public': isPublic,
      }).select().single();

      final groupId = groupData['id'];

      // 2. Añadirse como líder
      await _supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': user.id,
        'role': 'LÍDER',
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Ya existe una comunidad con este nombre. ¡Sé original!');
      }
      rethrow;
    } catch (e) {
      print('CRITICAL: Error en createGroup: $e');
      if (e is PostgrestException) {
        print('Postgrest Error Details: ${e.message}, Code: ${e.code}, Details: ${e.details}');
      }
      throw Exception('Error al crear el grupo: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchUserGroups() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from('group_members')
          .select('*, groups(*, group_members(count))')
          .eq('user_id', user.id)
          .order('is_favorite', ascending: false);

      return (data as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error en fetchUserGroups: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchGroupById(String groupId) async {
    try {
      final data = await _supabase.from('groups').select('*, group_members(count)').eq('id', groupId).single();
      return data;
    } catch (e) {
      print('Error en fetchGroupById: $e');
      return null;
    }
  }

  Future<void> toggleGroupFavorite(String groupId, bool isFavorite) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('group_members')
          .update({'is_favorite': isFavorite})
          .match({'group_id': groupId, 'user_id': user.id});
    } catch (e) {
      print('Error en toggleGroupFavorite: $e');
    }
  }

  Future<List<Map<String, dynamic>>> searchExploreGroups(String query, {int page = 0, int pageSize = 15}) async {
    try {
      final user = _supabase.auth.currentUser;
      final start = page * pageSize;
      final end = start + pageSize - 1;

      var queryBuilder = _supabase.from('groups').select('*, group_members(count)');
      
      if (query.isNotEmpty) {
        queryBuilder = queryBuilder.ilike('name', '%$query%');
      }

      final data = await queryBuilder.order('name', ascending: true).range(start, end);

      if (user == null) return (data as List).map((e) => e as Map<String, dynamic>).toList();

      // Marcamos los que ya pertenecemos y los que tienen solicitud pendiente
      final myGroups = await _supabase.from('group_members').select('group_id').eq('user_id', user.id);
      final myGroupIds = (myGroups as List).map((m) => m['group_id'] as String).toList();

      final pendingRequests = await _supabase
          .from('group_join_requests')
          .select('group_id')
          .eq('user_id', user.id)
          .eq('status', 'pending');
      final pendingGroupIds = (pendingRequests as List).map((r) => r['group_id'] as String).toList();

      return (data as List).map((e) {
        final group = e as Map<String, dynamic>;
        
        // Extraer el conteo de miembros de la subconsulta de Supabase
        int memberCount = 0;
        if (group['group_members'] != null && (group['group_members'] as List).isNotEmpty) {
          memberCount = group['group_members'][0]['count'] ?? 0;
        }

        return {
          ...group,
          'memberCount': memberCount,
          'isMember': myGroupIds.contains(group['id']),
          'isPending': pendingGroupIds.contains(group['id']),
        };
      }).where((g) => g['isMember'] == false && (g['memberCount'] as int) > 0).toList();
    } catch (e) {
      print('Error en searchExploreGroups: $e');
      return [];
    }
  }

  Future<void> requestToJoinGroup(String groupId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      await _supabase.from('group_join_requests').upsert({
        'group_id': groupId,
        'user_id': user.id,
        'status': 'pending',
      }, onConflict: 'group_id, user_id');
    } catch (e) {
      print('Error en requestToJoinGroup: $e');
      throw Exception('Error al solicitar unirse: $e');
    }
  }


  Future<void> respondToJoinRequest(String requestId, String groupId, String userId, bool accept) async {
    try {
      if (accept) {
        // 1. Añadir a miembros del grupo
        await _supabase.from('group_members').insert({
          'group_id': groupId,
          'user_id': userId,
          'role': 'Miembro',
        });
        // 2. Marcar como aceptada
        await _supabase.from('group_join_requests').update({'status': 'accepted'}).eq('id', requestId);
      } else {
        // Marcar como rechazada
        await _supabase.from('group_join_requests').update({'status': 'rejected'}).eq('id', requestId);
      }
    } catch (e) {
      print('Error en respondToJoinRequest: $e');
      throw Exception('Error al procesar la solicitud: $e');
    }
  }

  Future<void> joinGroup(String groupId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      await _supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': user.id,
        'role': 'member',
      });
    } catch (e) {
      print('Error en joinGroup: $e');
      throw Exception('Error al unirse al grupo: $e');
    }
  }

  Future<void> leaveGroup(String groupId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      // 1. Obtener todos los miembros actuales para decidir el curso de acción
      final allMembers = await fetchGroupMembers(groupId);
      
      // CASO ESPECIAL: Soy el último miembro del grupo
      if (allMembers.length <= 1) {
        print('Detectado último miembro. Pescando eliminación total del grupo.');
        await deleteGroup(groupId);
        return;
      }

      // 2. Si hay más miembros, verificar mi rol para traspasar liderato si es necesario
      final myMemberData = allMembers.firstWhere(
        (m) => m['user_id'] == user.id,
        orElse: () => {},
      );
      
      final String role = (myMemberData['role']?.toString() ?? '').trim().toUpperCase();

      if (role == 'LÍDER' || role == 'LEADER' || role == 'ADMIN') {
        final otherMembers = allMembers.where((m) => m['user_id'] != user.id).toList();

        // Si llegamos aquí, otherMembers no está vacío por la comprobación inicial
        // Prioridad 1: Moderadores
        final moderators = otherMembers.where((m) {
          final r = (m['role']?.toString() ?? '').trim().toUpperCase();
          return r == 'MODERADOR' || r == 'MODERATOR';
        }).toList();

        String successorId;
        if (moderators.isNotEmpty) {
          successorId = moderators.first['user_id'];
        } else {
          // Prioridad 2: Miembro aleatorio
          successorId = otherMembers.first['user_id'];
        }

        // Promocionar al sucesor
        await updateGroupMemberRole(groupId, successorId, 'LÍDER');
      }

      // 3. Salir del grupo normalmente (ya hay un sucesor o no soy el líder)
      await _supabase.from('group_members').delete().eq('group_id', groupId).eq('user_id', user.id);
      
    } catch (e) {
      print('Error en leaveGroup (con auto-limpieza simplificada): $e');
      throw Exception('Error al abandonar el grupo: $e');
    }
  }

  Future<void> transferLeadership(String groupId, String newLeaderId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // 1. El nuevo usuario pasa a ser LÍDER
      await updateGroupMemberRole(groupId, newLeaderId, 'LÍDER');
      
      // 2. Yo paso a ser un MIEMBRO normal
      await updateGroupMemberRole(groupId, user.id, 'MIEMBRO');
    } catch (e) {
      print('Error en transferLeadership: $e');
      throw Exception('Error al traspasar el liderato');
    }
  }

  Future<void> updateGroupPrivacy(String groupId, bool isPublic) async {
    try {
      await _supabase.from('groups').update({'is_public': isPublic}).eq('id', groupId);
      
      // Si el grupo pasa a ser público, aceptamos todas las peticiones pendientes automáticamente
      if (isPublic) {
        final pendingData = await _supabase
            .from('group_join_requests')
            .select('user_id, id')
            .eq('group_id', groupId)
            .eq('status', 'pending');
        
        final List<Map<String, dynamic>> requests = (pendingData as List).map((e) => e as Map<String, dynamic>).toList();
        
        if (requests.isNotEmpty) {
          // 1. Añadimos a todos los usuarios como miembros
          final List<Map<String, dynamic>> memberInserts = requests.map((r) => {
            'group_id': groupId,
            'user_id': r['user_id'],
            'role': 'Miembro',
          }).toList();
          
          await _supabase.from('group_members').insert(memberInserts);
          
          // 2. Marcamos las peticiones como aceptadas
          final List<String> requestIds = requests.map((r) => r['id'].toString()).toList();
          await _supabase.from('group_join_requests').update({'status': 'accepted'}).inFilter('id', requestIds);
        }
      }
    } catch (e) {
      print('Error en updateGroupPrivacy: $e');
      throw Exception('Error al actualizar la privacidad del grupo y procesar peticiones: $e');
    }
  }

  Future<void> updateGroupInfo(String groupId, String name, String description, String avatarUrl) async {
    try {
      final updates = {
        'name': name,
        'description': description,
        'avatar_url': avatarUrl,
      };
      await _supabase.from('groups').update(updates).eq('id', groupId);
    } catch (e) {
      print('Error en updateGroupInfo: $e');
      throw Exception('Error al actualizar la información del grupo');
    }
  }

  Future<void> deleteGroup(String groupId) async {
    try {
      print('Iniciando borrado exhaustivo del grupo: $groupId');
      
      // 1. Borrar todas las dependencias manualmente en orden inverso de importancia
      // Esto evita errores de clave foránea si el CASCADE de Supabase no está configurado
      await _supabase.from('group_messages').delete().eq('group_id', groupId);
      await _supabase.from('group_anime_ratings').delete().eq('group_id', groupId);
      await _supabase.from('group_animes').delete().eq('group_id', groupId);
      await _supabase.from('group_join_requests').delete().eq('group_id', groupId);
      
      // 2. Borrar el grupo mientras aún somos miembros (para que las políticas RLS nos dejen)
      final result = await _supabase.from('groups').delete().eq('id', groupId).select();
      
      // 3. Finalmente borrar a los miembros (si el CASCADE de SQL no lo hizo ya)
      await _supabase.from('group_members').delete().eq('group_id', groupId);

      if (result.isEmpty) {
        print('AVISO CRÍTICO: Supabase no devolvió filas borradas para el grupo $groupId.');
        print('Causa probable: Políticas RLS (Row Level Security) impiden que este usuario borre el registro de la tabla "groups".');
        throw Exception('No tienes permisos suficientes en la base de datos para eliminar este grupo.');
      }

      print('Grupo eliminado con éxito de todas las tablas.');
    } catch (e) {
      print('Error profundo en deleteGroup: $e');
      
      // Reintentar el borrado del grupo padre como última opción desesperada
      try {
        final retryResult = await _supabase.from('groups').delete().eq('id', groupId).select();
        if (retryResult.isEmpty) throw Exception('Reintento fallido: Permisos insuficientes.');
      } catch (e2) {
        print('Fallo total en el reintento de borrado: $e2');
        // Si llegamos aquí, lanzamos un error que la UI pueda entender
        if (e2.toString().contains('42501') || e2.toString().contains('permisos')) {
          throw Exception('Error de permisos en Supabase (RLS): No eres el dueño del grupo.');
        }
        throw Exception('Error al eliminar el grupo: $e2');
      }
    }
  }

  // --- SISTEMA DE CLUBES (ANIME EN GRUPOS) ---

  Future<List<Map<String, dynamic>>> fetchGroupAnimes(String groupId) async {
    try {
      // 1. Obtener la lista de animes agregados al grupo
      const animeFields = 'mal_id, title, image_url, score, synopsis, status, genres, demographic, release_year, episodes';
      final data = await _supabase
          .from('group_animes')
          .select('*, anime_info:animes($animeFields)')
          .eq('group_id', groupId);
      
      final myId = currentUser?.id ?? '';
      
      // 2. Obtener la lista de todos los miembros de este grupo
      final membersData = await _supabase
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId);
      final memberIds = membersData.map((m) => m['user_id'] as String).toList();

      // 3. Obtener mis datos personales para cruzarlos localmente (estado de visualización de mis animes)
      final myPersonalRaw = await _supabase
          .from('user_anime_list')
          .select('anime_id, status, episodes_watched')
          .eq('user_id', myId);
      final personalMap = { for (var e in myPersonalRaw) e['anime_id']: e };

      // 4. Obtener todas las opiniones personales de todos los miembros del grupo para cruzar sus valoraciones personales
      List<dynamic> allMembersReviewsRaw = [];
      if (memberIds.isNotEmpty) {
        allMembersReviewsRaw = await _supabase
            .from('reviews')
            .select('anime_id, user_id, rating, opinion')
            .inFilter('user_id', memberIds);
      }
      
      // Mapear reviews: anime_id -> { user_id: { rating: double, opinion: String } }
      final Map<int, Map<String, Map<String, dynamic>>> reviewsByAnime = {};
      for (var r in allMembersReviewsRaw) {
        final animeId = r['anime_id'] as int;
        final userId = r['user_id'] as String;
        final rating = (r['rating'] as num).toDouble();
        final opinion = r['opinion']?.toString() ?? '';
        reviewsByAnime.putIfAbsent(animeId, () => {})[userId] = {
          'rating': rating,
          'opinion': opinion,
        };
      }

      // 5. Obtener todos los votos guardados dentro de este grupo (de cualquier miembro)
      final groupRatingsRaw = await _supabase
          .from('group_anime_ratings')
          .select('anime_id, user_id, rating')
          .eq('group_id', groupId);

      // Mapear votos del grupo: anime_id -> { user_id: rating }
      final Map<int, Map<String, double>> groupRatingsByAnime = {};
      for (var r in groupRatingsRaw) {
        final animeId = r['anime_id'] as int;
        final userId = r['user_id'] as String;
        final rating = (r['rating'] as num).toDouble();
        groupRatingsByAnime.putIfAbsent(animeId, () => {})[userId] = rating;
      }
      
      List<Map<String, dynamic>> result = [];
      for (var item in data) {
        final animeMap = item['anime_info'] as Map<String, dynamic>?;
        if (animeMap == null) continue;

        final animeId = animeMap['mal_id'];
        
        final groupRatings = groupRatingsByAnime[animeId] ?? {};
        final personalReviews = reviewsByAnime[animeId] ?? {};

        // Combinar valoraciones:
        // Si el miembro tiene voto en el grupo, usamos ese voto.
        // Si no, si tiene un voto personal en sus reviews, lo sumamos y además programamos la sincronización en segundo plano.
        final Map<String, double> finalRatings = {};
        
        // Cargar primero los del grupo
        groupRatings.forEach((uid, rating) {
          finalRatings[uid] = rating;
        });

        // Luego cruzar con las reviews de todos los miembros del grupo
        for (var memberId in memberIds) {
          if (!finalRatings.containsKey(memberId)) {
            final reviewData = personalReviews[memberId];
            if (reviewData != null) {
              final double personalRating = reviewData['rating'];
              finalRatings[memberId] = personalRating;
              
              // Sincronizar automáticamente en segundo plano para guardarlo en group_anime_ratings
              _syncRatingToGroupInBackground(groupId, animeId, memberId, personalRating);
            }
          }
        }

        // Obtener el voto del usuario actual en el grupo o personal
        final double? myRating = finalRatings[myId];
        final myPersonalEntry = personalMap[animeId];
        final myPersonalReview = personalReviews[myId];

        // Calcular la media combinada de todos los miembros
        double groupAvg = 0;
        int totalVotes = finalRatings.length;
        if (totalVotes > 0) {
          double sum = 0;
          finalRatings.forEach((_, val) => sum += val);
          groupAvg = sum / totalVotes;
        }

        result.add({
          'anime': Anime.fromMap(animeMap),
          'avg_rating': groupAvg,
          'total_votes': totalVotes,
          'my_rating': myRating,
          'my_status': myPersonalEntry != null ? myPersonalEntry['status'] : 'No en mi lista',
          'my_episodes': myPersonalEntry != null ? (myPersonalEntry['episodes_watched'] as num).toInt() : 0,
          'my_opinion': myPersonalReview != null ? (myPersonalReview['opinion'] ?? '') : '',
        });
      }

      // ORDENAR: Mejores puntuados primero (Descendente por avg_rating)
      result.sort((a, b) {
        final double ratingA = (a['avg_rating'] as num).toDouble();
        final double ratingB = (b['avg_rating'] as num).toDouble();
        return ratingB.compareTo(ratingA);
      });
      
      return result;
    } catch (e) {
      print('Error en fetchGroupAnimes: $e');
      throw Exception('Error al cargar animes del grupo');
    }
  }

  void _syncRatingToGroupInBackground(String groupId, int animeId, String userId, double rating) {
    final now = DateTime.now().toIso8601String();
    Future.microtask(() async {
      try {
        try {
          await _supabase.from('group_anime_ratings').upsert({
            'group_id': groupId,
            'anime_id': animeId,
            'user_id': userId,
            'rating': rating,
            'created_at': now,
          }, onConflict: 'group_id,anime_id,user_id');
        } catch (e1) {
          try {
            await _supabase.from('group_anime_ratings').upsert({
              'group_id': groupId,
              'anime_id': animeId,
              'user_id': userId,
              'rating': rating,
              'created_at': now,
            }, onConflict: 'group_id,user_id,anime_id');
          } catch (e2) {
            try {
              await _supabase.from('group_anime_ratings').upsert({
                'group_id': groupId,
                'anime_id': animeId,
                'user_id': userId,
                'rating': rating,
              }, onConflict: 'group_id,anime_id,user_id');
            } catch (e3) {
              await _supabase.from('group_anime_ratings').upsert({
                'group_id': groupId,
                'anime_id': animeId,
                'user_id': userId,
                'rating': rating,
              }, onConflict: 'group_id,user_id,anime_id');
            }
          }
        }
      } catch (e) {
        print('Error en sincronización automática en segundo plano: $e');
      }
    });
  }


  Future<void> updateEpisodeProgress(int animeId, int episodes) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Primero intentamos ver si ya tiene un estado para no sobreescribirlo
      final existing = await _supabase.from('user_anime_list')
          .select('status')
          .eq('user_id', user.id)
          .eq('anime_id', animeId)
          .maybeSingle();

      // Si los episodios alcanzaron el máximo, marcar como 'Visto' automáticamente
      final anime = await _supabase.from('animes').select('episodes').eq('mal_id', animeId).single();
      final int maxEp = anime['episodes'] ?? 0;
      
      String statusToUse = (existing != null) ? existing['status'] : 'Viendo';
      
      // AUTO-STATUS LOGIC:
      if (episodes > 0 && episodes < maxEp) {
        statusToUse = 'Viendo';
      } else if (episodes >= maxEp && maxEp > 0) {
        statusToUse = 'Visto';
      } else if (episodes == 0) {
        statusToUse = 'Pendiente';
      }

      await _supabase.from('user_anime_list').upsert({
        'user_id': user.id,
        'anime_id': animeId,
        'episodes_watched': episodes,
        'status': statusToUse,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,anime_id');
    } catch (e) {
      print('Error en updateEpisodeProgress: $e');
      throw Exception('Error al actualizar progreso de episodios');
    }
  }

  Future<void> updateUserAnimeStatus(int animeId, String status) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final now = DateTime.now().toIso8601String();

      // 1. Si el estado es "No en mi lista", borrar la entrada por completo
    if (status == 'No en mi lista') {
      await _supabase.from('user_anime_list').delete().eq('user_id', user.id).eq('anime_id', animeId);
      
      // También borrar valoraciones personales y de grupo relacionadas
      await _supabase.from('reviews').delete().eq('user_id', user.id).eq('anime_id', animeId);
      await _supabase.from('group_anime_ratings').delete().eq('user_id', user.id).eq('anime_id', animeId);
      return;
    }

    // 2. Si se marca como "Visto", auto-completar episodios
      int? episodesToSet;
      if (status == 'Visto') {
        final animeData = await _supabase.from('animes').select('episodes').eq('mal_id', animeId).maybeSingle();
        if (animeData != null) {
          episodesToSet = animeData['episodes'] as int?;
        }
      }

      // 3. Actualizar el estado (y episodios si aplica)
      final updateData = {
        'user_id': user.id,
        'anime_id': animeId,
        'status': status,
        'updated_at': now,
      };
      if (episodesToSet != null) {
        updateData['episodes_watched'] = episodesToSet;
      }

      await _supabase.from('user_anime_list').upsert(updateData, onConflict: 'user_id,anime_id');
    } catch (e) {
      print('Error en updateUserAnimeStatus: $e');
      throw Exception('Error al sincronizar con tu lista personal');
    }
  }


  Future<void> addGroupAnime(String groupId, int animeId) async {
    try {
      // 1. Añadir el anime a la lista del grupo
      await _supabase.from('group_animes').insert({
        'group_id': groupId,
        'anime_id': animeId,
        'added_by': currentUser?.id,
      });

      // 2. Comprobar si el usuario actual ya lo tenía puntuado en su lista personal
      final user = currentUser;
      if (user != null) {
        final personalReview = await _supabase
            .from('reviews')
            .select('rating, opinion')
            .eq('user_id', user.id)
            .eq('anime_id', animeId)
            .maybeSingle();

        if (personalReview != null) {
          final rating = (personalReview['rating'] as num).toDouble();
          final now = DateTime.now().toIso8601String();

          // Sincronizar la nota al grupo de forma adaptativa
          try {
            await _supabase.from('group_anime_ratings').upsert({
              'group_id': groupId,
              'anime_id': animeId,
              'user_id': user.id,
              'rating': rating,
              'created_at': now,
            }, onConflict: 'group_id,anime_id,user_id');
          } catch (e1) {
            try {
              await _supabase.from('group_anime_ratings').upsert({
                'group_id': groupId,
                'anime_id': animeId,
                'user_id': user.id,
                'rating': rating,
                'created_at': now,
              }, onConflict: 'group_id,user_id,anime_id');
            } catch (e2) {
              try {
                await _supabase.from('group_anime_ratings').upsert({
                  'group_id': groupId,
                  'anime_id': animeId,
                  'user_id': user.id,
                  'rating': rating,
                }, onConflict: 'group_id,anime_id,user_id');
              } catch (e3) {
                try {
                  await _supabase.from('group_anime_ratings').upsert({
                    'group_id': groupId,
                    'anime_id': animeId,
                    'user_id': user.id,
                    'rating': rating,
                  }, onConflict: 'group_id,user_id,anime_id');
                } catch (e4) {
                  // Si falla la sincronización de nota inicial, logueamos pero no cancelamos la inserción del anime
                  print('Error al sincronizar nota inicial al grupo: $e4');
                }
              }
            }
          }
        }
      }
    } catch (e) {
      if (e.toString().contains('23505')) throw Exception('Este anime ya está en la lista del grupo.');
      if (e.toString().contains('42501')) throw Exception('No tienes permisos suficientes para añadir animes a este grupo.');
      print('Error en addGroupAnime: $e');
      throw Exception('No se pudo añadir el anime. Verifica tus permisos de Admin o Moderador.');
    }
  }


  Future<List<Map<String, dynamic>>> fetchGroupDetailedRatings(String groupId, int animeId) async {
    try {
      final myId = currentUser?.id;
      final friendIds = await fetchFriendshipIds();

      // 1. Traer todos los ratings del grupo
      List<dynamic> data;
      bool hasCreatedAt = true;
      try {
        data = await _supabase
            .from('group_anime_ratings')
            .select('rating, user_id, created_at')
            .eq('group_id', groupId)
            .eq('anime_id', animeId);
      } catch (e) {
        hasCreatedAt = false;
        data = await _supabase
            .from('group_anime_ratings')
            .select('rating, user_id')
            .eq('group_id', groupId)
            .eq('anime_id', animeId);
      }
      
      if (data.isEmpty) return [];

      final userIds = data.map((r) => r['user_id'] as String).toList();

      // 2. Traer perfiles por separado
      final profiles = await _supabase
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', userIds);
      
      final Map<String, Map<String, dynamic>> profileMap = {
        for (var p in profiles) p['id'] as String: p
      };

      // 3. Traer opiniones en lote
      final reviews = await _supabase
          .from('reviews')
          .select('user_id, opinion')
          .eq('anime_id', animeId)
          .inFilter('user_id', userIds);

      final Map<String, String> opinionMap = {
        for (var r in reviews) r['user_id'] as String: r['opinion']?.toString() ?? ''
      };
          
      // 4. Cruzar los datos y añadir flags sociales
      List<Map<String, dynamic>> result = data.map((row) {
        final Map<String, dynamic> merged = Map<String, dynamic>.from(row);
        final userId = row['user_id'] as String;
        merged['profile'] = profileMap[userId] ?? {'username': 'Usuario'};
        merged['opinion'] = opinionMap[userId] ?? '';
        merged['isMe'] = userId == myId;
        merged['isFriend'] = friendIds.contains(userId);
        return merged;
      }).toList();

      // 5. Ordenar: Yo > Amigos > Otros (y por fecha dentro de cada bloque si existe created_at)
      result.sort((a, b) {
        // Prioridad 1: Yo
        if (a['isMe'] == true) return -1;
        if (b['isMe'] == true) return 1;
        
        // Prioridad 2: Amigos
        if (a['isFriend'] == true && b['isFriend'] == false) return -1;
        if (a['isFriend'] == false && b['isFriend'] == true) return 1;
        
        // Por defecto: Fecha descendente (si existe created_at)
        if (hasCreatedAt && a['created_at'] != null && b['created_at'] != null) {
          try {
            final dateA = DateTime.parse(a['created_at'] as String);
            final dateB = DateTime.parse(b['created_at'] as String);
            return dateB.compareTo(dateA);
          } catch (_) {}
        }
        return 0;
      });

      return result;
    } catch (e) {
      print('Error en fetchGroupDetailedRatings: $e');
      return [];
    }
  }

  Future<void> rateGroupAnime(String groupId, int animeId, double rating, {String opinion = ''}) async {
    try {
      final user = currentUser;
      if (user == null) return;

      final now = DateTime.now().toIso8601String();

      // 1. Guardar nota en el grupo (Esto disparará el trigger de sincronización personal)
      try {
        // Opción A: Intentamos con created_at y onConflict A
        await _supabase.from('group_anime_ratings').upsert({
          'group_id': groupId,
          'anime_id': animeId,
          'user_id': user.id,
          'rating': rating,
          'created_at': now,
        }, onConflict: 'group_id,anime_id,user_id');
      } catch (e1) {
        try {
          // Opción B: Intentamos con created_at y onConflict B
          await _supabase.from('group_anime_ratings').upsert({
            'group_id': groupId,
            'anime_id': animeId,
            'user_id': user.id,
            'rating': rating,
            'created_at': now,
          }, onConflict: 'group_id,user_id,anime_id');
        } catch (e2) {
          try {
            // Opción C: Intentamos sin created_at y onConflict A (por si no hay columna de tiempo)
            await _supabase.from('group_anime_ratings').upsert({
              'group_id': groupId,
              'anime_id': animeId,
              'user_id': user.id,
              'rating': rating,
            }, onConflict: 'group_id,anime_id,user_id');
          } catch (e3) {
            try {
              // Opción D: Intentamos sin created_at y onConflict B
              await _supabase.from('group_anime_ratings').upsert({
                'group_id': groupId,
                'anime_id': animeId,
                'user_id': user.id,
                'rating': rating,
              }, onConflict: 'group_id,user_id,anime_id');
            } catch (e4) {
              print('Fallo en todas las combinaciones de upsert en group_anime_ratings: $e4');
              rethrow;
            }
          }
        }
      }

      // 2. Guardar la opinión en las reseñas personales (Sincronización de texto)
      try {
        await _supabase.from('reviews').upsert({
          'user_id': user.id,
          'anime_id': animeId,
          'rating': rating,
          'opinion': opinion,
          'created_at': now,
        }, onConflict: 'anime_id,user_id');
      } catch (e2) {
        // Fallback secundario si la restricción de reviews difiere
        try {
          await _supabase.from('reviews').upsert({
            'user_id': user.id,
            'anime_id': animeId,
            'rating': rating,
            'opinion': opinion,
            'created_at': now,
          }, onConflict: 'user_id,anime_id');
        } catch (e2Fallback) {
          print('Error en upsert reviews: $e2Fallback');
          rethrow;
        }
      }

    } catch (e) {
      print('Error en rateGroupAnime con sincronización total: $e');
      throw Exception('Error al puntuar: $e');
    }
  }



  Future<List<Map<String, dynamic>>> fetchGroupMembers(String groupId) async {
    try {
      final data = await _supabase
          .from('group_members')
          .select('*, profiles(*)')
          .eq('group_id', groupId);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      print('Error en fetchGroupMembers: $e');
      throw Exception('Error al cargar miembros del grupo');
    }
  }

  Future<void> updateGroupMemberRole(String groupId, String userId, String newRole) async {
    try {
      await _supabase
          .from('group_members')
          .update({'role': newRole})
          .eq('group_id', groupId)
          .eq('user_id', userId);
    } catch (e) {
      print('Error en updateGroupMemberRole: $e');
      throw Exception('Error al actualizar el rango del miembro');
    }
  }

  Future<void> removeGroupMember(String groupId, String userId) async {
    try {
      await _supabase
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId);
    } catch (e) {
      print('Error en removeGroupMember: $e');
      throw Exception('Error al eliminar al miembro del grupo');
    }
  }

  Future<void> deleteGroupAnime(String groupId, int animeId) async {
    try {
      await _supabase
          .from('group_animes')
          .delete()
          .eq('group_id', groupId)
          .eq('anime_id', animeId);
    } catch (e) {
      print('Error en deleteGroupAnime: $e');
      throw Exception('Error al eliminar anime del grupo');
    }
  }


  Future<List<String>> fetchFriendshipIds() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from('friendships')
          .select('friend_id')
          .eq('user_id', user.id);
      
      return (data as List).map((f) => f['friend_id'] as String).toList();
    } catch (e) {
      print('Error en fetchFriendshipIds: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllPendingGroupRequests() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      // 1. Obtener los IDs de los grupos donde soy Líder o Moderador
      final myLeadRoles = await _supabase
          .from('group_members')
          .select('group_id')
          .eq('user_id', user.id)
          .inFilter('role', ['LÍDER', 'MODERADOR']);
      
      final groupIds = (myLeadRoles as List).map((g) => g['group_id'] as String).toList();
      if (groupIds.isEmpty) return [];

      // 2. Obtener todas las solicitudes pendientes para esos grupos
      final data = await _supabase
          .from('group_join_requests')
          .select('*, profile:profiles(*), group:groups(name, avatar_url)')
          .inFilter('group_id', groupIds)
          .eq('status', 'pending');
      
      return (data as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error en fetchAllPendingGroupRequests: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchGroupJoinRequests(String groupId) async {
    try {
      final data = await _supabase
          .from('group_join_requests')
          .select('*, profile:profiles(*)')
          .eq('group_id', groupId)
          .eq('status', 'pending');
      return (data as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error en fetchGroupJoinRequests: $e');
      return [];
    }
  }

  Future<void> handleGroupJoinRequest(String requestId, bool accept) async {
    try {
      final status = accept ? 'accepted' : 'rejected';
      
      // 1. Obtener la info de la solicitud
      final request = await _supabase.from('group_join_requests').select().eq('id', requestId).single();
      
      // 2. Actualizar estado
      await _supabase.from('group_join_requests').update({'status': status}).eq('id', requestId);
      
      // 3. Si se acepta, añadir al grupo
      if (accept) {
        await _supabase.from('group_members').insert({
          'group_id': request['group_id'],
          'user_id': request['user_id'],
          'role': 'MIEMBRO',
        });
      }
    } catch (e) {
      print('Error en handleGroupJoinRequest: $e');
      throw Exception('Error al procesar la solicitud');
    }
  }

  Future<void> deleteRating(String groupId, int animeId) async {
    try {
      final user = currentUser;
      if (user == null) return;

      // Borrar del grupo
      await _supabase.from('group_anime_ratings').delete()
          .eq('group_id', groupId)
          .eq('anime_id', animeId)
          .eq('user_id', user.id);

      // Borrar de reseñas personales
      await _supabase.from('reviews').delete()
          .eq('user_id', user.id)
          .eq('anime_id', animeId);
    } catch (e) {
      print('Error en deleteRating: $e');
      throw Exception('Error al eliminar tu puntuación');
    }
  }

  // CHAT GRUPAL
  Future<List<Map<String, dynamic>>> fetchGroupMessages(String groupId) async {
    try {
      final data = await _supabase
          .from('group_messages')
          .select('*, profile:profiles(username, avatar_url)')
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(50);
      
      return (data as List).map((e) => e as Map<String, dynamic>).toList().reversed.toList();
    } catch (e) {
      print('Error en fetchGroupMessages: $e');
      return [];
    }
  }

  Future<void> sendGroupMessage(String groupId, String content) async {
    try {
      final user = currentUser;
      if (user == null) return;

      await _supabase.from('group_messages').insert({
        'group_id': groupId,
        'user_id': user.id,
        'content': content,
      });

      // Limpieza: Mantener solo los últimos 50
      final countData = await _supabase
          .from('group_messages')
          .select('id')
          .eq('group_id', groupId)
          .order('created_at', ascending: false);
      
      if (countData.length > 50) {
        final toDelete = (countData as List).sublist(50);
        final idsToDelete = toDelete.map((e) => e['id']).toList();
        await _supabase.from('group_messages').delete().inFilter('id', idsToDelete);
      }
    } catch (e) {
      print('Error en sendGroupMessage: $e');
    }
  }

  RealtimeChannel subscribeToGroupMessages(String groupId, Function(Map<String, dynamic>) onMessage) {
    return _supabase.channel('group_chat_$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) async {
            final message = payload.newRecord;
            final userId = message['user_id'];
            final profile = await _supabase.from('profiles').select('username, avatar_url').eq('id', userId).single();
            message['profile'] = profile;
            onMessage(message);
          },
        )
        .subscribe();
  }

  // --- SISTEMA DE SINCRONIZACIÓN OFFLINE (FASE 4) ---

  final List<PendingAction> _pendingActions = [];
  bool _isSyncing = false;

  Future<void> _addPendingAction(String type, Map<String, dynamic> data) async {
    _pendingActions.add(PendingAction(
      type: type,
      data: data,
      timestamp: DateTime.now(),
    ));
    await _savePendingActions();
    print('Acción offline encolada: $type');
  }

  Future<void> _savePendingActions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> encoded = _pendingActions.map((a) => jsonEncode(a.toMap())).toList();
      await prefs.setStringList('pending_actions_queue', encoded);
    } catch (e) {
      print('Error guardando cola de acciones: $e');
    }
  }

  Future<void> _loadPendingActions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? data = prefs.getStringList('pending_actions_queue');
      if (data != null) {
        _pendingActions.clear();
        _pendingActions.addAll(data.map((s) => PendingAction.fromMap(jsonDecode(s))));
        print('Cola de acciones cargada: ${_pendingActions.length} pendientes');
      }
    } catch (e) {
      print('Error cargando cola de acciones: $e');
    }
  }

  Future<void> _syncPendingActions() async {
    if (_isSyncing || _pendingActions.isEmpty) return;
    _isSyncing = true;
    print('Iniciando sincronización de ${_pendingActions.length} acciones...');

    final List<PendingAction> toRemove = [];

    for (var action in List.from(_pendingActions)) {
      bool success = false;
      try {
        switch (action.type) {
          case 'UPDATE_STATUS':
            await updateUserListStatus(
              action.data['anime_id'], 
              action.data['status'], 
              episodes: action.data['episodes'] ?? 0,
              forceOnline: true
            );
            success = true;
            break;
          case 'TOGGLE_FAVORITE':
            await toggleFavorite(action.data['anime_id'], forceOnline: true);
            success = true;
            break;
          case 'ADD_REVIEW':
            await addReview(
              action.data['anime_id'],
              action.data['rating'],
              action.data['opinion'],
              forceOnline: true
            );
            success = true;
            break;
        }
      } catch (e) {
        print('Fallo al sincronizar acción ${action.type}: $e');
      }

      if (success) {
        toRemove.add(action);
      }
    }

    _pendingActions.removeWhere((a) => toRemove.contains(a));
    await _savePendingActions();
    _isSyncing = false;
    print('Sincronización finalizada. Quedan: ${_pendingActions.length}');
  }
}

class PendingAction {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  PendingAction({required this.type, required this.data, required this.timestamp});

  Map<String, dynamic> toMap() => {
    'type': type,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };

  factory PendingAction.fromMap(Map<String, dynamic> map) => PendingAction(
    type: map['type'],
    data: map['data'],
    timestamp: DateTime.parse(map['timestamp']),
  );
}
