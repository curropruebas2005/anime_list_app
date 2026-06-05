import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/anime.dart';

/// Servicio encargado de gestionar las peticiones directas de animes a Supabase.
class AnimeService {
  // Instancia única y compartida (Singleton) del cliente de Supabase.
  final _supabase = Supabase.instance.client;

  /// Obtiene la lista completa de animes registrados en la tabla 'animes' de Supabase.
  Future<List<Anime>> fetchAnimes() async {
    try {
      // Lanza una consulta SELECT básica sobre la tabla 'animes'.
      final data = await _supabase.from('animes').select();
      
      // Mapea directamente el listado de filas en formato JSON a objetos de la clase Anime.
      return data.map((json) => Anime.fromMap(json)).toList();
    } catch (e) {
      throw Exception('Error al recuperar los animes desde el servidor: $e');
    }
  }

  /// Añade un anime específico a la tabla de 'favorites' vinculándolo al usuario actual.
  Future<void> addAnimeToFavorites(String animeId) async {
    try {
      // Recupera de forma segura el ID del usuario autenticado actualmente en la sesión de Supabase.
      final userId = _supabase.auth.currentUser?.id;
      
      // Control de seguridad: Si no hay usuario logueado en la sesión local, se aborta la operación.
      if (userId == null) {
        throw Exception('Operación no permitida: El usuario no ha iniciado sesión.');
      }

      // Inserta una nueva fila de relación en la tabla relacional 'favorites'.
      await _supabase.from('favorites').insert({
        'user_id': userId,
        'anime_id': animeId,
        'created_at': DateTime.now().toIso8601String(), // Guarda la fecha y hora de creación en formato estándar ISO 8601.
      });
    } catch (e) {
      throw Exception('Fallo al añadir el anime a favoritos en el servidor: $e');
    }
  }
}
