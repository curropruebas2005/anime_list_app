import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../utils/image_utils.dart';

class WebSafeImage extends StatelessWidget {
  final String url;
  final Uint8List? imageBytes;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool useFadeIn;

  const WebSafeImage({
    super.key,
    required this.url,
    this.imageBytes,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.useFadeIn = true,
  });

  @override
  Widget build(BuildContext context) {
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      return _wrap(
        child: Image.memory(
          imageBytes!,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        ),
      );
    }

    if (url.trim().isEmpty) return _buildPlaceholder();

    // Carga universal usando el helper unificado
    return _wrap(
      child: Image(
        image: getImageProvider(url),
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || !useFadeIn) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      ),
    );
  }

  Widget _buildBase64Image(String data) {
    try {
      String base64String = data.startsWith('data:image') ? data.split(',').last : data;
      return _wrap(
        child: Image.memory(
          base64Decode(base64String),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        ),
      );
    } catch (e) {
      return _buildPlaceholder();
    }
  }

  Widget _wrap({required Widget child}) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: SizedBox(
        width: width,
        height: height,
        child: child,
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: width,
      height: height,
      color: Colors.white.withValues(alpha: 0.05),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white12),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.white.withValues(alpha: 0.05),
      child: const Icon(Icons.broken_image_outlined, color: Colors.white10, size: 24),
    );
  }
}
