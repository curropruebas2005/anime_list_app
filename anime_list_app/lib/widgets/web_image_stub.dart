import 'package:flutter/material.dart';

Widget platformWebImage(String url, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
  // En móvil/desktop, usamos la carga normal de Flutter que sí funciona sin problemas de CORS
  return Image.network(
    url,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
  );
}
