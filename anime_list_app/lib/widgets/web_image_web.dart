import 'dart:html';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

// Mapa para evitar registrar la misma factoría varias veces (causa parpadeo)
final Map<String, bool> _registeredFactories = {};

Widget platformWebImage(String url, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
  // Generamos un ID único y limpio para la vista
  final String viewID = 'web-img-${url.hashCode}';

  // Solo registramos si no existe ya
  if (!_registeredFactories.containsKey(viewID)) {
    ui_web.platformViewRegistry.registerViewFactory(
      viewID,
      (int viewId) => ImageElement()
        ..src = url
        ..crossOrigin = 'anonymous' // Permite mayor compatibilidad con el motor de Flutter
        ..referrerPolicy = 'no-referrer'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = _mapBoxFitToCss(fit)
        ..style.borderRadius = 'inherit',
    );
    _registeredFactories[viewID] = true;
  }

  return SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(
      key: ValueKey(viewID), // Forzamos que Flutter reconozca la vista única
      viewType: viewID,
    ),
  );
}

String _mapBoxFitToCss(BoxFit fit) {
  switch (fit) {
    case BoxFit.cover: return 'cover';
    case BoxFit.contain: return 'contain';
    case BoxFit.fill: return 'fill';
    case BoxFit.fitHeight: return 'contain';
    case BoxFit.fitWidth: return 'contain';
    case BoxFit.none: return 'none';
    case BoxFit.scaleDown: return 'scale-down';
    default: return 'cover';
  }
}
