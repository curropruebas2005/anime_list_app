import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../theme.dart';
import '../models/anime.dart';
import '../repositories/anime_repository.dart';
import 'profile_screen.dart';
import 'group_detail_screen.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/web_safe_image.dart';
import '../utils/image_utils.dart';

class GroupsTabScreen extends StatefulWidget {
  final ScrollController? scrollController;
  const GroupsTabScreen({super.key, this.scrollController});

  @override
  State<GroupsTabScreen> createState() => _GroupsTabScreenState();
}

class _GroupsTabScreenState extends State<GroupsTabScreen> {
  int _selectedTab = 0; // 0: Mis Grupos, 1: Explorar
  final _animeRepo = AnimeRepository();
  bool _isLoading = true;
  
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> _exploreGroups = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  final TextEditingController _searchController = TextEditingController(); // Search for Explore
  final TextEditingController _mySearchController = TextEditingController(); // Search for My Groups
  String _myQuery = "";
  Timer? _mySearchDebounce;
  Timer? _exploreSearchDebounce;

  // Paginación para Explorar
  late final ScrollController _scrollController;
  final ScrollController _localScrollController = ScrollController();
  int _explorePage = 0;
  bool _isLoadingMoreExplore = false;
  bool _hasMoreExplore = true;
  final int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? _localScrollController;
    _loadData();
    _searchController.addListener(_onExploreSearchChanged);
    _mySearchController.addListener(_onMySearchChanged);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
        if (_selectedTab == 1 && !_isLoadingMoreExplore && _hasMoreExplore && !_isLoading) {
          _loadMoreExplore();
        }
      }
    });
  }

  void _onMySearchChanged() {
    if (_mySearchDebounce?.isActive ?? false) _mySearchDebounce!.cancel();
    _mySearchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _myQuery = _mySearchController.text.toLowerCase());
      }
    });
  }

  void _onExploreSearchChanged() {
    if (_exploreSearchDebounce?.isActive ?? false) _exploreSearchDebounce!.cancel();
    _exploreSearchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _selectedTab == 1) {
        _searchExplore();
      }
    });
  }

  @override
  void dispose() {
    _mySearchDebounce?.cancel();
    _exploreSearchDebounce?.cancel();
    _searchController.dispose();
    _mySearchController.dispose();
    if (widget.scrollController == null) {
      _localScrollController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _explorePage = 0;
      _hasMoreExplore = true;
    });
    await Future.wait([
      _loadMyGroups(),
      _searchExplore(refresh: true),
      _loadPendingRequests(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMyGroups() async {
    final groups = await _animeRepo.fetchUserGroups();
    if (mounted) {
      setState(() => _myGroups = groups);
      // Precarga de avatares en segundo plano
      for (var gm in groups) {
        String? url = gm['groups']?['avatar_url'];
        if (url != null && url.isNotEmpty) {
          precacheImage(getImageProvider(url), context).catchError((_) => null);
        }
      }
    }
  }

  Future<void> _searchExplore({bool refresh = true}) async {
    if (refresh) {
      _explorePage = 0;
      _hasMoreExplore = true;
    } else {
      setState(() => _isLoadingMoreExplore = true);
    }

    final query = _searchController.text.trim();
    final groups = await _animeRepo.searchExploreGroups(query, page: _explorePage, pageSize: _pageSize);
    
    // Filtrar para que no salgan grupos en los que ya estoy
    final newGroups = groups.where((g) => g['isMember'] != true).toList();
    
    if (mounted) {
      setState(() {
        if (refresh) {
          _exploreGroups = newGroups;
        } else {
          _exploreGroups.addAll(newGroups);
        }
        _hasMoreExplore = groups.length == _pageSize;
        _isLoadingMoreExplore = false;
      });

      // Precarga de avatares de exploración
      for (var g in newGroups) {
        String? url = g['avatar_url'];
        if (url != null && url.isNotEmpty) {
          precacheImage(getImageProvider(url), context).catchError((_) => null);
        }
      }
    }
  }

  Future<void> _loadMoreExplore() async {
    _explorePage++;
    await _searchExplore(refresh: false);
  }

  Future<void> _loadPendingRequests() async {
    final requests = await _animeRepo.fetchAllPendingGroupRequests();
    if (mounted) setState(() => _pendingRequests = requests);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlobalAppBar(
        titleWidget: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppTheme.primary, Color(0xFFD095FF)],
          ).createShader(bounds),
          child: const Text('Comunidad', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white)),
        ),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadData,
            color: AppTheme.primary,
            edgeOffset: MediaQuery.of(context).padding.top + 100,
            displacement: 150,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 80, 
                bottom: 125, 
                left: (MediaQuery.of(context).size.width * 0.05).clamp(16.0, 32.0), 
                right: (MediaQuery.of(context).size.width * 0.05).clamp(16.0, 32.0)
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildTabButton("Mis Grupos", 0),
                          _buildTabButton("Explorar", 1),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  if (_isLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.only(top: 200),
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ))
                  else
                    _selectedTab == 0 ? _buildMyGroupsView() : _buildExploreView(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedTab == 0 ? Padding(
        padding: const EdgeInsets.only(bottom: 125),
        child: FloatingActionButton.extended(
          onPressed: _showCreateGroupDialog,
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Text("Crear Grupo", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ) : null,
    );
  }

  Widget _buildTabButton(String title, int index) {
    bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildMyGroupsView() {
    // 1. Filtrar los que contienen el texto
    final filtered = _myGroups.where((m) {
      final name = (m['groups']?['name'] ?? '').toString().toLowerCase();
      return name.contains(_myQuery);
    }).toList();

    // 2. Ordenar: primero los que EMPIEZAN por el texto, luego el resto
    if (_myQuery.isNotEmpty) {
      filtered.sort((a, b) {
        final aName = (a['groups']?['name'] ?? '').toString().toLowerCase();
        final bName = (b['groups']?['name'] ?? '').toString().toLowerCase();
        
        final aStarts = aName.startsWith(_myQuery);
        final bStarts = bName.startsWith(_myQuery);
        
        if (aStarts && !bStarts) return -1;
        if (!aStarts && bStarts) return 1;
        return aName.compareTo(bName);
      });
    }

    return Column(
      children: [
        TextField(
          controller: _mySearchController,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Buscar entre mis grupos...',
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            suffixIcon: _mySearchController.text.isNotEmpty 
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _mySearchController.clear();
                    _onMySearchChanged();
                  },
                )
              : null,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), 
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2))
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), 
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2))
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), 
              borderSide: const BorderSide(color: Color(0xFF00C4FF))
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (filtered.isEmpty)
          _buildEmptyState(
            Icons.group_outlined, 
            _myQuery.isEmpty 
              ? "Aún no perteneces a ningún grupo.\n¡Explora o crea uno propio!"
              : "No se encontraron grupos que coincidan con tu búsqueda."
          )
        else
          ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final groupMember = filtered[index];
              final group = groupMember['groups'] as Map<String, dynamic>;
              return _buildGroupCard(group, isMember: true, role: groupMember['role'], isFavorite: groupMember['is_favorite'] == true);
            },
          ),
      ],
    );
  }

  Widget _buildExploreView() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Buscar grupos por nombre...',
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            suffixIcon: _searchController.text.isNotEmpty 
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _onExploreSearchChanged();
                  },
                )
              : null,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), 
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2))
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), 
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.2))
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), 
              borderSide: const BorderSide(color: Color(0xFF00C4FF))
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_exploreGroups.isEmpty)
          _buildEmptyState(Icons.explore_outlined, "No se encontraron grupos para mostrar.")
        else
          ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _exploreGroups.length + (_isLoadingMoreExplore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index < _exploreGroups.length) {
                final group = _exploreGroups[index];
                return _buildGroupCard(group, isMember: group['isMember'] ?? false);
              } else {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                );
              }
            },
          ),
          if (!_hasMoreExplore && _exploreGroups.length > 5)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  "Eso es todo por ahora 🌐",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                    fontSize: 12,
                    fontWeight: FontWeight.bold
                  )
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group, {required bool isMember, String? role, bool isFavorite = false}) {
    return GestureDetector(
      onTap: () {
        // Enviar también el rol, favorito y conteo inicial para evitar parpadeos visuales al entrar
        final groupData = Map<String, dynamic>.from(group);
        groupData['initial_role'] = role;
        groupData['initial_is_favorite'] = isFavorite;
        groupData['isMember'] = isMember; // Pasamos si ya es miembro
        
        // Extraer conteo de la subconsulta de Supabase
        int mCount = 0;
        if (group['group_members'] != null && (group['group_members'] as List).isNotEmpty) {
          mCount = group['group_members'][0]['count'] ?? 0;
        }
        groupData['initial_member_count'] = mCount;
        
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => GroupDetailScreen(group: groupData)),
        ).then((_) => _loadData());
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                WebSafeImage(
                  url: group['avatar_url'] ?? '', 
                  width: 54, 
                  height: 54, 
                  borderRadius: BorderRadius.circular(12)
                ),
                if (group['is_public'] == false)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.lock_rounded, color: Colors.amber, size: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          group['name'] ?? 'Grupo', 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isFavorite) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                      ],
                      if (role == 'LÍDER' || role == 'MODERADOR' || role == 'ADMIN') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (role == 'LÍDER' || role == 'ADMIN') ? Colors.amber.withOpacity(0.2) : Colors.blue.withOpacity(0.2), 
                            borderRadius: BorderRadius.circular(4)
                          ),
                          child: Text(
                            (role == 'LÍDER' || role == 'ADMIN') ? "ADMIN" : "MODERADOR", 
                            style: TextStyle(
                              fontSize: 8, 
                              fontWeight: FontWeight.w900, 
                              color: (role == 'LÍDER' || role == 'ADMIN') ? Colors.amber : Colors.blue
                            )
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group['description'] ?? 'Sin descripción', 
                    style: TextStyle(color: AppTheme.onSurfaceVariant.withOpacity(0.7), fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!isMember) 
              group['isPending'] == true
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text("Pendiente", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  : ElevatedButton(
                      onPressed: () => group['is_public'] == false 
                          ? _handleRequestJoin(group['id'], group['name'])
                          : _handleJoinAndRefresh(group['id']),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: group['is_public'] == false ? Colors.white10 : AppTheme.primary,
                        foregroundColor: group['is_public'] == false ? Colors.white : Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        group['is_public'] == false ? "Solicitar" : "Unirse", 
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)
                      ),
                    ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(icon, size: 64, color: AppTheme.onSurfaceVariant.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              message, 
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.onSurfaceVariant.withOpacity(0.5), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // --- ACCIONES ---

  Future<void> _handleJoinAndRefresh(String groupId) async {
    try {
      await _animeRepo.joinGroup(groupId);
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _handleRequestJoin(String groupId, String groupName) async {
    try {
      await _animeRepo.requestToJoinGroup(groupId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Solicitud enviada a $groupName. Espera a que el admin te acepte."),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
        )
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleLeaveAndRefresh(String groupId) async {
    try {
      await _animeRepo.leaveGroup(groupId);
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isPublic = true;
    String? base64Image;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
            top: 24,
            left: 24,
            right: 24
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Crear Nueva Comunidad", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              
              Row(
                children: [
                  // Selector de Imagen
                  GestureDetector(
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
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary.withOpacity(0.5), width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: base64Image != null
                        ? WebSafeImage(url: base64Image!, fit: BoxFit.cover, borderRadius: BorderRadius.circular(40))
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_rounded, color: AppTheme.primary),
                              SizedBox(height: 4),
                              Text("Foto", style: TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Text(isPublic ? "Grupo Público" : "Grupo Privado", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          subtitle: Text(isPublic ? "Cualquiera puede unirse" : "Adhesión bajo solicitud", style: const TextStyle(fontSize: 12)),
                          value: isPublic,
                          activeColor: AppTheme.primary,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => setModalState(() => isPublic = val),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: nameController,
                decoration: AppTheme.inputDecoration("Nombre del grupo", Icons.group),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                maxLines: 3,
                decoration: AppTheme.inputDecoration("Descripción", Icons.description),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty) return;
                    try {
                      await _animeRepo.createGroup(
                        nameController.text.trim(), 
                        descController.text.trim(), 
                        base64Image ?? '',
                        isPublic: isPublic
                      );
                      if (mounted) {
                        Navigator.pop(context);
                        _loadData();
                      }
                    } catch (e) {
                      String errorMessage = e.toString().replaceAll('Exception: ', '');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.white),
                                const SizedBox(width: 12),
                                Expanded(child: Text(errorMessage, style: const TextStyle(fontWeight: FontWeight.bold))),
                              ],
                            ),
                            backgroundColor: Colors.red.shade800,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.only(bottom: 16),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("Crear Grupo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(count, style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }

  Widget _buildGroupRequestCard({
    required String requestId, 
    required String groupId, 
    required String userId, 
    required String name, 
    required String groupName, 
    required String imageUrl
  }) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          WebSafeImage(url: wrapImageProxy(imageUrl), width: 44, height: 44, borderRadius: BorderRadius.circular(22)),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          Text(groupName, style: TextStyle(fontSize: 10, color: AppTheme.primary.withOpacity(0.8)), overflow: TextOverflow.ellipsis),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  onPressed: () async {
                    await _animeRepo.respondToJoinRequest(requestId, groupId, userId, true);
                    _loadData();
                  },
                ),
              ),
              Expanded(
                child: IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    await _animeRepo.respondToJoinRequest(requestId, groupId, userId, false);
                    _loadData();
                  },
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
