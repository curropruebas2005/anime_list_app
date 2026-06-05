# Documentación del Proyecto - Anime List App (Tomodachi)

## 1. Descripción general

Este proyecto es una aplicación móvil multiplataforma desarrollada en Flutter, llamada `Tomodachi`, pensada para gestionar listas de anime, perfil de usuario y funciones sociales básicas.

La aplicación integra:
- Autenticación con Supabase (email/password, registro, verificación de email).
- Inicio de sesión con Google.
- Catálogo de anime con filtros, búsqueda y paginación.
- Lista personal de seguimiento del usuario.
- Secciones sociales de amigos y grupos.
- Perfil de usuario con avatar y datos almacenados.
- Tema claro/oscuro salvo que el usuario escoja una preferencia.

---

## 2. Arquitectura principal

### 2.1 Punto de entrada

`lib/main.dart`
- Inicializa Flutter bindings y fuerza orientación vertical.
- Configura Supabase con URL y `anonKey` embebidos.
- Inicializa `themeProvider` y `AnimeRepository`.
- Inicia la aplicación con `MyApp`.

### 2.2 Gestión de tema

`lib/theme.dart`
- Define `AppTheme.lightTheme` y `AppTheme.darkTheme`.
- `ThemeProvider` guarda y carga la preferencia de tema usando `SharedPreferences`.
- `MyApp` utiliza `ListenableBuilder` para reaccionar a cambios de tema.

### 2.3 Flujo de autenticación

`main.dart` -> `AuthGate`
- Escucha `Supabase.instance.client.auth.onAuthStateChange`.
- Redirige a `MainLayout` si hay sesión válida.
- Si no hay sesión o el email no está confirmado, muestra `LoginScreen`.

### 2.4 Layout principal

`lib/screens/main_layout.dart`
- Contiene la barra inferior (`BottomNavigationBar`) con 4 pestañas.
- Usa `IndexedStack` para mantener vivas todas las pestañas y mejorar UX.
- Pestañas:
  - `HomeScreen`
  - `MyListScreen`
  - `FriendsTabScreen`
  - `GroupsTabScreen`
- Precarga de imágenes y perfil en segundo plano al iniciar.

---

## 3. Capas y responsabilidades

### 3.1 UI / Pantallas

Carpeta `lib/screens/`
- `login_screen.dart`: login, registro, Google Sign-In y validación de errores.
- `main_layout.dart`: navegación principal tabulada.
- `home_screen.dart`: catálogo de anime.
- `my_list_screen.dart`: lista personal del usuario.
- `friends_tab_screen.dart`: área de amigos.
- `groups_tab_screen.dart`: área de grupos.
- `anime_detail_screen.dart`: detalle de anime.
- `profile_screen.dart` / `user_profile_screen.dart`: gestión de perfil.
- `group_detail_screen.dart`, `full_activity_screen.dart`: vistas complementarias.

### 3.2 Lógica de negocio / datos

`lib/repositories/anime_repository.dart`
- Singleton `AnimeRepository`.
- Inicializa caché local con `SharedPreferences`.
- Gestiona perfil de usuario cacheado.
- Controla estado de conexión y sincronización.
- Recupera animes desde Supabase con filtros avanzados.
- Guarda caché local de la primera página para soporte offline.
- Publica actualizaciones mediante `ValueNotifier` y `StreamController`.

`lib/services/anime_service.dart`
- Servicio directo para recuperar listas y añadir favoritos.
- Ejemplo de separación entre repositorio de estado y servicio de API.

### 3.3 Modelo

`lib/models/anime.dart`
- Clase `Anime` con campos relevantes:
  - `malId`, `title`, `imageUrl`, `score`, `synopsis`, `status`, `genres`, `demographic`, `year`, `episodes`.
  - Campos opcionales: `myStatus`, `myRating`, `isFavorite`.
- Conversión desde/para `Map<String, dynamic>`.

### 3.4 Utilidades y widgets

`lib/utils/` y `lib/widgets/`
- Soporte para carga de imágenes y web compatibility.
- Componentes personalizados UI reutilizables.

---

## 4. Dependencias principales

`pubspec.yaml` contiene:
- `flutter`
- `supabase_flutter`: backend, auth, base de datos y almacenamiento.
- `cupertino_icons`
- `google_fonts`: tipografías personalizadas.
- `image_picker`: selección de imágenes locales.
- `shared_preferences`: persistencia local ligera.
- `marquee`: textos animados tipo ticker.
- `google_sign_in`: autenticación con Google.

Dev dependencies:
- `flutter_test`
- `flutter_launcher_icons`
- `flutter_lints`

---

## 5. Integraciones externas

### 5.1 Supabase

- Auth de usuarios.
- Tablas consultadas: `animes`, `user_anime_list`, `reviews`, `favorites`.
- Consultas con filtros, orden, paginación y exclusión de elementos.
- Verificación de email y comienzo de sesión condicional.

### 5.2 Google Sign-In

- Uso de `GoogleSignIn` con `serverClientId` para intercambio de token con Supabase.
- Permite acceso social además de la autenticación por email.

---

## 6. Ejecución y preparación para presentación

### 6.1 Comandos necesarios

Desde la raíz del proyecto:
```bash
flutter pub get
flutter run
```

Si deseas ejecutar en Android/iOS específicos:
```bash
flutter run -d chrome
flutter run -d emulator-5554
```

### 6.2 Verificar antes de presentar

- Comprueba que el emulador/dispositivo esté conectado.
- Asegúrate de que el backend de Supabase funciona y no haya límite de conexión.
- Prueba:
  - Registro de usuario y login.
  - Login con Google.
  - Navegación entre pestañas.
  - Búsqueda y filtros en el catálogo.
  - Carga de perfil y avatar.

---

## 7. Puntos fuertes para defender

- Uso de Flutter para app móvil multiplataforma.
- Arquitectura desacoplada entre UI, repositorio, servicios y modelos.
- Integración con un backend real (Supabase) y servicios de autenticación.
- Soporte de tema persistente y experiencia visual moderna.
- Optimización de UX con `IndexedStack` y precarga de imágenes.
- Gestión de estado ligera y eficiente sin complejos frameworks.
- Persistencia parcial offline con caché local.

---

## 8. Puntos de mejora / futuro trabajo

- Mover credenciales de Supabase a variables de entorno o archivo seguro.
- Añadir pruebas unitarias e integración.
- Implementar un `Provider`/`Riverpod`/`BLoC` para una arquitectura más escalable.
- Mejorar la sincronización offline para acciones de usuario pendientes.
- Añadir soporte completo de internacionalización (i18n).

---

## 9. Archivos clave

- `lib/main.dart`
- `lib/theme.dart`
- `lib/models/anime.dart`
- `lib/repositories/anime_repository.dart`
- `lib/services/anime_service.dart`
- `lib/screens/login_screen.dart`
- `lib/screens/main_layout.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/my_list_screen.dart`
- `lib/screens/friends_tab_screen.dart`
- `lib/screens/groups_tab_screen.dart`
- `lib/screens/anime_detail_screen.dart`
- `lib/screens/profile_screen.dart`
- `lib/utils/` y `lib/widgets/`

---

## 10. Observaciones finales

Este proyecto es un buen TFG porque combina:
- Interfaz móvil atractiva.
- Autenticación real y control de sesión.
- Consumo de datos remotos.
- Persistencia en el dispositivo.
- Funcionalidades sociales y de lista personal.

Para la defensa, enfócate en:
- el flujo de usuario,
- la separación de responsabilidades,
- la integración con Supabase,
- y los elementos de diseño que mejoran la experiencia.
