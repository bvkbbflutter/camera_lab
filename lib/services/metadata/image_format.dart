/// The three image formats this POC supports end-to-end. WebP has two
/// distinct encodings with different metadata-survival characteristics,
/// so callers usually branch on both [ImageFormat] and, for WebP, whether
/// lossless encoding was requested.
enum ImageFormat { jpeg, png, webp }

extension ImageFormatX on ImageFormat {
  String get label => switch (this) {
        ImageFormat.jpeg => 'JPEG',
        ImageFormat.png => 'PNG',
        ImageFormat.webp => 'WebP',
      };

  String get extension => switch (this) {
        ImageFormat.jpeg => 'jpg',
        ImageFormat.png => 'png',
        ImageFormat.webp => 'webp',
      };

  String get mimeType => switch (this) {
        ImageFormat.jpeg => 'image/jpeg',
        ImageFormat.png => 'image/png',
        ImageFormat.webp => 'image/webp',
      };
}
