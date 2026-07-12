String playlistExportFileName({
  required String playlistName,
  required String extension,
}) {
  final normalizedExtension = extension.trim().replaceFirst(RegExp(r'^\.+'), '');
  if (normalizedExtension.isEmpty) {
    throw ArgumentError.value(extension, 'extension', 'must not be empty');
  }

  final sanitizedName = playlistName
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '')
      .trim();
  final baseName = sanitizedName.isEmpty ? 'playlist' : sanitizedName;
  return '$baseName.$normalizedExtension';
}
