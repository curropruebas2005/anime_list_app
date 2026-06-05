import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../repositories/anime_repository.dart';
import '../models/anime.dart';
import '../theme.dart';
import '../widgets/web_safe_image.dart';
import '../utils/image_utils.dart';
import 'profile_screen.dart';
import 'user_profile_screen.dart';
import 'anime_detail_screen.dart';
import 'dart:async';
import 'dart:typed_data';

class GroupDetailScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;
  final _animeRepo = AnimeRepository();
  bool _isLoading = true;
  List<Map<String, dynamic>> _groupAnimes = [];
  List<Map<String, dynamic>> _members = [];
  int _memberCount = 0;
  String? _stableAvatarUrl;
  Uint8List? _avatarBytes;
  List<Map<String, dynamic>> _pendingRequests = [];
  Map<String, dynamic>? _groupData;
  List<String> _friendIds = [];
  Map<String, Uint8List> _avatarByteCache = {}; // Caché para fotos de miembros/solicitudes
  String _myRole = 'member';
  Map<String, Map<String, dynamic>> _memberProfileMap = {}; 
  bool _isFavorite = false;
  bool _isMember = false;

  bool get _canModerate => _isAdmin;

  // CHAT STATE
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _chatChannel;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  void _updateAvatarBytes(String? urlOrBase64) {
    if (urlOrBase64 == null || urlOrBase64.isEmpty) {
      _avatarBytes = null;
      return;
    }
    if (urlOrBase64.startsWith('data:image') || (urlOrBase64.length > 200 && !urlOrBase64.contains('.'))) {
      try {
        String base64String = urlOrBase64.startsWith('data:image') ? urlOrBase64.split(',').last : urlOrBase64;
        _avatarBytes = base64Decode(base64String);
      } catch (e) {
        _avatarBytes = null;
      }
    } else {
      _avatarBytes = null;
    }
  }

  void _updateCacheForList(List list, String urlKey) {
    for (var item in list) {
      // Si la estructura es anidada (ej: member['profiles']['avatar_url'])
      dynamic data = item;
      if (item['profiles'] != null) data = item['profiles'];
      if (item['profile'] != null) data = item['profile'];

      String? url = data[urlKey];
      if (url != null && url.isNotEmpty) {
        if (url.startsWith('data:image') || (url.length > 200 && !url.contains('.'))) {
          if (!_avatarByteCache.containsKey(url)) {
            try {
              String base64String = url.startsWith('data:image') ? url.split(',').last : url;
              _avatarByteCache[url] = base64Decode(base64String);
            } catch (_) {}
          }
        } else {
          // Es una URL real, precacherla por si acaso
          precacheImage(getImageProvider(url), context).catchError((_) => null);
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Inicializar con los valores 'initial' pasados desde la lista para evitar parpadeos
    // Inicializar membresía según lo que venga de la lista
    _isMember = widget.group['isMember'] ?? true;
    _myRole = widget.group['initial_role'] ?? (_isMember ? 'member' : 'none');
    _isFavorite = widget.group['initial_is_favorite'] == true;
    _memberCount = widget.group['initial_member_count'] ?? 0;
    _stableAvatarUrl = widget.group['avatar_url'];
    _updateAvatarBytes(_stableAvatarUrl);
    
    _tabController = TabController(length: _isMember ? 3 : 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        HapticFeedback.selectionClick();
      }
      setState(() {});
    });
    _loadData();
    _animeRepo.profileUpdateNotifier.addListener(_loadDataShort);
    if (_isMember) _initChat();
  }

  void _loadDataShort() => _loadData(showLoader: false);

  void _initChat() async {
    // 1. Cargar mensajes iniciales
    final msgs = await _animeRepo.fetchGroupMessages(widget.group['id']);
    setState(() {
      _messages = msgs;
    });

    // 2. Suscribirse a tiempo real
    _chatChannel = _animeRepo.subscribeToGroupMessages(widget.group['id'], (newMsg) {
      if (mounted) {
        setState(() {
          _messages.add(newMsg);
        });
        _scrollToBottom();
      }
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precargar avatar del grupo para evitar parpadeo
    final avatarUrl = widget.group['avatar_url'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      precacheImage(getImageProvider(avatarUrl), context);
    }
    // También precargar la imagen del _groupData si ya existe para evitar cortes
    if (_groupData != null && _groupData!['avatar_url'] != null) {
       precacheImage(getImageProvider(_groupData!['avatar_url']), context);
    }
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _animeRepo.fetchGroupAnimes(widget.group['id']),
        _animeRepo.fetchGroupMembers(widget.group['id']),
        _animeRepo.fetchFriendshipIds(),
        _animeRepo.fetchGroupById(widget.group['id']),
      ]);

      setState(() {
        _groupAnimes = results[0] as List<Map<String, dynamic>>;
        _members = results[1] as List<Map<String, dynamic>>;
        _friendIds = results[2] as List<String>;
        _groupData = results[3] as Map<String, dynamic>?;

        // Actualizar caché de bytes para miembros y solicitudes
        _updateCacheForList(_members, 'avatar_url');
        _updateCacheForList(_pendingRequests, 'avatar_url');

        // Solo actualizar la foto si la nueva es válida y distinta
        final newAvatar = _groupData?['avatar_url'];
        if (newAvatar != null && newAvatar.isNotEmpty && newAvatar != _stableAvatarUrl) {
          _stableAvatarUrl = newAvatar;
          _updateAvatarBytes(_stableAvatarUrl);
        }

        // Actualizar el conteo real desde los datos frescos
        if (_groupData != null && _groupData!['group_members'] != null) {
          final gm = _groupData!['group_members'] as List;
          if (gm.isNotEmpty) {
            _memberCount = gm[0]['count'] ?? _members.length;
          } else {
            _memberCount = _members.length;
          }
        } else {
          _memberCount = _members.length;
        }
        
        // Crear mapa de perfiles para el chat
        _memberProfileMap = {
          for (var m in _members) m['user_id'].toString(): m['profiles'] as Map<String, dynamic>
        };
        
        // Ordenar miembros por jerarquía: LÍDER > MODERADORES > MIEMBROS
        _members.sort((a, b) {
          int getPriority(String r) {
            r = r.toUpperCase().trim();
            if (r == 'LÍDER' || r == 'ADMIN' || r == 'LIDER' || r == 'LEADER') return 0;
            if (r == 'MODERADOR' || r == 'MODERATOR') return 1;
            return 2;
          }
          return getPriority(a['role'] ?? '').compareTo(getPriority(b['role'] ?? ''));
        });
        
        // Detectar mi rol y si soy miembro
        final currentUserId = _animeRepo.currentUser?.id;
        final meIndex = _members.indexWhere((m) => m['user_id'] == currentUserId);
        
        final bool wasMember = _isMember;
        if (meIndex != -1) {
          final me = _members[meIndex];
          _isMember = true;
          _myRole = me['role'] ?? 'member';
          _isFavorite = me['is_favorite'] == true;
        } else {
          _isMember = false;
          _myRole = 'none';
          _isFavorite = false;
        }

        // Si el estado de membresía cambió, tenemos que regenerar el TabController
        if (wasMember != _isMember) {
          int oldIndex = _tabController.index;
          _tabController.dispose();
          _tabController = TabController(
            length: _isMember ? 3 : 2, 
            vsync: this,
            initialIndex: oldIndex.clamp(0, (_isMember ? 3 : 2) - 1)
          );
          _tabController.addListener(() => setState(() {}));
          if (_isMember) _initChat();
        }
      });

      // Si soy moderador o líder, cargar solicitudes
      if (_canModerate) {
        final requests = await _animeRepo.fetchGroupJoinRequests(widget.group['id']);
        if (mounted) {
          setState(() {
            _pendingRequests = requests;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (showLoader) setState(() => _isLoading = false);
    }
  }

  bool get _isLeader {
    final r = _myRole.trim().toUpperCase();
    return r == 'ADMIN' || r == 'LÍDER' || r == 'LIDER' || r == 'LEADER';
  }
  
  bool get _isAdmin {
    final r = _myRole.trim().toUpperCase();
    return _isLeader || r == 'MODERADOR' || r == 'MODERATOR';
  }

  @override
  void dispose() {
    _animeRepo.profileUpdateNotifier.removeListener(_loadDataShort);
    _tabController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    if (_chatChannel != null) {
      _supabase.removeChannel(_chatChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isMember) ...[
            IconButton(
              icon: Icon(_isFavorite ? Icons.star : Icons.star_border, color: _isFavorite ? Colors.amber : onSurface.withOpacity(0.54)),
              onPressed: _toggleFavorite,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: onSurface),
              color: theme.colorScheme.surface,
              onSelected: (val) {
                if (val == 'leave') _leaveGroup();
                if (val == 'edit') _showEditGroupDialog();
              },
              itemBuilder: (context) => [
                if (_isAdmin)
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined, color: onSurface, size: 20),
                        const SizedBox(width: 12),
                        Text("Ajustes del Grupo", style: TextStyle(color: onSurface)),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'leave',
                  child: const Row(
                    children: [
                      Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                      SizedBox(width: 12),
                      Text("Abandonar Grupo", style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primary,
        edgeOffset: 120,
        displacement: 150,
        child: Column(
          children: [
            _buildGroupHeader(),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primary,
              labelColor: AppTheme.primary,
              unselectedLabelColor: onSurface.withOpacity(0.6),
              tabs: [
                const Tab(text: "Animes"),
                if (_isMember) const Tab(text: "Chat"),
                const Tab(text: "Miembros"),
              ],
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
            Expanded(
              child: _isLoading 
                ? const Center(child: Padding(padding: EdgeInsets.only(top: 100), child: CircularProgressIndicator(color: AppTheme.primary)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAnimesTab(),
                      if (_isMember) _buildChatTab(),
                      _buildMembersTab(),
                    ],
                  ),
            ),
          ],
        ),
      ),
      floatingActionButton: (_isMember && _tabController.index == 0) ? FloatingActionButton.extended(
        onPressed: _showAddAnimeSearch,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text("Sugerir Anime", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ) : null,
    );
  }

  Future<void> _toggleFavorite() async {
    setState(() => _isFavorite = !_isFavorite);
    await _animeRepo.toggleGroupFavorite(widget.group['id'], _isFavorite);
  }

  void _showEditGroupDialog() {
    final nameController = TextEditingController(text: (_groupData ?? widget.group)['name'] ?? '');
    final descController = TextEditingController(text: (_groupData ?? widget.group)['description'] ?? '');
    String? base64Image = (_groupData ?? widget.group)['avatar_url'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentGroup = _groupData ?? widget.group;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const Text("Ajustes del Grupo", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              // Selector de Imagen Estilo Crear Grupo
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 400,
                      maxHeight: 400,
                      imageQuality: 50,
                    );
                    
                    if (image != null) {
                      final bytes = await image.readAsBytes();
                      setModalState(() {
                        base64Image = 'data:image/png;base64,${base64Encode(bytes)}';
                      });
                    }
                  },
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.5), width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (base64Image != null && base64Image!.isNotEmpty)
                      ? WebSafeImage(
                          url: base64Image!, 
                          fit: BoxFit.cover,
                          borderRadius: BorderRadius.circular(18), // Un poco menos que el contenedor para encajar en el borde
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_rounded, color: AppTheme.primary),
                            SizedBox(height: 4),
                            Text("Cambiar Foto", style: TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: AppTheme.inputDecoration("Nombre del grupo", Icons.group),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                decoration: AppTheme.inputDecoration("Descripción", Icons.description),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: Text(((_groupData ?? widget.group)['is_public'] ?? true) ? "Grupo Público" : "Grupo Privado", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(((_groupData ?? widget.group)['is_public'] ?? true) 
                  ? "Cualquiera podrá unirse sin aprobación previa." 
                  : "Los nuevos miembros necesitarán aprobación.", 
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                value: (_groupData ?? widget.group)['is_public'] ?? true,
                activeColor: AppTheme.primary,
                onChanged: (bool value) async {
                  try {
                    // Actualización visual inmediata en el modal
                    setModalState(() {
                      widget.group['is_public'] = value;
                      if (_groupData != null) _groupData!['is_public'] = value;
                    });
                    
                    await _animeRepo.updateGroupPrivacy(widget.group['id'], value);
                    _loadData(showLoader: false);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                    // Revertir en caso de error
                    setModalState(() {
                      widget.group['is_public'] = !value;
                      if (_groupData != null) _groupData!['is_public'] = !value;
                    });
                  }
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (_isLeader) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _confirmDeleteGroup,
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                        child: const Text("BORRAR GRUPO"),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await _animeRepo.updateGroupInfo(widget.group['id'], nameController.text, descController.text ?? '', base64Image ?? '');
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Grupo actualizado correctamente")));
                            _loadData(); // Refrescar para ver los cambios
                          }
                        } catch (e) {
                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black),
                      child: const Text("GUARDAR"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    ),
  );
}

  Future<void> _leaveGroup() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Abandonar Grupo", style: TextStyle(color: Colors.white)),
        content: const Text(
          "¿Estás seguro de que quieres abandonar esta comunidad? Podrás volver a unirte (o solicitar entrada) más adelante.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCELAR")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("ABANDONAR", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _animeRepo.leaveGroup(widget.group['id']);
        if (context.mounted) {
          Navigator.of(context).pop(); // Vuelve a la lista de grupos
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Has abandonado el grupo")));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _confirmDeleteGroup() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("¿Borrar Grupo?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Esta acción es irreversible. Se eliminarán todos los miembros, animes y votos asociados a esta comunidad.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCELAR")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("BORRAR DEFINITIVAMENTE", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      
      try {
        await _animeRepo.deleteGroup(widget.group['id']);
        if (mounted) {
          // Usamos Navigator.pop dos veces de forma segura: 
          // 1. Cerramos el BottomSheet de Ajustes
          // 2. Cerramos la pantalla de GroupDetail
          int count = 0;
          Navigator.of(context).popUntil((route) {
            return count++ >= 2;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Grupo eliminado correctamente")),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          // Limpieza agresiva de "Exception:" y "Error:" repetidos
          String errorMsg = e.toString().replaceAll('Exception:', '').replaceAll('Error:', '').trim();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: $errorMsg"),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Widget _buildGroupHeader() {
    final group = _groupData ?? widget.group;
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.transparent,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WebSafeImage(
                url: _stableAvatarUrl ?? group['avatar_url'] ?? '',
                imageBytes: _avatarBytes,
                width: 80,
                height: 80,
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group['name'],
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      group['description'] ?? 'Sin descripción',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.people, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 4),
                        Text("$_memberCount miembros", style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                        if (_isMember) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isLeader ? AppTheme.secondary.withOpacity(0.2) : 
                                     _isAdmin ? AppTheme.neonCyan.withOpacity(0.2) : Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _isLeader ? 'ADMIN' : 
                              _isAdmin ? 'MODERADOR' : 'MIEMBRO',
                              style: TextStyle(
                                fontSize: 9, 
                                fontWeight: FontWeight.bold, 
                                color: _isLeader ? AppTheme.secondary : 
                                       _isAdmin ? AppTheme.neonCyan : AppTheme.onSurfaceVariant
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_isMember) ...[
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  final group = _groupData ?? widget.group;
                  if (group['is_public'] == false) {
                    _animeRepo.requestToJoinGroup(group['id']).then((_) {
                       ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Solicitud enviada al admin."))
                      );
                    });
                  } else {
                    _animeRepo.joinGroup(group['id']).then((_) => _loadData());
                  }
                },
                icon: const Icon(Icons.group_add_rounded, size: 20),
                label: Text((_groupData ?? widget.group)['is_public'] == false ? "SOLICITAR UNIRSE" : "UNIRSE AL GRUPO"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  minimumSize: const Size(260, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimesTab() {
    if (_groupAnimes.isEmpty) {
      return _buildEmptyState(Icons.movie_filter_outlined, "No hay animes en este grupo.\n¡Añade la primera serie!");
    }

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 140, left: 16, right: 16, top: 16),
      itemCount: _groupAnimes.length,
      itemBuilder: (context, index) {
        final item = _groupAnimes[index];
        final anime = item['anime'] as Anime;
        final double avgRating = (item['avg_rating'] as num?)?.toDouble() ?? 0.0;
        final int totalVotes = (item['total_votes'] as num?)?.toInt() ?? 0;
        final double? myRating = (item['my_rating'] as num?)?.toDouble();
        final String myStatus = item['my_status']?.toString() ?? 'No en mi lista';
        final String myOpinion = item['my_opinion']?.toString() ?? '';
        final int myEpisodes = (item['my_episodes'] as num?)?.toInt() ?? 0;
        final int totalEpisodes = anime.episodes;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)),
                ).then((_) => _loadData(showLoader: false)),
                child: WebSafeImage(url: wrapImageProxy(anime.imageUrl), width: 70, height: 100, borderRadius: BorderRadius.circular(12)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)),
                            ).then((_) => _loadData(showLoader: false)),
                            child: Text(
                              anime.title, 
                              style: TextStyle(
                                fontWeight: FontWeight.bold, 
                                fontSize: 16, 
                                color: onSurface
                              )
                            ),
                          ),
                        ),
                        if (_isAdmin) IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => _confirmDeleteAnime(anime),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            avgRating == 0 ? "Sin notas" : avgRating.toStringAsFixed(1),
                            style: TextStyle(color: onSurface, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Text("($totalVotes votos)", style: TextStyle(color: onSurfaceVariant, fontSize: 12)),
                          if (_isMember) ...[
                            const Spacer(),
                            if (totalVotes > 0) TextButton(
                              onPressed: () => _showGroupRatingsModal(anime.malId, anime.title),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text("Ver valoraciones", style: TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                    ),
                    if (_isMember) ...[
                      if (myOpinion.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          "\"$myOpinion\"",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: onSurfaceVariant, fontSize: 10, fontStyle: FontStyle.italic),
                        ),
                      ] else ...[
                        const SizedBox(height: 6),
                        Text(
                          "\"Sin comentarios\"",
                          style: TextStyle(color: onSurfaceVariant.withOpacity(0.5), fontSize: 10, fontStyle: FontStyle.italic),
                        ),
                      ],
                      const SizedBox(height: 10),
                      // SECTOR DE EPISODIOS Y ESTADO
                      Row(
                        children: [
                          // Contador de Episodios
                          _buildEpisodeCounter(anime, myEpisodes, totalEpisodes),
                          const SizedBox(width: 8),
                          // Selector de Estado
                          Expanded(child: _buildStatusSelector(anime, myStatus)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // BOTÓN DE PUNTUAR (Alineado a la derecha)
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => _showRatingPicker(anime.malId, myRating ?? 0.0, initialOpinion: myOpinion),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: myRating != null ? AppTheme.primary.withOpacity(0.1) : theme.colorScheme.onSurface.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: myRating != null ? AppTheme.primary : Colors.transparent),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 12, color: myRating != null ? AppTheme.primary : onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  myRating != null ? myRating.toStringAsFixed(1) : "Puntuar",
                                  style: TextStyle(
                                    color: myRating != null ? AppTheme.primary : onSurfaceVariant,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEpisodeCounter(Anime anime, int current, int total) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildEpButton(Icons.remove, () {
            if (current > 0) _updateEpisodes(anime, current - 1);
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              "$current / $total CP",
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          _buildEpButton(Icons.add, () {
            if (current < total) {
              _updateEpisodes(anime, current + 1);
            }
          }),
        ],
      ),
    );
  }

  Widget _buildEpButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: AppTheme.primary),
      ),
    );
  }

  Future<bool> _showRegressionConfirmation(String animeTitle) async {
    final theme = Theme.of(context);
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text("¿Estás seguro?", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: Text(
          "Si bajas el progreso de '$animeTitle', tu valoración y reseña se eliminarán automáticamente ya que el anime dejará de estar 'Visto'.",
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancelar", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Estoy seguro", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _updateEpisodes(Anime anime, int newCount) async {
    // 0. Verificar si requiere confirmación (Solo si regrese de 'Visto' con nota)
    final index = _groupAnimes.indexWhere((item) => (item['anime'] as Anime).malId == anime.malId);
    if (index != -1) {
      final oldStatus = _groupAnimes[index]['my_status'];
      final myRating = _groupAnimes[index]['my_rating'];
      
      if (oldStatus == 'Visto' && newCount < (anime.episodes ?? 0) && myRating != null) {
        bool confirm = await _showRegressionConfirmation(anime.title);
        if (!confirm) return;
      }
    }

  // 1. Actualización Optimista
  int? oldProgress;
  String? oldStatus;
  bool statusChanged = false;

  setState(() {
    final index = _groupAnimes.indexWhere((item) => (item['anime'] as Anime).malId == anime.malId);
    if (index != -1) {
      oldProgress = _groupAnimes[index]['my_episodes'];
      oldStatus = _groupAnimes[index]['my_status'];
      _groupAnimes[index]['my_episodes'] = newCount;
      
      String targetStatus = oldStatus ?? 'Pendiente';
      
      // LÓGICA DE ESTADO AUTOMÁTICA
      if (newCount == 0) {
        targetStatus = 'Pendiente';
      } else if (newCount == anime.episodes) {
        targetStatus = 'Visto';
      } else {
        targetStatus = 'Viendo';
      }

      if (targetStatus != oldStatus) {
        _groupAnimes[index]['my_status'] = targetStatus;
        statusChanged = true;
        
        // Si ya no está "Visto", quitamos la valoración automáticamente
        if (oldStatus == 'Visto' && targetStatus != 'Visto') {
          _groupAnimes[index]['my_rating'] = null;
          _groupAnimes[index]['my_opinion'] = null;
        }
      }
    }
  });

  try {
    // 2. Guardado en segundo plano
    await _animeRepo.updateEpisodeProgress(anime.malId, newCount);
    
    // 3. Si hubo cambio de estado, sincronizar con el perfil
    if (statusChanged) {
      final index = _groupAnimes.indexWhere((item) => (item['anime'] as Anime).malId == anime.malId);
      if (index != -1) {
        final newStatus = _groupAnimes[index]['my_status'];
        await _animeRepo.updateUserAnimeStatus(anime.malId, newStatus);
        
        // Si el estado ya no es Visto, eliminar la valoración de la base de datos
        if (newStatus != 'Visto') {
          await _animeRepo.removeReview(anime.malId);
        }
        
        // NO recargar inmediatamente para evitar que el estado antiguo del servidor sobreescriba el local optimista
      }
    }
  } catch (e) {
    // 4. Revertir si hay error
    if (oldProgress != null) {
      setState(() {
        final index = _groupAnimes.indexWhere((item) => (item['anime'] as Anime).malId == anime.malId);
        if (index != -1) {
          _groupAnimes[index]['my_episodes'] = oldProgress;
          if (oldStatus != null) _groupAnimes[index]['my_status'] = oldStatus;
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al sincronizar: $e")));
  }
}

  Widget _buildStatusSelector(Anime anime, String currentStatus) {
    final theme = Theme.of(context);
    final Map<String, Color> statusColors = {
      'Visto': Colors.blue,
      'Viendo': Colors.green,
      'Pendiente': Colors.orange,
      'No en mi lista': theme.colorScheme.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: (statusColors[currentStatus] ?? theme.colorScheme.onSurface.withOpacity(0.1)).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (statusColors[currentStatus] ?? theme.colorScheme.onSurface.withOpacity(0.1)).withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentStatus,
          isExpanded: true,
          dropdownColor: theme.colorScheme.surface,
          icon: Icon(Icons.keyboard_arrow_down, size: 16, color: theme.colorScheme.onSurfaceVariant),
          style: TextStyle(color: statusColors[currentStatus] ?? theme.colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.bold),
          items: statusColors.keys.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value, style: TextStyle(color: theme.colorScheme.onSurface)),
            );
          }).toList(),
          onChanged: (newStatus) async {
            if (newStatus != null) {
              try {
                await _animeRepo.updateUserAnimeStatus(anime.malId, newStatus);
                _loadData(showLoader: false);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildMembersTab() {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

    return Column(
      children: [
        // SOLO LÍDERES Y MODERADORES VEN LAS SOLICITUDES
        if (_canModerate && _pendingRequests.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text("SOLICITUDES PENDIENTES", style: TextStyle(color: onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ],
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _pendingRequests.length,
              itemBuilder: (context, idx) {
                final req = _pendingRequests[idx];
                final profile = req['profile'] as Map<String, dynamic>;
                return Container(
                  width: 220,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      WebSafeImage(
                        url: profile['avatar_url'] ?? '', 
                        imageBytes: _avatarByteCache[profile['avatar_url'] ?? ''],
                        width: 44, 
                        height: 44, 
                        borderRadius: BorderRadius.circular(22),
                        useFadeIn: false,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(profile['username'] ?? 'Usuario', style: TextStyle(color: onSurface, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                            Row(
                              children: [
                                InkWell(
                                  onTap: () => _handleJoinRequest(req['id'], true),
                                  child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
                                ),
                                const SizedBox(width: 12),
                                InkWell(
                                  onTap: () => _handleJoinRequest(req['id'], false),
                                  child: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 28),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Divider(height: 32, indent: 16, endIndent: 16, color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
        ],

        // LISTA DE MIEMBROS
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              final profile = member['profiles'] as Map<String, dynamic>;
              final String role = member['role'] ?? 'MIEMBRO';
              final String userId = member['user_id'];
              final bool isMe = userId == _animeRepo.currentUser?.id;
              final bool isFriend = _friendIds.contains(userId);

              final String cleanRole = role.toUpperCase();
              String roleDisplay = 'Miembro';
              if (cleanRole == 'LÍDER' || cleanRole == 'ADMIN') roleDisplay = 'Admin';
              if (cleanRole == 'MODERADOR') roleDisplay = 'Moderador';

              return ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: profile))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: WebSafeImage(
                  url: profile['avatar_url'] ?? '', 
                  imageBytes: _avatarByteCache[profile['avatar_url'] ?? ''],
                  width: 50, 
                  height: 50, 
                  borderRadius: BorderRadius.circular(25),
                  useFadeIn: false,
                ),
                title: Text(profile['full_name'] ?? profile['username'] ?? 'Usuario', style: TextStyle(color: onSurface, fontWeight: FontWeight.bold)),
                subtitle: _isMember ? Text(
                  roleDisplay.toUpperCase(), 
                  style: TextStyle(
                    color: roleDisplay == 'Admin' ? Colors.amber : (roleDisplay == 'Moderador' ? Colors.blue : AppTheme.primary), 
                    fontSize: 10, 
                    fontWeight: FontWeight.bold
                  )
                ) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isMe && !isFriend) IconButton(
                      icon: const Icon(Icons.person_add_outlined, color: AppTheme.primary, size: 20),
                      onPressed: () => _handleAddFriend(userId, profile['username']),
                    ),
                    if (_canModerate && !isMe) PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: onSurfaceVariant),
                      tooltip: "",
                      color: theme.colorScheme.surface,
                      onSelected: (val) => _handleModeration(val, userId, cleanRole),
                      itemBuilder: (context) => [
                        if (_isLeader && cleanRole != 'LÍDER')
                          const PopupMenuItem(value: 'make_leader', child: Text("Hacer Admin", style: TextStyle(color: Colors.amber))),
                        if (_isLeader && cleanRole == 'MIEMBRO')
                          const PopupMenuItem(value: 'promote', child: Text("Hacer Moderador", style: TextStyle(color: Colors.blue))),
                        if (_isLeader && cleanRole == 'MODERADOR')
                          PopupMenuItem(value: 'demote', child: Text("Quitar Moderador", style: TextStyle(color: onSurface))),
                        if (_canKick(cleanRole))
                          const PopupMenuItem(value: 'kick', child: Text("Expulsar", style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _handleJoinRequest(String requestId, bool accept) async {
    try {
      await _animeRepo.handleGroupJoinRequest(requestId, accept);
      _loadData(showLoader: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accept ? "Solicitud aceptada" : "Solicitud rechazada"))
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  bool _canKick(String targetRole) {
    final String myCleanRole = _myRole.toUpperCase();
    final String targetCleanRole = targetRole.toUpperCase();
    
    if (myCleanRole == 'ADMIN' || myCleanRole == 'LÍDER' || myCleanRole == 'LEADER') return true;
    if ((myCleanRole == 'MODERADOR' || myCleanRole == 'MODERATOR') && 
        (targetCleanRole == 'MIEMBRO' || targetCleanRole == 'MEMBER' || targetCleanRole == 'USER')) return true;
    return false;
  }

  Future<void> _handleModeration(String action, String userId, String currentRole) async {
    try {
      if (action == 'promote') {
        await _animeRepo.updateGroupMemberRole(widget.group['id'], userId, 'MODERADOR');
      } else if (action == 'demote') {
        bool? confirm = await _showConfirmDialog("¿Quitar Moderador?", "¿Quieres quitar los permisos de moderación a este usuario?");
        if (confirm == true) {
          await _animeRepo.updateGroupMemberRole(widget.group['id'], userId, 'MIEMBRO');
        } else {
          return;
        }
      } else if (action == 'kick') {
        bool? confirm = await _showConfirmDialog("¿Expulsar usuario?", "¿Estás seguro de que quieres eliminar a este usuario del grupo?");
        if (confirm == true) {
          await _animeRepo.removeGroupMember(widget.group['id'], userId);
        } else {
          return;
        }
      } else if (action == 'make_leader') {
        bool? confirm = await _showConfirmDialog("¿Traspasar Admin?", "Pasarás a ser un miembro normal y este usuario será el nuevo admin del grupo. ¿Estás seguro?");
        if (confirm == true) {
          await _animeRepo.transferLeadership(widget.group['id'], userId);
          if (mounted) Navigator.pop(context); // Cerrar pantalla actual para refrescar desde fuera
        } else {
          return;
        }
      }
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _handleAddFriend(String userId, String username) async {
    try {
      await _animeRepo.sendFriendRequest(userId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Solicitud enviada a $username")));
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmDeleteAnime(Anime anime) async {
    bool? confirm = await _showConfirmDialog("Quitar Anime", "¿Quieres eliminar '${anime.title}' de la lista del grupo?");
    if (confirm == true) {
      try {
        await _animeRepo.deleteGroupAnime(widget.group['id'], anime.malId);
        _loadData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text(title, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: Text(content, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Confirmar", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String text) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7), fontSize: 16),
          ),
        ],
      ),
    );
  }

  void _showRatingPicker(int animeId, double currentRating, {String initialOpinion = ''}) {
    double tempRating = currentRating == 0 ? 5.0 : currentRating;
    final opinionController = TextEditingController(text: initialOpinion);
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Puntuar para el grupo", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
              if (currentRating > 0)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    setState(() => _isLoading = true);
                    try {
                      await _animeRepo.deleteRating(widget.group['id'], animeId);
                      _loadData(showLoader: false);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text("Quitar nota", style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tempRating.toStringAsFixed(1), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                Slider(
                  value: tempRating,
                  min: 1,
                  max: 10,
                  divisions: 90, 
                  activeColor: AppTheme.primary,
                  onChanged: (val) => setDialogState(() => tempRating = val),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: opinionController,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                  maxLines: 3,
                  decoration: AppTheme.inputDecoration("Tu opinión (opcional)", Icons.comment_outlined).copyWith(
                    hintText: "¿Qué te ha parecido este anime?",
                    hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _animeRepo.rateGroupAnime(
                    widget.group['id'], 
                    animeId, 
                    tempRating, 
                    opinion: opinionController.text.trim()
                  );
                  Navigator.pop(context);
                  _loadData(showLoader: false);
                } catch (e) {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black),
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddAnimeSearch() {
    final searchController = TextEditingController();
    List<Anime> searchResults = [];
    bool isSearching = false;
    final theme = Theme.of(context);

    // Cargar algunos animes iniciales para que no esté vacío
    _animeRepo.fetchAnimes(orderFilter: 'Puntuación').then((results) {
      // Resultados cargados
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Timer? debounce;
          // Cargar iniciales una sola vez al abrir
          if (searchResults.isEmpty && !isSearching && searchController.text.isEmpty) {
            isSearching = true;
            _animeRepo.fetchAnimes(orderFilter: 'Puntuación').then((results) {
              if (context.mounted) {
                setSheetState(() {
                  final List<Anime> list = results['list'] ?? [];
                  searchResults = list.take(10).toList();
                  isSearching = false;
                });
              }
            });
          }

          Future<void> performSearch() async {
            if (searchController.text.isEmpty) return;
            setSheetState(() => isSearching = true);
            try {
              final results = await _animeRepo.searchAnime(searchController.text);
              if (context.mounted) {
                setSheetState(() {
                  searchResults = results;
                  isSearching = false;
                });
              }
            } catch (e) {
              if (context.mounted) setSheetState(() => isSearching = false);
            }
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text("Añadir Anime al Grupo", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 20),
                TextField(
                  controller: searchController,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  onChanged: (val) {
                    if (debounce?.isActive ?? false) debounce?.cancel();
                    debounce = Timer(const Duration(milliseconds: 500), () {
                      performSearch();
                    });
                  },
                  decoration: AppTheme.inputDecoration("Buscar anime...", Icons.search),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: isSearching 
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : searchResults.isEmpty 
                      ? Center(child: Text("No se encontraron resultados", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final anime = searchResults[index];
                            // Verificar si ya está en el grupo
                            final bool alreadyInGroup = _groupAnimes.any((ga) => (ga['anime'] as Anime).malId == anime.malId);

                            return ListTile(
                              leading: WebSafeImage(url: wrapImageProxy(anime.imageUrl), width: 40, height: 60, borderRadius: BorderRadius.circular(8)),
                              title: Text(anime.title, style: TextStyle(color: theme.colorScheme.onSurface)),
                              subtitle: Text("${anime.year} • ${anime.score}", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                              trailing: alreadyInGroup 
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : IconButton(
                                    icon: const Icon(Icons.add_circle, color: AppTheme.primary),
                                    onPressed: () async {
                                      try {
                                        await _animeRepo.addGroupAnime(widget.group['id'], anime.malId);
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          _loadData();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("${anime.title} añadido al grupo"))
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')))
                                          );
                                        }
                                      }
                                    },
                                  ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showGroupRatingsModal(int animeId, String animeTitle) async {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _animeRepo.fetchGroupDetailedRatings(widget.group['id'], animeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: AppTheme.primary)));
          }
          final ratings = snapshot.data ?? [];
          return Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Valoraciones: $animeTitle", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                if (ratings.isEmpty)
                  SizedBox(
                    height: 100,
                    child: Center(child: Text("Nadie ha valorado aún", style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: ratings.length,
                      itemBuilder: (context, idx) {
                        final r = ratings[idx];
                        final profile = r['profile'] as Map<String, dynamic>? ?? {};
                        final double rating = (r['rating'] as num).toDouble();
                        final String opinion = r['opinion']?.toString() ?? '';
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(16)
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              WebSafeImage(url: profile['avatar_url'] ?? '', width: 40, height: 40, borderRadius: BorderRadius.circular(20)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Text(profile['username'] ?? 'Usuario', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
                                            if (r['isMe'] == true) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(4)),
                                                child: const Text("TÚ", style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
                                              ),
                                            ] else if (r['isFriend'] == true) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.3), borderRadius: BorderRadius.circular(4)),
                                                child: const Text("AMIGO", style: TextStyle(color: Colors.blueAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            const Icon(Icons.star, color: Colors.amber, size: 14),
                                            const SizedBox(width: 4),
                                            Text(rating.toStringAsFixed(1), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      opinion.isEmpty ? "\"Sin comentarios\"" : "\"$opinion\"",
                                      style: TextStyle(
                                        color: opinion.isEmpty ? theme.colorScheme.onSurfaceVariant.withOpacity(0.5) : theme.colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showJoinRequestsModal() async {
    final requests = await _animeRepo.fetchGroupJoinRequests(widget.group['id']);
    // Actualizar caché para las fotos en el modal
    _updateCacheForList(requests, 'avatar_url');
    final theme = Theme.of(context);
    
    if (mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Solicitudes de Unión", 
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)
                ),
                const SizedBox(height: 20),
                if (requests.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text("No hay solicitudes pendientes.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5))),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: requests.length,
                      separatorBuilder: (_, __) => Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
                      itemBuilder: (context, index) {
                        final req = requests[index];
                        final profile = req['profile'] as Map<String, dynamic>;
                        
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: WebSafeImage(
                            url: profile['avatar_url'] ?? '', 
                            imageBytes: _avatarByteCache[profile['avatar_url'] ?? ''],
                            width: 44, 
                            height: 44, 
                            borderRadius: BorderRadius.circular(22),
                            useFadeIn: false,
                          ),
                          title: Text(profile['username'] ?? 'Usuario', style: TextStyle(color: theme.colorScheme.onSurface)),
                          subtitle: Text("Quiere unirse al grupo", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                onPressed: () async {
                                  await _animeRepo.respondToJoinRequest(req['id'], widget.group['id'], req['user_id'], true);
                                  setModalState(() => requests.removeAt(index));
                                  _loadData();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                onPressed: () async {
                                  await _animeRepo.respondToJoinRequest(req['id'], widget.group['id'], req['user_id'], false);
                                  setModalState(() => requests.removeAt(index));
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildChatTab() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
            ? Center(child: Text("¡Di hola al grupo! 👋", style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5))))
            : ListView.builder(
                controller: _chatScrollController,
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isMe = msg['user_id'] == _animeRepo.currentUser?.id;
                  final profile = msg['profile'] as Map<String, dynamic>? ?? {};
                  
                  return _buildChatBubble(msg, isMe, profile);
                },
              ),
        ),
        _buildChatInput(),
      ],
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> msg, bool isMe, Map<String, dynamic> profile) {
    final theme = Theme.of(context);
    final userId = msg['user_id'];
    String roleName = 'Miembro';
    Color roleColor = theme.colorScheme.onSurfaceVariant.withOpacity(0.5);

    try {
      final member = _members.firstWhere((m) => m['user_id'] == userId);
      final r = (member['role'] ?? 'Miembro').toString().toUpperCase().trim();
      if (r == 'ADMIN' || r == 'LÍDER' || r == 'LIDER' || r == 'LEADER') {
        roleName = 'Admin';
        roleColor = Colors.amber;
      } else if (r == 'MODERADOR' || r == 'MODERATOR') {
        roleName = 'Moderador';
        roleColor = Colors.blue;
      }
    } catch (_) {}

    // Intentar usar el perfil MÁS RECIENTE de la lista de miembros
    final Map<String, dynamic> currentProfile = _memberProfileMap[userId] ?? profile;
    // Priorizamos nombre público si está disponible
    final String displayName = currentProfile['full_name'] ?? currentProfile['username'] ?? 'Usuario';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userProfile: currentProfile))),
              child: WebSafeImage(
                url: currentProfile['avatar_url'] ?? '',
                imageBytes: _avatarByteCache[currentProfile['avatar_url'] ?? ''],
                width: 32,
                height: 32,
                borderRadius: BorderRadius.circular(10),
                useFadeIn: false,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe) 
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(displayName, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Text(roleName, style: TextStyle(color: roleColor, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? AppTheme.primary : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                    ),
                    child: Text(
                      msg['content'] ?? '',
                      style: TextStyle(color: isMe ? Colors.black : theme.colorScheme.onSurface, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput() {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12, 
        bottom: MediaQuery.of(context).padding.bottom + 12
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: "Escribe un mensaje...",
                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  void _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    
    HapticFeedback.lightImpact();
    _chatController.clear();
    await _animeRepo.sendGroupMessage(widget.group['id'], text);
    // El mensaje aparecerá automáticamente vía Realtime
  }
}
