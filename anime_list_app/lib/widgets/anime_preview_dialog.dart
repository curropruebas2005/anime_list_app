import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/anime.dart';
import 'web_safe_image.dart';
import '../theme.dart';
import '../screens/anime_detail_screen.dart';

class AnimePreviewDialog extends StatelessWidget {
  final Anime anime;

  const AnimePreviewDialog({super.key, required this.anime});

  /// Muestra el modal de vista previa del anime con vibración háptica
  static void show(BuildContext context, Anime anime) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AnimePreviewDialog(anime: anime),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Colores basados en el tema
    final backgroundColor = isDark 
        ? const Color(0xFF1E1E2E).withOpacity(0.9) 
        : Colors.white.withOpacity(0.9);
    final borderColor = isDark 
        ? Colors.white.withOpacity(0.1) 
        : Colors.black.withOpacity(0.08);
    final textColor = theme.colorScheme.onSurface;
    final secondaryTextColor = theme.colorScheme.onSurfaceVariant.withOpacity(0.7);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.5 : 0.15),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabecera con título e icono de cerrar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Vista Rápida",
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: textColor.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Fila Principal: Portada + Detalles
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Portada del anime
                        Hero(
                          tag: 'preview-${anime.malId}',
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: WebSafeImage(
                              url: anime.imageUrl,
                              width: 100,
                              height: 145,
                              borderRadius: BorderRadius.circular(16),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Detalles textuales
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Puntuación
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                                  const SizedBox(width: 4),
                                  Text(
                                    anime.score.toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(anime.status).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      anime.status.toUpperCase(),
                                      style: TextStyle(
                                        color: _getStatusColor(anime.status),
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Metadatos rápidos (Icono + Texto)
                              _buildMetadataRow(
                                context,
                                icon: Icons.calendar_month_rounded,
                                text: 'Año de lanzamiento: ${anime.year}',
                                isDark: isDark,
                              ),
                              const SizedBox(height: 4),
                              _buildMetadataRow(
                                context,
                                icon: Icons.local_play_rounded,
                                text: 'Episodios: ${anime.episodes == 0 ? "En emisión / Sin especificar" : anime.episodes}',
                                isDark: isDark,
                              ),
                              const SizedBox(height: 4),
                              _buildMetadataRow(
                                context,
                                icon: Icons.people_outline_rounded,
                                text: 'Público: ${anime.demographic}',
                                isDark: isDark,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // TÍTULO ENTERO (Se muestra sin cortes ni truncado)
                    Text(
                      anime.title,
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.25,
                      ),
                    ),
                    if (anime.titleRomaji != null && anime.titleRomaji != anime.title) ...[
                      const SizedBox(height: 4),
                      Text(
                        anime.titleRomaji!,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // GÉNEROS
                    if (anime.genres.isNotEmpty) ...[
                      Text(
                        "Géneros",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textColor.withOpacity(0.4),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: anime.genres.map((genre) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                              ),
                            ),
                            child: Text(
                              genre,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: textColor.withOpacity(0.8),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // BOTÓN DE ACCIÓN (Ver detalles completos)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(context); // Cerrar el diálogo
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AnimeDetailScreen(anime: anime),
                                ),
                              );
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.info_outline_rounded, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  "Ver Detalles Completos",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataRow(
    BuildContext context, {
    required IconData icon,
    required String text,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(
          icon, 
          size: 16, 
          color: isDark ? Colors.white.withOpacity(0.35) : Colors.black.withOpacity(0.35),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('finalizado') || s.contains('finished') || s.contains('completed')) {
      return const Color(0xFF00E676); // Verde brillante
    }
    if (s.contains('emisión') || s.contains('airing') || s.contains('publishing')) {
      return const Color(0xFF0288D1); // Azul brillante
    }
    return const Color(0xFFFFB300); // Ámbar
  }
}
