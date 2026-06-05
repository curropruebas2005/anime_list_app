import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:typed_data';
import 'dart:convert';
import '../theme.dart';
import '../utils/image_utils.dart';
import '../widgets/web_safe_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/anime_repository.dart';
import '../screens/profile_screen.dart';

class GlobalAppBar extends StatefulWidget implements PreferredSizeWidget {
  final Widget titleWidget;
  
  const GlobalAppBar({super.key, required this.titleWidget});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  State<GlobalAppBar> createState() => _GlobalAppBarState();
}

class _GlobalAppBarState extends State<GlobalAppBar> {
  Map<String, dynamic>? _profile;
  Uint8List? _avatarBytes;
  final _animeRepo = AnimeRepository();

  @override
  void initState() {
    super.initState();
    // Cargamos primero de la memoria rápida para evitar parpadeos
    _profile = _animeRepo.cachedProfile;
    _updateAvatarBytes();
    _loadProfile();
    // Escuchamos cambios globales en el perfil
    _animeRepo.profileUpdateNotifier.addListener(_loadProfile);
  }

  @override
  void dispose() {
    // Es vital quitar el listener al cerrar la pantalla
    _animeRepo.profileUpdateNotifier.removeListener(_loadProfile);
    super.dispose();
  }

  void _updateAvatarBytes() {
    final avatarUrl = _profile?['avatar_url']?.toString();
    if (avatarUrl != null && (avatarUrl.startsWith('data:image') || avatarUrl.length > 200)) {
      try {
        final base64String = avatarUrl.contains(',') ? avatarUrl.split(',').last : avatarUrl;
        _avatarBytes = base64Decode(base64String);
      } catch (_) {
        _avatarBytes = null;
      }
    } else {
      _avatarBytes = null;
    }
  }

  Future<void> _loadProfile() async {
    final profile = await _animeRepo.getCurrentUserProfile();
    if (mounted && profile != null) {
      // Solo actualizamos si realmente hay un cambio para evitar parpadeos de re-renderizado
      if (_profile == null || 
          _profile!['avatar_url'] != profile['avatar_url'] || 
          _profile!['username'] != profile['username'] ||
          _profile!['full_name'] != profile['full_name']) {
        setState(() {
          _profile = profile;
          _updateAvatarBytes();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final username = _profile?['username']?.toString().isNotEmpty == true ? _profile!['username'] : user?.userMetadata?['username'];
    final fullName = _profile?['full_name']?.toString().isNotEmpty == true ? _profile!['full_name'] : user?.userMetadata?['full_name'];
    
    // Priorizamos el Nombre Público (Full Name) para ser coherentes con el perfil
    final displayName = fullName ?? username ?? user?.email?.split('@')[0] ?? 'Usuario';
    final String? profileAvatar = (_profile?['avatar_url']?.toString().isNotEmpty == true) ? _profile!['avatar_url'] : null;
    final String? metaAvatar = (user?.userMetadata?['avatar_url']?.toString().isNotEmpty == true) ? user!.userMetadata!['avatar_url'] :
                              (user?.userMetadata?['picture']?.toString().isNotEmpty == true) ? user!.userMetadata!['picture'] :
                              (user?.userMetadata?['avatar']?.toString().isNotEmpty == true) ? user!.userMetadata!['avatar'] :
                              (user?.userMetadata?['photo']?.toString().isNotEmpty == true) ? user!.userMetadata!['photo'] : null;
                             
    // Si tenemos algo en el perfil (disco/cache), MANDAMOS ese y bloqueamos el de metadatos (que suele estar obsoleto)
    final avatarUrl = profileAvatar ?? metaAvatar;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.7),
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
          title: widget.titleWidget,
          actions: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              child: Row(
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Plus Jakarta Sans',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    margin: const EdgeInsets.only(right: 16),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primary, width: 1.5),
                    ),
                    child: WebSafeImage(
                      url: wrapImageProxy(avatarUrl ?? "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp&f=y"),
                      imageBytes: _avatarBytes,
                      borderRadius: BorderRadius.circular(19),
                      useFadeIn: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
