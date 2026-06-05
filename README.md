# Estructura del Proyecto - Anime List App

## Descripción General
Aplicación Flutter para gestionar una lista de animes con funcionalidades de favoritos, reseñas, grupos y autenticación con Google.

---

## 📁 Estructura de Carpetas

### `/lib`
Carpeta principal que contiene todo el código Dart de la aplicación.

#### **`/lib/models`**
Define los modelos de datos de la aplicación.
- `anime.dart` - Modelo principal para representar un anime con propiedades como título, puntuación, géneros, etc.

#### **`/lib/repositories`**
Capa de acceso a datos que gestiona la comunicación con Supabase.
- `anime_repository.dart` - Maneja todas las operaciones de lectura/escritura de animes, favoritos, reseñas, grupos, amigos, etc.

#### **`/lib/screens`**
Pantallas/vistas de la aplicación. Cada archivo representa una pantalla diferente de la UI.
- `anime_detail_screen.dart` - Detalle completo de un anime
- `friends_tab_screen.dart` - Gestión de amigos
- `full_activity_screen.dart` - Historial de actividades
- `group_detail_screen.dart` - Detalles y gestión de un grupo
- `groups_tab_screen.dart` - Listado de grupos
- `home_screen.dart` - Pantalla principal
- `login_screen.dart` - Autenticación con Google
- `my_list_screen.dart` - Lista personalizada del usuario
- `profile_screen.dart` - Perfil del usuario
- `user_profile_screen.dart` - Perfil de otros usuarios

#### **`/lib/services`**
Servicios especializados para operaciones específicas.
- `anime_service.dart` - Servicio para obtener datos de animes directos de Supabase

#### **`/lib/utils`**
Utilidades y funciones auxiliares.
- `image_utils.dart` - Funciones para procesar y gestionar imágenes

#### **`/lib/widgets`**
Componentes reutilizables de UI.
- `global_app_bar.dart` - Barra de aplicación global personalizada
- `smart_marquee.dart` - Widget de marquesina inteligente para textos largos
- `web_image_stub.dart` - Stub para imágenes web
- `web_image_web.dart` - Implementación de carga de imágenes para web
- `web_safe_image.dart` - Widget seguro para cargar imágenes con fallback

#### **`main.dart`**
Punto de entrada de la aplicación. Configura la app y el acceso a Supabase.

#### **`theme.dart`**
Define el tema global de la aplicación (colores, estilos de texto, etc.)

### `/android`
Configuración específica para Android. Contiene el proyecto Android nativo.

### `/ios`
Configuración específica para iOS. Contiene el proyecto iOS nativo.

### `/test`
Tests unitarios e integración de la aplicación.

### `/dart_tool`
Archivos generados automáticamente por Flutter/Dart (dependencias, cache, etc.). No editar manualmente.

---

## 🔧 Configuración Importante

- **pubspec.yaml** - Dependencias y configuración del proyecto
- **analysis_options.yaml** - Reglas de análisis estático de código

---

## 🚀 Flujo de Datos

1. **UI (Screens)** → Solicita datos
2. **Repository** → Accede a Supabase
3. **Supabase** → Retorna datos
4. **Models** → Transforma datos en objetos Dart
5. **Widgets** → Renderiza en pantalla

---

## 📝 Notas de Desarrollo

- Las pantallas están en `/screens` y son responsables de la UI y user interaction
- La lógica de datos se centraliza en `/repositories`
- Los modelos en `/models` definen la estructura de datos
- Los widgets reutilizables en `/widgets` simplifican el código
