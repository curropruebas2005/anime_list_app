import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/anime.dart';
import '../widgets/web_safe_image.dart';
import '../utils/image_utils.dart';
import 'anime_detail_screen.dart';
import 'user_profile_screen.dart';

class FullActivityScreen extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final String type; // 'activity' o 'review'

  const FullActivityScreen({
    super.key,
    required this.title,
    required this.items,
    required this.type,
  });

  @override
  State<FullActivityScreen> createState() => _FullActivityScreenState();
}

class _FullActivityScreenState extends State<FullActivityScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_searchQuery.isEmpty) return widget.items;
    return widget.items.where((item) {
      final profile = item['profile'] as Map<String, dynamic>;
      final fullName = (profile['full_name'] as String?)?.toLowerCase() ?? "";
      final username = (profile['username'] as String?)?.toLowerCase() ?? "";
      return fullName.contains(_searchQuery) || username.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _filteredItems;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Buscador
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar por amigo...',
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.primary),
                suffixIcon: _searchQuery.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Colors.white60),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          
          Expanded(
            child: filteredItems.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty ? "No hay ${widget.title.toLowerCase()}" : "No se encontraron resultados",
                      style: const TextStyle(color: Colors.white30),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      final profile = item['profile'] as Map<String, dynamic>;
                      final anime = item['animes'] as Map<String, dynamic>;
                      final name = profile['full_name'] ?? profile['username'] ?? 'Usuario';
                      final imageUrl = profile['avatar_url'] ?? '';
                      final animeImageUrl = anime['image_url'] ?? '';

                      if (widget.type == 'activity') {
                        return _buildActivityRow(
                          context: context,
                          name: name,
                          animeTitle: anime['title'],
                          status: item['status'],
                          episode: item['episodes_watched'],
                          imageUrl: imageUrl,
                          animeImageUrl: animeImageUrl,
                          profile: profile,
                          animeMap: anime,
                        );
                      } else {
                        return _buildReviewCard(
                          context: context,
                          name: name,
                          animeTitle: anime['title'],
                          rating: (item['rating'] as num).toDouble(),
                          opinion: item['opinion'] ?? '',
                          imageUrl: imageUrl,
                          animeImageUrl: animeImageUrl,
                          profile: profile,
                          animeMap: anime,
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityRow({
    required BuildContext context,
    required String name,
    required String animeTitle,
    required String status,
    required int episode,
    required String imageUrl,
    required String animeImageUrl,
    required Map<String, dynamic> profile,
    required Map<String, dynamic> animeMap,
  }) {
    String actionStr = status == 'Viendo' ? 'está viendo' : 'ha terminado';
    String detailStr = status == 'Viendo' ? 'Episodio $episode' : '¡Visto!';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: profile))),
            child: WebSafeImage(url: wrapImageProxy(imageUrl), width: 36, height: 36, borderRadius: BorderRadius.circular(18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    children: [
                      TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: " $actionStr ", style: const TextStyle(color: Colors.white70)),
                      TextSpan(text: animeTitle, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detailStr,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: Anime.fromMap(animeMap)))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: WebSafeImage(url: wrapImageProxy(animeImageUrl), width: 32, height: 44, fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard({
    required BuildContext context,
    required String name,
    required String animeTitle,
    required double rating,
    required String opinion,
    required String imageUrl,
    required String animeImageUrl,
    required Map<String, dynamic> profile,
    required Map<String, dynamic> animeMap,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: profile))),
                child: WebSafeImage(url: wrapImageProxy(imageUrl), width: 28, height: 28, borderRadius: BorderRadius.circular(14)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: profile))),
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      children: [
                        TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(text: " ha valorado ", style: TextStyle(color: Colors.white70)),
                        TextSpan(text: animeTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: Anime.fromMap(animeMap)))),
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
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.white70),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
