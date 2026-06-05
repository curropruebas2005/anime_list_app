import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import '../theme.dart';
import '../models/anime.dart';
import 'login_screen.dart';
import 'anime_detail_screen.dart';
import '../repositories/anime_repository.dart';
import '../utils/image_utils.dart';
import '../widgets/web_safe_image.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  final _animeRepo = AnimeRepository();
  bool _isLoading = true;
  List<Anime> _favorites = [];
  List<Anime> _recentActivity = [];
  int _totalVistos = 0;
  int _totalCapitulos = 0;

  final List<String> _animeAvatars = [
    'https://i.pinimg.com/736x/2b/24/09/2b240974719c28893113540d99516625.jpg', // Luffy
    'https://i.pinimg.com/736x/8f/33/c4/8f33c46a89c9a59530e466487e38e137.jpg', // Zoro
    'https://i.pinimg.com/736x/df/79/11/df79116e036d07d9f95889e4776104f6.jpg', // Naruto
    'https://i.pinimg.com/736x/82/3a/04/823a042e979a4de5e4787d558b356bb5.jpg', // Sasuke
    'https://i.pinimg.com/736x/91/92/79/9192797746199f36f966d56d1c2a13cc.jpg', // Goku
    'https://i.pinimg.com/736x/55/0f/2d/550f2d486aa789c676059d08e5c3e72c.jpg', // Tanjiro
    'https://i.pinimg.com/736x/88/53/7c/88537c62c3f7654afbc140f7d56e0743.jpg', // Nezuko
    'https://i.pinimg.com/736x/3b/6a/0c/3b6a0c0e7cd881e79391b8d608938d2f.jpg', // Deku
    'https://i.pinimg.com/736x/60/9e/7b/609e7bab6029279c6b986cc2a0885e33.jpg', // Saitama
    'https://i.pinimg.com/736x/8b/7c/4a/8b7c4a03440e34b9d07399818ae9165d.jpg', // Anya Forger
  ];

  List<Map<String, String>> _catalogAvatars = [];

  @override
  void initState() {
    super.initState();
    // Cargamos de la memoria rápida SOLO si es mi propio perfil
    if (_isMe) {
      _profile = _animeRepo.cachedProfile;
      _isLoading = (_profile == null); 
    } else {
      _isLoading = true;
    }
    
    _loadAllData();
    // Escuchamos cambios globales en el perfil
    _animeRepo.profileUpdateNotifier.addListener(_loadAllData);
  }

  @override
  void dispose() {
    _animeRepo.profileUpdateNotifier.removeListener(_loadAllData);
    super.dispose();
  }

  bool get _isMe => widget.userId == null || widget.userId == _animeRepo.currentUser?.id;

  Future<void> _loadAllData() async {
    final effectiveUserId = widget.userId ?? _animeRepo.currentUser?.id;
    final supabase = Supabase.instance.client;
    
    if (mounted) {
      setState(() {
        if (!_isMe) {
          _profile = null;
          _favorites = [];
          _recentActivity = [];
          _totalVistos = 0;
          _totalCapitulos = 0;
        }
        _isLoading = true;
      });
    }

    // Carga instantánea desde caché si es mi perfil y tenemos los datos
    if (_isMe) {
      _profile = _animeRepo.cachedProfile; // Cargar perfil de disco/memoria ya!
      if (AnimeRepository.cachedUserStats != null) {
        final cachedStats = AnimeRepository.cachedUserStats!;
        _totalVistos = cachedStats['vistos'] ?? 0;
        _totalCapitulos = cachedStats['capitulos'] ?? 0;
        _favorites = AnimeRepository.cachedFavorites ?? [];
        _recentActivity = AnimeRepository.cachedRecentActivity ?? [];
        _isLoading = false; // Ya podemos mostrar algo
      }
    }

    final results = await Future.wait<dynamic>([
      widget.userId != null 
        ? supabase.from('profiles').select().eq('id', widget.userId!).single()
        : _animeRepo.getCurrentUserProfile(),
      _animeRepo.fetchFavorites(userId: effectiveUserId),
      _animeRepo.fetchRecentActivity(userId: effectiveUserId),
      _animeRepo.fetchUserStats(userId: effectiveUserId),
      _animeRepo.fetchAvatarCatalog(),
    ]);

    if (mounted) {
      final stats = results[3] as Map<String, int>;
      final catalog = results[4] as List<Map<String, String>>;
      final newProfile = results[0] as Map<String, dynamic>?;
      
      // Evitar parpadeo si los datos de perfil son idénticos
      bool profileChanged = _profile == null || 
          (newProfile != null && (newProfile['avatar_url'] != _profile!['avatar_url'] || 
                                  newProfile['username'] != _profile!['username']));

      setState(() {
        if (profileChanged) _profile = newProfile;
        _favorites = results[1] as List<Anime>;
        _recentActivity = results[2] as List<Anime>;
        _totalVistos = stats['vistos'] ?? 0;
        _totalCapitulos = stats['capitulos'] ?? 0;
        _catalogAvatars = catalog;
        _isLoading = false;
      });
    }
  }

  void _showAvatarPicker() {
    final user = Supabase.instance.client.auth.currentUser;
    final String? socialUrl = user?.userMetadata?['avatar_url'] ?? 
                             user?.userMetadata?['picture'] ?? 
                             user?.userMetadata?['avatar'] ?? 
                             user?.userMetadata?['photo'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 24),
            const Text('Elige tu Avatar', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Plus Jakarta Sans')),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: 1 + (_catalogAvatars.isNotEmpty ? _catalogAvatars.length : _animeAvatars.length),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 300,
                          maxHeight: 300,
                          imageQuality: 50,
                        );
                        
                        if (image != null && mounted) {
                          Navigator.pop(context);
                          setState(() => _isLoading = true);
                          try {
                            final bytes = await image.readAsBytes();
                            final base64Image = 'data:image/png;base64,${base64Encode(bytes)}';
                            await _animeRepo.updateProfile(avatarUrl: base64Image);
                            _loadAllData();
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                            setState(() => _isLoading = false);
                          }
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.primary.withOpacity(0.5), width: 2),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_rounded, color: AppTheme.primary, size: 32),
                            SizedBox(height: 4),
                            Text("GALERÍA", style: TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  }

                  final adjustedIndex = index - 1;
                  final avatarUrl = wrapImageProxy(_catalogAvatars.isNotEmpty 
                      ? _catalogAvatars[adjustedIndex]['url']! 
                      : _animeAvatars[adjustedIndex]);
                      
                  return GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      setState(() => _isLoading = true);
                      try {
                        await _animeRepo.updateProfile(avatarUrl: avatarUrl);
                        _loadAllData();
                      } catch (e) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                         setState(() => _isLoading = false);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: WebSafeImage(
                        url: avatarUrl,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final userEmail = user?.email ?? 'invitado@tomodachi.com';
    
    final username = _profile?['username']?.toString().isNotEmpty == true ? _profile!['username'] : user?.userMetadata?['username'];
    final fullName = _profile?['full_name']?.toString().isNotEmpty == true ? _profile!['full_name'] : user?.userMetadata?['full_name'];
    
    // El nombre grande ahora es el Full Name por defecto (Nombre Público)
    final displayName = fullName ?? username ?? userEmail.split('@')[0];
                         
    final String? profileAvatar = (_profile?['avatar_url']?.toString().isNotEmpty == true) ? _profile!['avatar_url'] : null;
    final String? metaAvatar = (user?.userMetadata?['avatar_url']?.toString().isNotEmpty == true) ? user!.userMetadata!['avatar_url'] :
                              (user?.userMetadata?['picture']?.toString().isNotEmpty == true) ? user!.userMetadata!['picture'] :
                              (user?.userMetadata?['avatar']?.toString().isNotEmpty == true) ? user!.userMetadata!['avatar'] :
                              (user?.userMetadata?['photo']?.toString().isNotEmpty == true) ? user!.userMetadata!['photo'] : null;
                             
    final avatarUrl = profileAvatar ?? metaAvatar ?? "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp&f=y";

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Mi Perfil', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.w900, color: AppTheme.primary)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.primary, width: 2),
                                boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.2), blurRadius: 15)],
                              ),
                              child: WebSafeImage(
                                url: wrapImageProxy(avatarUrl),
                                borderRadius: BorderRadius.circular(40),
                              ),
                            ),
                            if (_isMe && _profile != null) Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _showAvatarPicker,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.edit_rounded, color: Colors.black, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName, 
                                style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (username != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  "@$username", 
                                  style: TextStyle(color: AppTheme.primary.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w600)
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(userEmail, style: TextStyle(color: AppTheme.onSurfaceVariant.withOpacity(0.7), fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                _buildHorizontalSection('MIS FAVORITOS', _favorites),
                
                const SizedBox(height: 24),

                // Recent Activity Section
                _buildHorizontalSection('ACTIVIDAD RECIENTE', _recentActivity),

                const SizedBox(height: 32),
                
                // Settings Section
                if (_isMe) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.1)),
                      ),
                      child: Column(
                        children: [
                          _buildSettingsTile(context, Icons.account_circle, 'Mi Cuenta', onTap: () => _showAccountModal(context)),
                          const Divider(height: 1),
                          _buildSettingsTile(context, Icons.language, 'Idioma', trailing: 'Español'),
                          const Divider(height: 1),
                          ListenableBuilder(
                            listenable: themeProvider,
                            builder: (context, _) => SwitchListTile(
                              activeColor: AppTheme.primary,
                              secondary: Icon(Icons.dark_mode, color: themeProvider.isDarkMode ? AppTheme.primary : AppTheme.onSurfaceVariant),
                              title: const Text('Modo Oscuro', style: TextStyle(fontWeight: FontWeight.w600)),
                              value: themeProvider.isDarkMode,
                              onChanged: (bool value) {
                                themeProvider.toggleTheme(value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Logout Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          backgroundColor: Colors.red.withOpacity(0.05),
                        ),
                        icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                        label: const Text('Cerrar Sesión', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          _animeRepo.clearCache();
                          await Supabase.instance.client.auth.signOut();
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
                          }
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 48),
              ],
            ),
          ),
    );
  }

  Widget _buildHorizontalSection(String title, List<Anime> animes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: AppTheme.primary)),
        ),
        const SizedBox(height: 16),
        if (animes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('Aún no hay nada aquí...', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5))),
          )
        else
          SizedBox(
            height: 180,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: animes.length,
              itemBuilder: (context, index) {
                final anime = animes[index];
                return GestureDetector(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)));
                    _loadAllData(); // Refresh on back
                  },
                  child: Container(
                    width: 110,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WebSafeImage(
                          url: anime.imageUrl,
                          height: 140,
                          width: 110,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        const SizedBox(height: 8),
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

  void _showAccountModal(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final fullNameController = TextEditingController(text: _profile?['full_name'] ?? user?.userMetadata?['full_name']);
    final usernameController = TextEditingController(text: _profile?['username'] ?? user?.userMetadata?['username']);
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
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
              const Text('Mi Cuenta', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Text('Correo Electrónico', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7), fontSize: 12)),
              const SizedBox(height: 8),
              Text(user?.email ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: fullNameController,
                decoration: AppTheme.inputDecoration('Nombre Público (Grande)', Icons.person_outline),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameController,
                readOnly: true, // El @ no se cambia por ahora
                enabled: false,
                decoration: AppTheme.inputDecoration('Nombre de Usuario (@)', Icons.alternate_email).copyWith(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              ),
              const SizedBox(height: 24),
              // Solo mostrar cambio de contraseña si no es Google
              if (user?.appMetadata['provider'] != 'google') ...[
                const Divider(),
                const SizedBox(height: 12),
                const Text('Cambiar Contraseña', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña actual', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Nueva contraseña', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isSaving ? null : () async {
                    setModalState(() => isSaving = true);
                    try {
                      // 1. Update Profile (Only Full Name)
                      await _animeRepo.updateProfile(
                        fullName: fullNameController.text,
                        // El username no lo enviamos porque es solo lectura
                      );
                      
                      // 2. Change Password if requested
                      if (newPasswordController.text.isNotEmpty) {
                        // We check old password by attempting sign in
                        try {
                          await Supabase.instance.client.auth.signInWithPassword(
                            email: user!.email!,
                            password: oldPasswordController.text,
                          );
                          await _animeRepo.changePassword(newPasswordController.text);
                        } catch (e) {
                          throw Exception('Contraseña actual incorrecta o error al cambiarla');
                        }
                      }
                      
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cuenta actualizada correctamente')));
                        _loadAllData();
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red));
                    } finally {
                      setModalState(() => isSaving = false);
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Guardar cambios', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.neonCyan)),
        Text(label.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, {String? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primary.withOpacity(0.8)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) Text(trailing, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 13)),
          if (trailing != null) const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
        ],
      ),
      onTap: onTap,
    );
  }
}
