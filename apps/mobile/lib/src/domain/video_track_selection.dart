bool isSelectableEmbeddedVideoTrackId(String id) {
  final normalized = id.trim().toLowerCase();
  return normalized.isNotEmpty && normalized != 'auto' && normalized != 'no';
}

String videoTrackSelectionLabel({
  required String fallback,
  required int index,
  String? title,
  String? language,
}) {
  final normalizedTitle = title?.trim() ?? '';
  final normalizedLanguage = language?.trim() ?? '';
  if (normalizedTitle.isNotEmpty && normalizedLanguage.isNotEmpty) {
    return '$normalizedTitle ($normalizedLanguage)';
  }
  if (normalizedTitle.isNotEmpty) {
    return normalizedTitle;
  }
  if (normalizedLanguage.isNotEmpty) {
    return normalizedLanguage;
  }
  return '$fallback ${index + 1}';
}
