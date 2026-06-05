class Anime {
  final int malId;
  final String title;
  final String? titleRomaji;
  final String imageUrl;
  final double score;
  final String synopsis;
  final String status;
  final List<String> genres;
  final String demographic;
  final int year;
  final int episodes;
  final String? myStatus;
  final double? myRating;
  final bool isFavorite;

  Anime({
    required this.malId,
    required this.title,
    this.titleRomaji,
    required this.imageUrl,
    required this.score,
    required this.synopsis,
    required this.status,
    required this.genres,
    required this.demographic,
    required this.year,
    required this.episodes,
    this.myStatus,
    this.myRating,
    this.isFavorite = false,
  });

  factory Anime.fromMap(Map<String, dynamic> map) {
    // Manejo de géneros (ahora vienen como array de Supabase)
    List<String> genreList = [];
    if (map['genres'] != null) {
      if (map['genres'] is List) {
        genreList = List<String>.from(map['genres']);
      } else {
        // Fallback por si acaso siguen viniendo como string (migración)
        genreList = (map['genres'] as String).split(',').map((e) => e.trim()).toList();
      }
    }

    return Anime(
      malId: map['mal_id'] ?? map['id'] ?? 0,
      title: map['title'] ?? 'Unknown',
      titleRomaji: map['title_romaji'] ?? map['titleRomaji'],
      imageUrl: map['image_url'] ?? '',
      score: (map['score'] ?? 0.0).toDouble(),
      synopsis: map['synopsis'] ?? '',
      status: map['status'] ?? 'Desconocido',
      genres: genreList,
      demographic: map['demographic'] ?? 'Shonen',
      year: map['release_year'] ?? 2024,
      episodes: map['episodes'] ?? 0,
      myStatus: map['my_status'], // Solo del campo directo si existe
      myRating: (map['my_rating'] as num?)?.toDouble(),
      isFavorite: map['is_favorite'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mal_id': malId,
      'title': title,
      'title_romaji': titleRomaji,
      'image_url': imageUrl,
      'score': score,
      'synopsis': synopsis,
      'status': status,
      'genres': genres,
      'demographic': demographic,
      'release_year': year,
      'episodes': episodes,
    };
  }

  Map<String, dynamic> toMap() => toJson();

  Anime copyWith({
    int? malId,
    String? title,
    String? titleRomaji,
    String? imageUrl,
    double? score,
    String? synopsis,
    String? status,
    List<String>? genres,
    String? demographic,
    int? year,
    int? episodes,
    String? myStatus,
    double? myRating,
    bool? isFavorite,
  }) {
    return Anime(
      malId: malId ?? this.malId,
      title: title ?? this.title,
      titleRomaji: titleRomaji ?? this.titleRomaji,
      imageUrl: imageUrl ?? this.imageUrl,
      score: score ?? this.score,
      synopsis: synopsis ?? this.synopsis,
      status: status ?? this.status,
      genres: genres ?? this.genres,
      demographic: demographic ?? this.demographic,
      year: year ?? this.year,
      episodes: episodes ?? this.episodes,
      myStatus: myStatus ?? this.myStatus,
      myRating: myRating ?? this.myRating,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
