import 'dart:core';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';

// --- SISTEMA DOBLE CANAL: MÓVIL (DIRECTO) + WEB (PROXY) ---

String wrapImageProxy(String url) {
  if (url.trim().isEmpty) {
    return "https://via.placeholder.com/150?text=No+Image";
  }
  
  String cleanUrl = url.trim();

  // 1. Limpieza de basura
  if (cleanUrl.contains(',') && !cleanUrl.startsWith('data:')) {
    cleanUrl = cleanUrl.split(',').last.trim();
  }

  while (cleanUrl.startsWith('/')) {
    cleanUrl = cleanUrl.substring(1).trim();
  }

  // 2. Base64 (Avatares) directo
  if (cleanUrl.startsWith('data:image') || (cleanUrl.length > 200 && !cleanUrl.contains('.'))) {
    return cleanUrl;
  }

  // 3. Protocolo
  if (!cleanUrl.startsWith('http')) {
    cleanUrl = 'https://' + cleanUrl;
  }

  // 4. LÓGICA DE CANAL DIFERENCIADO
  if (kIsWeb) {
    // --- WEB: Necesitamos Proxy para saltar CORS ---
    if (cleanUrl.contains('myanimelist.net')) {
       final encodedUrl = Uri.encodeComponent(cleanUrl);
       return 'https://images1-focus-opensocial.googleusercontent.com/gadgets/proxy?container=focus&refresh=2592000&url=$encodedUrl';
    }
  }

  // --- MÓVIL (Android/iOS): Carga directa SIEMPRE ---
  return cleanUrl;
}

// Helper para obtener el ImageProvider correcto (Network o Memory)
ImageProvider getImageProvider(String url) {
  final providerUrl = wrapImageProxy(url);
  
  if (providerUrl.startsWith('data:image') || (providerUrl.length > 200 && !providerUrl.contains('.'))) {
    try {
      String base64String = providerUrl.startsWith('data:image') ? providerUrl.split(',').last : providerUrl;
      return MemoryImage(base64Decode(base64String));
    } catch (e) {
      return const NetworkImage("https://via.placeholder.com/150?text=Error");
    }
  }
  
  return NetworkImage(providerUrl);
}
